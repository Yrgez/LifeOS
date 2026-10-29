import 'dart:async';
import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';

import '../core/app_log.dart';
import 'key_store.dart';

/// Открывает базу по пути. [password] == null — без шифрования.
typedef DbOpener = Future<Database> Function(String path, {String? password});

class EncryptionException implements Exception {
  final String message;
  EncryptionException(this.message);
  @override
  String toString() => message;
}

/// Имитация внезапного обрыва миграции (убитый процесс, питание). Бросается только из тестового [DbEncryptionManager.debugHook];
/// менеджер не откатывает изменения при ней — как при настоящем обрыве, — а состояние восстанавливает [DbEncryptionManager.recover].
class MigrationInterrupted extends Error {}

/// Шаги миграции — точки, где в тестах моделируется внезапный сбой (питание, убитый процесс).
enum MigrationStep { afterMarker, afterCopy, afterOldMoved, afterSwapped, afterKeyCommitted }

/// Включение и выключение шифрования базы (SQLCipher) с защитой данных на каждом шаге.
///
/// Исходная база **не изменяется и не удаляется**, пока новая копия не создана, не сверена по числу строк
/// во всех таблицах и не подменила исходную. Путь: копия во временный файл → проверка → исходный файл
/// переименовывается в `.premigrate` → копия становится основной → повторная проверка → фиксация ключа →
/// только после этого старый файл затирается и удаляется. На любом сбое исходная база возвращается на место,
/// а прерванная процессом миграция доводится или откатывается при следующем запуске ([recover]).
///
/// Ключ — случайные 32 байта в безопасном хранилище (Android Keystore / iOS Keychain). Пока ключ
/// есть в хранилище, база считается зашифрованной.
class DbEncryptionManager {
  DbEncryptionManager({
    required this.open,
    required this.keys,
    required this.path,
    required this.tables,
    this.debugHook,
  });

  final DbOpener open;
  final KeyStore keys;
  final String path;

  /// Таблицы, которые копируются (см. `SqliteAppRepository.tables`). Неизвестная таблица в базе = отказ
  /// от миграции: данные не должны теряться молча.
  final List<String> tables;

  /// Только для тестов: вызывается после каждого шага; [MigrationInterrupted] имитирует мгновенный сбой.
  final FutureOr<void> Function(MigrationStep step)? debugHook;

  static const keyName = 'db_key';
  static const pendingKeyName = 'db_key_pending';
  static const markerName = 'db_migration';

  String get _tmp => '$path.migrating';
  String get _old => '$path.premigrate';

  Future<String?> currentKey() => keys.read(keyName);
  Future<bool> isEncrypted() async => (await currentKey()) != null;

  // ---------------- восстановление после прерванной миграции ----------------

  /// Вызывать при каждом запуске, до открытия базы.
  Future<void> recover() async {
    final marker = await keys.read(markerName);
    final pending = await keys.read(pendingKeyName);
    _shred(_tmp); // недоделанная копия никому не нужна
    final hasOld = File(_old).existsSync();
    if (marker == null && !hasOld && pending == null) return;

    AppLog.d('Шифрование: восстановление после прерванной миграции (${marker ?? 'без метки'})');
    if (hasOld) {
      final hasMain = File(path).existsSync();
      if (!hasMain) {
        File(_old).renameSync(path); // подмена не завершилась — возвращаем исходную базу
      } else {
        final toEncrypted = marker == 'to_encrypted';
        final current = await keys.read(keyName);
        // пароль, которым должна открываться «новая» база
        final String? expected = marker == null ? current : (toEncrypted ? pending : null);
        final canVerify = marker == null || !toEncrypted || pending != null;
        if (canVerify && await _probe(path, expected)) {
          // новая база на месте и открывается — доводим фиксацию ключа до конца
          if (marker != null) {
            if (toEncrypted) {
              await keys.write(keyName, pending!);
            } else {
              await keys.delete(keyName);
            }
          }
          _shred(_old);
        } else {
          _shred(path); // новая база не открывается — возвращаем исходную
          File(_old).renameSync(path);
        }
      }
    }
    await _clearMarkers();
  }

  // ---------------- включение / выключение ----------------

  /// Приводит базу к нужному состоянию. Бросает [EncryptionException], если не удалось; при этом база остаётся прежней.
  /// База не должна быть открыта (в приложении — вызывать внутри `SqliteAppRepository.exclusive`).
  Future<void> setEncrypted(bool enable) async {
    await recover();
    final key = await keys.read(keyName);
    if (enable == (key != null)) return;

    if (!File(path).existsSync()) {
      // базы ещё нет: достаточно сменить режим — файл создастся сразу в нужном виде
      if (enable) {
        await keys.write(keyName, generateDbKey());
      } else {
        await keys.delete(keyName);
      }
      return;
    }

    final newKey = enable ? generateDbKey() : null;
    await keys.write(markerName, enable ? 'to_encrypted' : 'to_plain');
    if (newKey != null) await keys.write(pendingKeyName, newKey);
    await debugHook?.call(MigrationStep.afterMarker);

    try {
      _shred(_tmp);
      final counts = await _copy(path, key, _tmp, newKey);
      await debugHook?.call(MigrationStep.afterCopy);

      File(path).renameSync(_old);
      await debugHook?.call(MigrationStep.afterOldMoved);
      _deleteSidecars(path);
      File(_tmp).renameSync(path);
      _deleteSidecars(_tmp);
      await debugHook?.call(MigrationStep.afterSwapped);

      if (!await _verify(path, newKey, counts)) throw EncryptionException('Проверка новой базы не пройдена');

      if (enable) {
        await keys.write(keyName, newKey!);
      } else {
        await keys.delete(keyName);
      }
      await debugHook?.call(MigrationStep.afterKeyCommitted);
    } on MigrationInterrupted {
      rethrow; // обрыв: откатывать нечем и некому — разберётся recover() при следующем запуске
    } catch (e, st) {
      AppLog.e('Шифрование: миграция не удалась, исходная база восстановлена', e, st);
      await _rollback();
      throw e is EncryptionException ? e : EncryptionException('Не удалось ${enable ? 'включить' : 'отключить'} шифрование: $e');
    }

    _shred(_old);
    await _clearMarkers();
  }

