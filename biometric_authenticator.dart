import 'dart:async';

/// Итог подтверждения личности.
enum AuthOutcome {
  success,
  cancelled, // пользователь закрыл запрос
  failed, // не распознан / ошибка
  notAvailable, // на устройстве нет биометрии и защиты экрана
  lockedOut, // слишком много попыток — система временно блокирует запросы
}

/// Граница между приложением и платформенной биометрией (`local_auth`).
abstract class BiometricAuthenticator {
  /// Можно ли защитить устройство: есть биометрия или PIN/пароль/графический ключ.
  Future<bool> isAvailable();

  /// Показывает системный запрос (биометрия, при необходимости — PIN устройства).
  Future<AuthOutcome> authenticate(String reason);
}

/// Управляемая реализация для тестов и превью.
class FakeAuthenticator implements BiometricAuthenticator {
  bool available;
  AuthOutcome nextOutcome;
  final List<String> reasons = [];

  /// Вызывается внутри [authenticate] — позволяет смоделировать события жизненного цикла во время запроса.
  Future<void> Function()? duringAuth;

  FakeAuthenticator({this.available = true, this.nextOutcome = AuthOutcome.success});

  int get calls => reasons.length;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<AuthOutcome> authenticate(String reason) async {
    reasons.add(reason);
    await duringAuth?.call();
    if (!available) return AuthOutcome.notAvailable;
    return nextOutcome;
  }
}
