import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/app_log.dart';
import 'biometric_authenticator.dart';
import 'screen_security.dart';
import 'security_settings.dart';

/// Блокировка приложения: запрос биометрии/PIN при запуске и возврате из фона, «шторка» над содержимым
/// в списке приложений. Чистая логика (без UI): жизненный цикл подаётся методом [onLifecycle].
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock({
    required this.authenticator,
    required this.settings,
    this.screen,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final BiometricAuthenticator authenticator;
  final SecuritySettings settings;
  final ScreenSecurity? screen;
  final DateTime Function() _clock;

  bool _locked = false;
  bool _shielded = false;
  bool _authenticating = false;
  DateTime? _backgroundAt;
  String? _message;

  bool get enabled => settings.lockEnabled;
  int get timeoutSec => settings.lockTimeoutSec;
  bool get screenProtection => settings.screenProtection;

  /// Приложение заблокировано: UI показывает экран разблокировки.
  bool get locked => enabled && _locked;

  /// Содержимое нужно скрыть (приложение уходит в фон), даже если блокировка выключена.
  bool get shielded => screenProtection && _shielded && !locked;

  bool get authenticating => _authenticating;
  String? get message => _message;

  /// Холодный старт: если блокировка включена — приложение сразу заблокировано.
  void start() {
    _locked = settings.lockEnabled;
    unawaited(screen?.setSecure(settings.screenProtection));
  }

  void attach() => WidgetsBinding.instance.addObserver(this);
  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onLifecycle(state);

  void onLifecycle(AppLifecycleState state) {
    // Системный запрос биометрии сам переводит приложение в inactive/paused — на это не реагируем,
    // иначе разблокировка зацикливается.
    if (_authenticating) return;
    switch (state) {
      case AppLifecycleState.inactive:
        _shielded = true; // шторка: миниатюра в списке приложений снимается именно сейчас
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _shielded = true;
        _backgroundAt ??= _clock();
        if (enabled && timeoutSec == 0) _locked = true;
      case AppLifecycleState.resumed:
        _shielded = false;
        final at = _backgroundAt;
        _backgroundAt = null;
        if (enabled && !_locked && at != null && _clock().difference(at).inSeconds >= timeoutSec) _locked = true;
      case AppLifecycleState.detached:
        break;
    }
    notifyListeners();
  }

  /// Блокирует немедленно (кнопка «Заблокировать»).
  void lockNow() {
    if (!enabled) return;
    _locked = true;
    notifyListeners();
  }

  Future<AuthOutcome> _authenticate(String reason) async {
    _authenticating = true;
    notifyListeners();
    try {
      return await authenticator.authenticate(reason);
    } catch (e, st) {
      AppLog.e('Запрос подтверждения личности завершился ошибкой', e, st);
      return AuthOutcome.failed;
    } finally {
      _authenticating = false;
    }
  }

  /// Разблокировка. Если на устройстве больше нет защиты экрана, блокировку нечем обеспечить:
  /// приложение открывается, а блокировка отключается (иначе пользователь потерял бы доступ к своим данным).
  Future<AuthOutcome> unlock() async {
    if (!locked) return AuthOutcome.success;
    if (_authenticating) return AuthOutcome.cancelled;
    final out = await _authenticate('Разблокируйте Life OS');
    switch (out) {
      case AuthOutcome.success:
        _locked = false;
        _message = null;
        _backgroundAt = null;
      case AuthOutcome.notAvailable:
        _locked = false;
        settings.lockEnabled = false;
        await settings.save();
        _message = 'На устройстве не настроена защита экрана — блокировка приложения отключена.';
      case AuthOutcome.lockedOut:
        _message = 'Слишком много попыток. Подождите или разблокируйте телефон другим способом.';
      case AuthOutcome.failed:
        _message = 'Не удалось подтвердить личность. Попробуйте ещё раз.';
      case AuthOutcome.cancelled:
        _message = null;
    }
    notifyListeners();
    return out;
  }

  /// Включает/выключает блокировку. В обе стороны требуется подтверждение личности: так включённую блокировку
  /// нельзя снять, просто взяв открытое приложение.
  Future<AuthOutcome> setEnabled(bool value) async {
    if (value == enabled) return AuthOutcome.success;
    if (!await authenticator.isAvailable()) {
      _message = 'Сначала настройте на устройстве биометрию или PIN/пароль экрана.';
      notifyListeners();
      return AuthOutcome.notAvailable;
    }
    final out = await _authenticate(value ? 'Подтвердите, чтобы включить блокировку' : 'Подтвердите, чтобы отключить блокировку');
    if (out != AuthOutcome.success) {
      notifyListeners();
      return out;
    }
    settings.lockEnabled = value;
    await settings.save();
    _locked = false;
    _backgroundAt = null;
    _message = null;
    notifyListeners();
    return AuthOutcome.success;
  }

  Future<void> setTimeout(int seconds) async {
    if (!SecuritySettings.timeoutOptions.contains(seconds)) return;
    settings.lockTimeoutSec = seconds;
    await settings.save();
    notifyListeners();
  }

  Future<void> setScreenProtection(bool value) async {
    settings.screenProtection = value;
    await settings.save();
    await screen?.setSecure(value);
    notifyListeners();
  }

  void clearMessage() {
    if (_message == null) return;
    _message = null;
    notifyListeners();
  }
}
