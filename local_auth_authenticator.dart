import 'package:flutter/services.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

import '../core/app_log.dart';
import 'biometric_authenticator.dart';

/// Единственный файл, который знает о плагине `local_auth` (pubspec: `local_auth: ^2.3.0`).
class LocalAuthAuthenticator implements BiometricAuthenticator {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e, st) {
      AppLog.e('local_auth: не удалось определить поддержку', e, st);
      return false;
    }
  }

  @override
  Future<AuthOutcome> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        // biometricOnly: false — допускается PIN/пароль устройства: иначе без биометрии вход невозможен
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      return ok ? AuthOutcome.success : AuthOutcome.cancelled;
    } on PlatformException catch (e) {
      switch (e.code) {
        case auth_error.notAvailable:
        case auth_error.notEnrolled:
        case auth_error.passcodeNotSet:
          return AuthOutcome.notAvailable;
        case auth_error.lockedOut:
        case auth_error.permanentlyLockedOut:
          return AuthOutcome.lockedOut;
        default:
          AppLog.e('local_auth: ошибка ${e.code}', e.message);
          return AuthOutcome.failed;
      }
    } catch (e, st) {
      AppLog.e('local_auth: непредвиденная ошибка', e, st);
      return AuthOutcome.failed;
    }
  }
}
