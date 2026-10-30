import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/security/db_encryption.dart';
import 'package:life_os/security/key_store.dart';
import 'package:life_os/security/security_service.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Моделируем SQLCipher так: «пароль» хранится в заголовке файла (application_id). Открыть файл с неверным
/// паролем нельзя — как у настоящего шифрования; переименование файла переносит и его «пароль».
/// Сами криптографические свойства SQLCipher здесь не проверяются — проверяется логика миграции:
/// порядок шагов, проверки, откат и восстановление после сбоя.
int _hash(String? p) => p == null ? 0 : (p.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) & 0x7fffffff) | 1);

Future<Database> fakeOpen(String path, {String? password}) async {
  final existed = File(path).existsSync();
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(version: kDbVersion, onCreate: SqliteAppRepository.onCreateSchema),
  );
  final want = _hash(password);
  final have = ((await db.rawQuery('PRAGMA application_id')).first.values.first as num).toInt();
  if (!existed) {
    if (want != 0) await db.execute('PRAGMA application_id = $want');
  } else if (have != want) {
    await db.close();
    throw StateError('file is not a database');
  }
  return db;
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory dir;
  late String path;
  late MemoryKeyStore keys;

  DbEncryptionManager manager({DbOpener? open, FutureOr<void> Function(MigrationStep)? hook}) => DbEncryptionManager(
        open: open ?? fakeOpen,
        keys: keys,
        path: path,
        tables: SqliteAppRepository.tables,
        debugHook: hook,
      );

  DbEncryptionManager crashAt(MigrationStep step) => manager(hook: (s) {
        if (s == step) throw MigrationInterrupted();
      });

  Future<void> seed({int sets = 2500, int txs = 1200, bool extraTable = false}) async {
    final db = await fakeOpen(path);
    final b = db.batch();
    b.insert('kv', {'k': 'netWorth', 'v': '123456'});
    b.insert('kv', {'k': 'userName', 'v': '"Мария"'});
    b.insert('docs', {'coll': 'goals', 'id': 'g1', 'pos': 0, 'body': '{"id":"g1","title":"Цель"}'});
    for (int i = 0; i < sets; i++) {
      b.insert('workout_sets', {'id': 's$i', 'muscle_id': 'chest', 'ts': 1700000000000 + i, 'weight': 50.5 + i, 'reps': 5});
    }
    for (int i = 0; i < txs; i++) {
      b.insert('money_tx', {'id': 't$i', 'ts': 1700000000000 + i, 'is_income': i % 2, 'amount': 100 + i, 'category_id': 'food', 'note': 'заметка $i', 'affects_net_worth': 1, 'recurring_id': null});
    }
    await b.commit(noResult: true);
    if (extraTable) await db.execute('CREATE TABLE extra (x INTEGER)');
    await db.close();
  }

  /// Полное содержимое всех таблиц (для сравнения «до» и «после»).
  Future<Map<String, List<Map<String, Object?>>>> content(String? password) async {
    final db = await fakeOpen(path, password: password);
    try {
      return {
        for (final t in SqliteAppRepository.tables) t: (await db.rawQuery('SELECT * FROM $t ORDER BY rowid')).map((r) => Map<String, Object?>.of(r)).toList(),
      };
    } finally {
      await db.close();
    }
  }

  Future<bool> opens(String? password) async {
    try {
      final db = await fakeOpen(path, password: password);
      await db.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool leftovers() => File('$path.migrating').existsSync() || File('$path.premigrate').existsSync();

  Future<bool> markersClear() async =>
      await keys.read(DbEncryptionManager.markerName) == null && await keys.read(DbEncryptionManager.pendingKeyName) == null;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('life_os_enc_test');
    path = '${dir.path}/life_os.db';
    keys = MemoryKeyStore();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('включение и выключение', () {
    test('включение: данные целы, без ключа база не открывается, следов миграции нет', () async {
      await seed();
      final before = await content(null);

      await manager().setEncrypted(true);

      final key = await keys.read(DbEncryptionManager.keyName);
      expect(key, isNotNull);
      expect(key!.length, 64);
      expect(await opens(null), isFalse); // без ключа не открыть
      expect(await opens(key), isTrue);
      expect(await content(key), before); // каждая строка на месте (больше одной порции копирования)
      expect(leftovers(), isFalse);
      expect(await markersClear(), isTrue);
    });

    test('выключение возвращает обычную базу, ключ удаляется, данные целы', () async {
      await seed();
      final before = await content(null);
      await manager().setEncrypted(true);
      await manager().setEncrypted(false);

      expect(await keys.read(DbEncryptionManager.keyName), isNull);
      expect(await opens(null), isTrue);
      expect(await content(null), before);
      expect(leftovers(), isFalse);
      expect(await markersClear(), isTrue);
    });

    test('при каждом включении создаётся новый ключ', () async {
      await seed(sets: 5, txs: 5);
      await manager().setEncrypted(true);
      final k1 = await keys.read(DbEncryptionManager.keyName);
      await manager().setEncrypted(false);
      await manager().setEncrypted(true);
      final k2 = await keys.read(DbEncryptionManager.keyName);
      expect(k1, isNot(k2));
    });

    test('повторное включение ничего не меняет', () async {
      await seed(sets: 5, txs: 5);
      await manager().setEncrypted(true);
      final k1 = await keys.read(DbEncryptionManager.keyName);
      await manager().setEncrypted(true);
      expect(await keys.read(DbEncryptionManager.keyName), k1);
    });

    test('базы ещё нет: меняется только режим (файл создастся сразу в нужном виде)', () async {
      await manager().setEncrypted(true);
      expect(await keys.read(DbEncryptionManager.keyName), isNotNull);
      expect(File(path).existsSync(), isFalse);
      await manager().setEncrypted(false);
      expect(await keys.read(DbEncryptionManager.keyName), isNull);
    });

    test('пустая база шифруется без ошибок', () async {
      await seed(sets: 0, txs: 0);
      await manager().setEncrypted(true);
      final key = await keys.read(DbEncryptionManager.keyName);
      expect(await opens(key), isTrue);
    });
  });

  group('отказ без потери данных', () {
    test('не удалось создать зашифрованную копию: исходная база цела, ключа нет, следов нет', () async {
      await seed();
      final before = await content(null);
      final failing = manager(open: (p, {String? password}) {
        if (p.endsWith('.migrating')) throw StateError('диск переполнен');
        return fakeOpen(p, password: password);
      });

      await expectLater(failing.setEncrypted(true), throwsA(isA<EncryptionException>()));

      expect(await keys.read(DbEncryptionManager.keyName), isNull);
      expect(await opens(null), isTrue);
      expect(await content(null), before);
      expect(leftovers(), isFalse);
      expect(await markersClear(), isTrue);
    });

    test('неизвестная таблица в базе: миграция отклоняется (данные не теряются молча)', () async {
      await seed(sets: 5, txs: 5, extraTable: true);
      await expectLater(manager().setEncrypted(true), throwsA(predicate((e) => e is EncryptionException && e.message.contains('extra'))));
      expect(await keys.read(DbEncryptionManager.keyName), isNull);
      expect(await opens(null), isTrue);
      expect(leftovers(), isFalse);
    });

    test('итоговая проверка не пройдена (потеряна строка): исходная база возвращается', () async {
      await seed();
      final before = await content(null);
      final sabotage = manager(hook: (step) async {
        if (step == MigrationStep.afterSwapped) {
          final pending = await keys.read(DbEncryptionManager.pendingKeyName);
          final db = await fakeOpen(path, password: pending);
          await db.rawDelete('DELETE FROM money_tx WHERE id = (SELECT id FROM money_tx LIMIT 1)');
          await db.close();
        }
      });

      await expectLater(sabotage.setEncrypted(true), throwsA(isA<EncryptionException>()));

      expect(await keys.read(DbEncryptionManager.keyName), isNull);
      expect(await opens(null), isTrue);
      expect(await content(null), before);
      expect(leftovers(), isFalse);
      expect(await markersClear(), isTrue);
    });

    test('сбой при выключении шифрования: зашифрованная база и ключ остаются', () async {
      await seed();
      await manager().setEncrypted(true);
      final key = await keys.read(DbEncryptionManager.keyName);
      final before = await content(key);

      final failing = manager(open: (p, {String? password}) {
        if (p.endsWith('.migrating')) throw StateError('нет места');
        return fakeOpen(p, password: password);
      });
      await expectLater(failing.setEncrypted(false), throwsA(isA<EncryptionException>()));

      expect(await keys.read(DbEncryptionManager.keyName), key);
      expect(await content(key), before);
      expect(leftovers(), isFalse);
    });
  });

  group('восстановление после внезапного сбоя (убитый процесс, питание)', () {
    Future<void> crash(DbEncryptionManager m, bool enable) async {
      await expectLater(m.setEncrypted(enable), throwsA(isA<MigrationInterrupted>()));
    }

    test('сбой сразу после метки: после восстановления всё как было', () async {
      await seed();
      final before = await content(null);
      await crash(crashAt(MigrationStep.afterMarker), true);
      await manager().recover();
      expect(await keys.read(DbEncryptionManager.keyName), isNull);
      expect(await content(null), before);
      expect(await markersClear(), isTrue);
    });

    test('сбой после создания копии: временная копия удаляется, исходная цела', () async {
      await seed();
      final before = await content(null);
      await crash(crashAt(MigrationStep.afterCopy), true);
      expect(File('$path.migrating').existsSync(), isTrue);
      await manager().recover();
      expect(leftovers(), isFalse);
      expect(await keys.read(DbEncryptionManager.keyName), isNull);
      expect(await content(null), before);
    });

    test('сбой после переименования исходной базы: она возвращается на место', () async {
      await seed();
      final before = await content(null);
      await crash(crashAt(MigrationStep.afterOldMoved), true);
      expect(File(path).existsSync(), isFalse);
      await manager().recover();
      expect(await keys.read(DbEncryptionManager.keyName), isNull);
      expect(await content(null), before);
      expect(leftovers(), isFalse);
    });

    test('сбой после подмены файла, до фиксации ключа: миграция доводится до конца', () async {
      await seed();
      final before = await content(null);
      await crash(crashAt(MigrationStep.afterSwapped), true);
      expect(await keys.read(DbEncryptionManager.keyName), isNull); // ключ ещё не зафиксирован
      await manager().recover();
      final key = await keys.read(DbEncryptionManager.keyName);
      expect(key, isNotNull); // ключ зафиксирован из «ожидающего»
      expect(await opens(null), isFalse);
      expect(await content(key), before);
      expect(leftovers(), isFalse);
      expect(await markersClear(), isTrue);
    });

    test('сбой сразу после фиксации ключа: старая база затирается, итог — зашифрованная база', () async {
      await seed();
      final before = await content(null);
      await crash(crashAt(MigrationStep.afterKeyCommitted), true);
      expect(File('$path.premigrate').existsSync(), isTrue);
      await manager().recover();
      final key = await keys.read(DbEncryptionManager.keyName);
      expect(await content(key), before);
      expect(leftovers(), isFalse);
    });

    test('выключение: сбой после подмены — миграция доводится, ключ удаляется', () async {
      await seed();
      final before = await content(null);
      await manager().setEncrypted(true);
      await crash(crashAt(MigrationStep.afterSwapped), false);
      await manager().recover();
      expect(await keys.read(DbEncryptionManager.keyName), isNull);
      expect(await content(null), before);
      expect(leftovers(), isFalse);
    });

    test('выключение: сбой после переименования — зашифрованная база возвращается вместе с ключом', () async {
      await seed();
      await manager().setEncrypted(true);
      final key = await keys.read(DbEncryptionManager.keyName);
      final before = await content(key);
      await crash(crashAt(MigrationStep.afterOldMoved), false);
      await manager().recover();
      expect(await keys.read(DbEncryptionManager.keyName), key);
      expect(await content(key), before);
      expect(leftovers(), isFalse);
    });

    test('recover на чистом состоянии ничего не меняет', () async {
      await seed(sets: 5, txs: 5);
      await manager().setEncrypted(true);
      final key = await keys.read(DbEncryptionManager.keyName);
      await manager().recover();
      await manager().recover();
      expect(await keys.read(DbEncryptionManager.keyName), key);
      expect(await opens(key), isTrue);
    });

    test('остатки временной копии без метки просто удаляются', () async {
      await seed(sets: 5, txs: 5);
      File('$path.migrating').writeAsStringSync('мусор');
      await manager().recover();
      expect(File('$path.migrating').existsSync(), isFalse);
      expect(await opens(null), isTrue);
    });
  });

  test('destroy удаляет базу и ключи', () async {
    await seed(sets: 5, txs: 5);
    await manager().setEncrypted(true);
    await manager().destroy();
    expect(File(path).existsSync(), isFalse);
    expect(await keys.read(DbEncryptionManager.keyName), isNull);
    expect(leftovers(), isFalse);
  });

  test('generateDbKey: 64 hex-символа, ключи разные', () {
    final a = generateDbKey();
    final b = generateDbKey();
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(a), isTrue);
    expect(a, isNot(b));
  });

  group('вместе с репозиторием и контроллером', () {
    // у записей разные метки времени — порядок при сравнении однозначен
    var now = DateTime(2026, 10, 24, 12);
    void tick() => now = now.add(const Duration(minutes: 1));
    DateTime clock() => now;

    test('включение шифрования на лету: приложение продолжает сохранять, данные читаются при следующем запуске', () async {
      final repo = SqliteAppRepository(
        opener: () async => fakeOpen(path, password: await keys.read(DbEncryptionManager.keyName)),
      );
      final c = AppController(repo, clock: clock, saveDelay: const Duration(days: 1));
      await c.load();
      tick();
      c.logWorkout('chest', 100, 5);
      tick();
      c.addTransaction(categoryId: 'food', amount: 700);
      await c.flush();

      final m = manager();
      final service = SecurityService(
        lock: SecurityService.disabled().lock,
        encryption: m,
        flushStorage: c.flush,
        exclusive: repo.exclusive,
      );
      await service.init();
      expect(service.encrypted, isFalse);

      tick();
      c.logWorkout('abs', 20, 10); // изменение накоплено, но ещё не записано
      final res = await service.setEncryption(true);
      expect(res.ok, isTrue, reason: res.message);
      expect(service.encrypted, isTrue);

      tick();
      c.addTransaction(categoryId: 'salary', amount: 90000); // сохраняется уже в зашифрованную базу
      await c.flush();

      final repo2 = SqliteAppRepository(opener: () async => fakeOpen(path, password: await keys.read(DbEncryptionManager.keyName)));
      final c2 = AppController(repo2, clock: clock, saveDelay: const Duration(days: 1));
      await c2.load();
      expect(c2.exportBackup(), c.exportBackup());
      expect(c2.sets.length, 2);
      expect(c2.transactions.length, 2);
      expect(await opens(null), isFalse);
    });

    test('выключение шифрования на лету', () async {
      final repo = SqliteAppRepository(opener: () async => fakeOpen(path, password: await keys.read(DbEncryptionManager.keyName)));
      final c = AppController(repo, clock: clock, saveDelay: const Duration(days: 1));
      await c.load();
      tick();
      c.logWorkout('chest', 100, 5);
      await c.flush();
      final service = SecurityService(lock: SecurityService.disabled().lock, encryption: manager(), flushStorage: c.flush, exclusive: repo.exclusive);
      await service.setEncryption(true);
      tick();
      c.logWorkout('abs', 20, 10);
      await service.setEncryption(false);
      expect(service.encrypted, isFalse);
      expect(await opens(null), isTrue);

      final repo2 = SqliteAppRepository(opener: () async => fakeOpen(path));
      final c2 = AppController(repo2, saveDelay: const Duration(days: 1));
      await c2.load();
      expect(c2.sets.length, 2);
    });
  });
}
