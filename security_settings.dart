import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_log.dart';

/// Настройки защиты. Хранятся в SharedPreferences, а не в базе данных: они относятся к устройству
/// (не должны переезжать вместе с резервной копией) и должны работать, даже если база недоступна.
class SecuritySettings {
  static const _kLock = 'sec_lock_enabled';
  static const _kTimeout = 'sec_lock_timeout_sec';
  static const _kScreen = 'sec_screen_protection';

  /// Допустимые задержки блокировки после ухода в фон, секунды (0 — сразу).
  static const timeoutOptions = [0, 30, 60, 300];

  bool lockEnabled;
  int lockTimeoutSec;
  bool screenProtection;

  SecuritySettings({this.lockEnabled = false, this.lockTimeoutSec = 30, this.screenProtection = false, SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;

  static Future<SecuritySettings> load([SharedPreferences? prefs]) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final t = p.getInt(_kTimeout) ?? 30;
      return SecuritySettings(
        lockEnabled: p.getBool(_kLock) ?? false,
        lockTimeoutSec: timeoutOptions.contains(t) ? t : 30,
        screenProtection: p.getBool(_kScreen) ?? false,
        prefs: p,
      );
    } catch (e, st) {
      AppLog.e('Не удалось прочитать настройки защиты', e, st);
      return SecuritySettings(prefs: prefs);
    }
  }

  Future<void> save() async {
    try {
      final p = _prefs ??= await SharedPreferences.getInstance();
      await p.setBool(_kLock, lockEnabled);
      await p.setInt(_kTimeout, lockTimeoutSec);
      await p.setBool(_kScreen, screenProtection);
    } catch (e, st) {
      AppLog.e('Не удалось сохранить настройки защиты', e, st);
    }
  }
}
