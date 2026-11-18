import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_log.dart';
import '../core/backup_schedule.dart';
import '../data/backup_storage.dart';
import '../state/app_controller.dart';
import 'backup_cipher.dart';
import 'key_store.dart';

/// Итог попытки сделать копию.
enum BackupOutcome { done, notConfigured, noAccess, failed }

/// Автоматическая резервная копия: зашифрованная паролем копия всех данных — в папку, которую человек выбрал
/// (на телефоне или в облаке через системный проводник). Делается при запуске и возвращении в приложение,
/// если пора; хранятся последние [backupKeepCount] копий.
///
/// Настройки — устройства, а не данных (SharedPreferences): адрес папки на другом телефоне ничего не значит.
/// Пароль копий — в защищённом хранилище (Android Keystore); восстановить копию без него нельзя.
/// Ничего не отправляется туда, куда человек сам не указал.
class AutoBackup extends ChangeNotifier {
  static const passKey = 'backup_passphrase';
  static const _kFolder = 'bk_folder';
  static const _kFolderName = 'bk_folder_name';
  static const _kInterval = 'bk_interval_days';
  static const _kLast = 'bk_last_ms';
  static const _kLastFile = 'bk_last_file';
  static const _kError = 'bk_error';

  AutoBackup({
    required this.controller,
    required this.storage,
    required this.keys,
    this.cipher = const BackupCipher(useIsolate: true),
    SharedPreferences? prefs,
    DateTime Function()? clock,
  })  : _prefs = prefs,
        _clock = clock ?? DateTime.now;

  /// Заглушка: автокопия недоступна (тесты интерфейса, платформы без хранилища).
  factory AutoBackup.disabled(AppController controller) =>
      AutoBackup(controller: controller, storage: const UnsupportedBackupStorage(), keys: MemoryKeyStore());

  final AppController controller;
  final BackupStorage storage;
  final KeyStore keys;
  final BackupCipher cipher;
  final DateTime Function() _clock;
  SharedPreferences? _prefs;

  String? _folder;
  String? _folderName;
  int _intervalDays = 7;
  DateTime? _lastAt;
  String? _lastFile;
  String? _error;
  bool _hasPassword = false;
  bool _running = false;

  bool get supported => storage is! UnsupportedBackupStorage;
  String? get folder => _folder;
  String? get folderName => _folderName;
  int get intervalDays => _intervalDays;
  DateTime? get lastAt => _lastAt;
  String? get lastFile => _lastFile;

  /// Последняя ошибка автокопии (сбрасывается удачной копией); null — ошибок нет.
  String? get error => _error;
  bool get hasPassword => _hasPassword;
  bool get configured => _folder != null && _hasPassword;
  bool get running => _running;

  /// Напоминание на «Сегодня»: копий нет давно (или вовсе), либо автокопия перестала получаться.
  bool needsAttention(DateTime now) {
    if (!supported) return false;
    if (_error != null) return true;
    final d = daysSinceBackup(_lastAt, now);
    return d == null || d >= backupReminderDays;
  }

  Future<SharedPreferences> get _p async => _prefs ??= await SharedPreferences.getInstance();

  Future<void> init() async {
    try {
      final p = await _p;
      _folder = p.getString(_kFolder);
      _folderName = p.getString(_kFolderName);
      final i = p.getInt(_kInterval) ?? 7;
      _intervalDays = backupIntervalOptions.contains(i) ? i : 7;
      final last = p.getInt(_kLast);
      _lastAt = last == null ? null : DateTime.fromMillisecondsSinceEpoch(last);
      _lastFile = p.getString(_kLastFile);
      _error = p.getString(_kError);
      _hasPassword = (await keys.read(passKey))?.isNotEmpty ?? false;
    } catch (e, st) {
      AppLog.e('Автокопия: не удалось прочитать настройки', e, st);
    }
    notifyListeners();
  }

