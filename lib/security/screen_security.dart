import 'package:flutter/services.dart';

import '../core/app_log.dart';

/// Защита от скриншотов и записи экрана (Android FLAG_SECURE). Нужен нативный код (docs/SECURITY_SETUP.md).
abstract class ScreenSecurity {
  Future<void> setSecure(bool secure);
}

class MethodChannelScreenSecurity implements ScreenSecurity {
  static const _channel = MethodChannel('life_os/screen_security');

  @override
  Future<void> setSecure(bool secure) async {
    try {
      await _channel.invokeMethod<void>('setSecure', secure);
    } on MissingPluginException {
      AppLog.d('Защита от скриншотов недоступна: нативная часть не подключена');
    } on PlatformException catch (e) {
      AppLog.e('Защита от скриншотов: ошибка ${e.code}', e.message);
    }
  }
}

class FakeScreenSecurity implements ScreenSecurity {
  bool secure = false;
  int calls = 0;

  @override
  Future<void> setSecure(bool value) async {
    calls++;
    secure = value;
  }
}