  /// Полный сброс: удаляет базу и ключи (когда ключ утерян и базу не открыть). Данные не восстановить.
  Future<void> destroy() async {
    _shred(path);
    _shred(_tmp);
    _shred(_old);
    await keys.delete(keyName);
    await _clearMarkers();
  }

  // ---------------- внутреннее ----------------

  Future<void> _rollback() async {
    try {
      _shred(_tmp);
      if (File(_old).existsSync()) {
        _shred(path);
        File(_old).renameSync(path);
      }
    } catch (e, st) {
      AppLog.e('Шифрование: откат не завершён', e, st);
    }
    await _clearMarkers();
  }

  Future<void> _clearMarkers() async {
    await keys.delete(markerName);
    await keys.delete(pendingKeyName);
  }

  Future<bool> _probe(String file, String? password) async {
    if (!File(file).existsSync()) return false;
    Database? db;
    try {
      db = await open(file, password: password);
      await db.rawQuery('SELECT count(*) FROM sqlite_master');
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  Future<int> _count(Database db, String table) async {
    final r = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return (r.first['n'] as num).toInt();
  }

  /// Копирует все таблицы построчно (порциями) и сверяет число строк. Схема приёмника создаётся при открытии.
  Future<Map<String, int>> _copy(String srcPath, String? srcKey, String dstPath, String? dstKey) async {
    final src = await open(srcPath, password: srcKey);
    Database? dst;
    try {
      final rows = await src.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name <> 'android_metadata'");
      final names = rows.map((r) => r['name'] as String).toSet();
      final unknown = names.difference(tables.toSet());
      if (unknown.isNotEmpty) throw EncryptionException('В базе есть таблицы, неизвестные миграции: ${unknown.join(', ')}');

      dst = await open(dstPath, password: dstKey);
      final counts = <String, int>{};
      for (final t in tables) {
        if (!names.contains(t)) continue;
        var last = -1;
        var copied = 0;
        while (true) {
          final chunk = await src.rawQuery('SELECT rowid AS _rid, * FROM $t WHERE rowid > ? ORDER BY rowid LIMIT 1000', [last]);
          if (chunk.isEmpty) break;
          final batch = dst.batch();
          for (final r in chunk) {
            final m = Map<String, Object?>.of(r);
            last = m.remove('_rid') as int;
            batch.insert(t, m);
          }
          await batch.commit(noResult: true);
          copied += chunk.length;
        }
        final srcCount = await _count(src, t);
        final dstCount = await _count(dst, t);
        if (srcCount != copied || dstCount != copied) {
          throw EncryptionException('Число строк в таблице «$t» не сошлось: было $srcCount, скопировано $dstCount');
        }
        counts[t] = copied;
      }
      return counts;
    } finally {
      try {
        await src.close();
      } catch (_) {}
      try {
        await dst?.close();
      } catch (_) {}
    }
  }

  Future<bool> _verify(String file, String? password, Map<String, int> expected) async {
    Database? db;
    try {
      db = await open(file, password: password);
      for (final t in tables) {
        if (await _count(db, t) != (expected[t] ?? 0)) return false;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  void _deleteSidecars(String file) {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      try {
        final f = File('$file$suffix');
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  /// Затирает файл нулями и удаляет (вместе с WAL/SHM/journal). Это best-effort: на флеш-памяти с журналируемой
  /// файловой системой гарантии физического стирания нет — поэтому исходная база не должна жить дольше необходимого.
  void _shred(String file) {
    for (final f in [file, '$file-wal', '$file-shm', '$file-journal']) {
      try {
        final fl = File(f);
        if (!fl.existsSync()) continue;
        final len = fl.lengthSync();
        final raf = fl.openSync(mode: FileMode.write); // перезапись (файл усекается и заполняется нулями)
        try {
          final zeros = List<int>.filled(64 * 1024, 0);
          var left = len;
          while (left > 0) {
            final n = left < zeros.length ? left : zeros.length;
            raf.writeFromSync(zeros, 0, n);
            left -= n;
          }
          raf.flushSync();
        } finally {
          raf.closeSync();
        }
        fl.deleteSync();
      } catch (e) {
        AppLog.e('Не удалось затереть файл $f', e);
        try {
          File(f).deleteSync();
        } catch (_) {}
      }
    }
  }
}