  /// Выбор папки. false — выбор отменён или невозможен.
  Future<bool> chooseFolder() async {
    try {
      final f = await storage.pickFolder();
      if (f == null) return false;
      _folder = f;
      _folderName = await storage.folderName(f);
      _error = null;
      final p = await _p;
      await p.setString(_kFolder, f);
      if (_folderName != null) await p.setString(_kFolderName, _folderName!);
      await p.remove(_kError);
      notifyListeners();
      return true;
    } catch (e, st) {
      AppLog.e('Автокопия: папка не выбрана', e, st);
      return false;
    }
  }

  /// Пароль копий. Хранится в защищённом хранилище устройства; нужен, чтобы восстановить копию на другом телефоне.
  Future<bool> setPassword(String passphrase) async {
    if (passphrase.length < BackupCipher.minPassphraseLength) return false;
    await keys.write(passKey, passphrase);
    _hasPassword = true;
    notifyListeners();
    return true;
  }

  Future<void> setInterval(int days) async {
    if (!backupIntervalOptions.contains(days)) return;
    _intervalDays = days;
    await (await _p).setInt(_kInterval, days);
    notifyListeners();
  }

  /// Отключить автокопию: забыть папку и пароль. Уже сделанные копии остаются в папке.
  Future<void> disable() async {
    final p = await _p;
    for (final k in [_kFolder, _kFolderName, _kError]) {
      await p.remove(k);
    }
    await keys.delete(passKey);
    _folder = _folderName = _error = null;
    _hasPassword = false;
    notifyListeners();
  }

  /// Копия, если пора (вызывается при запуске и возвращении в приложение). Ошибки не всплывают — запоминаются.
  Future<BackupOutcome?> maybeRun() async {
    if (!supported || !configured || _running || !controller.loaded) return null;
    if (!backupDue(_lastAt, _clock(), _intervalDays)) return null;
    return runNow();
  }

  /// Сделать копию сейчас. Старые копии удаляются только после того, как новая записана.
  Future<BackupOutcome> runNow() async {
    if (!configured) return BackupOutcome.notConfigured;
    if (_running) return BackupOutcome.failed;
    _running = true;
    notifyListeners();
    final p = await _p;
    try {
      final folder = _folder!;
      if (!await storage.hasAccess(folder)) {
        await _fail(p, 'нет доступа к папке «${_folderName ?? 'копии'}» — выберите её заново');
        return BackupOutcome.noAccess;
      }
      final pass = await keys.read(passKey);
      if (pass == null || pass.isEmpty) {
        _hasPassword = false;
        await _fail(p, 'пароль копий не найден — задайте его заново');
        return BackupOutcome.notConfigured;
      }
      final now = _clock();
      final encrypted = await cipher.encrypt(controller.exportBackup(), pass);
      var name = backupFileName(now);
      final existing = await storage.list(folder);
      if (existing.any((f) => f.name == name)) name = name.replaceFirst(backupFileExtension, '-2$backupFileExtension');
      await storage.write(folder, name, Uint8List.fromList(utf8.encode(encrypted)));
      _lastAt = now;
      _lastFile = name;
      _error = null;
      await p.setInt(_kLast, now.millisecondsSinceEpoch);
      await p.setString(_kLastFile, name);
      await p.remove(_kError);
      // очистка — после записи и по возможности: её сбой копию не отменяет
      try {
        final all = await storage.list(folder);
        final drop = backupsToDelete(all.map((f) => f.name));
        for (final f in all) {
          if (drop.contains(f.name)) await storage.delete(folder, f.id);
        }
      } catch (e, st) {
        AppLog.e('Автокопия: старые копии не удалены', e, st);
      }
      return BackupOutcome.done;
    } catch (e, st) {
      AppLog.e('Автокопия не удалась', e, st);
      await _fail(p, 'копия не записана: $e');
      return BackupOutcome.failed;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> _fail(SharedPreferences p, String message) async {
    _error = message;
    await p.setString(_kError, message);
  }
}
