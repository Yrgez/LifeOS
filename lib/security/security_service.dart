import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/app_log.dart';
import 'app_lock.dart';
import 'backup_cipher.dart';
import 'biometric_authenticator.dart';
import 'db_encryption.dart';
import 'security_settings.dart';

/// Запускает действие при закрытой базе и остановленной очереди сохранений (`SqliteAppRepository.exclusive`).
typedef ExclusiveRunner = Future<T> Function<T>(Future<T> Function() action);

class EncryptionResult {
  final bool ok;
  final String? message;
  const EncryptionResult.success() : ok = true, message = null;
  const EncryptionResult.failure(String this.message) : ok = false;
}

/// Всё, что связано с безопасностью, в одном объекте для интерфейса: блокировка, шифрование базы, шифрование копий.
class SecurityService extends ChangeNotifier {
  SecurityService({
    required this.lock,
    this.encryption,
    this.flushStorage,
    this.exclusive,
    this.onStorageReset,
    this.backupCipher = const BackupCipher(),
  });

  /// Заглушка для тестов интерфейса и превью: блокировка выключена, шифрование базы недоступно.
  factory SecurityService.disabled() {
    final lock = AppLock(authenticator: FakeAuthenticator(available: false), settings: SecuritySettings())..start();
    return SecurityService(lock: lock, backupCipher: const BackupCipher(iterations: 1000));
  }

  final AppLock lock;

  /// null — шифрование базы не поддерживается (нет SQLCipher/хранилища ключей).
  final DbEncryptionManager? encryption;
  final Future<void> Function()? flushStorage;
  final ExclusiveRunner? exclusive;

  /// Вызывается после сброса хранилища: приложению нужно заново прочитать (создать) данные.
  final Future<void> Function()? onStorageReset;

  final BackupCipher backupCipher;

  bool _encrypted = false;
  bool _busy = false;

  bool get encryptionSupported => encryption != null && exclusive != null;
  bool get encrypted => _encrypted;
  bool get busy => _busy;

  Future<void> init() async {
    try {
      _encrypted = await encryption?.isEncrypted() ?? false;
    } catch (e, st) {
      AppLog.e('Не удалось определить состояние шифрования', e, st);
    }
    notifyListeners();
  }

  /// Включает или выключает шифрование базы. Накопленные изменения сначала записываются, затем база закрывается,
  /// копируется в новую форму и открывается заново; сохранения, вызванные за это время, ждут своей очереди.
  Future<EncryptionResult> setEncryption(bool enable) async {
    if (!encryptionSupported) return const EncryptionResult.failure('Шифрование базы недоступно на этом устройстве');
    if (_busy) return const EncryptionResult.failure('Операция уже выполняется');
    if (enable == _encrypted) return const EncryptionResult.success();
    _busy = true;
    notifyListeners();
    try {
      await flushStorage?.call();
      await exclusive!<void>(() => encryption!.setEncrypted(enable));
      _encrypted = enable;
      return const EncryptionResult.success();
    } on EncryptionException catch (e) {
      return EncryptionResult.failure('${e.message}\nДанные не изменены.');
    } catch (e, st) {
      AppLog.e('Смена шифрования завершилась ошибкой', e, st);
      return const EncryptionResult.failure('Не удалось изменить шифрование. Данные не изменены.');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Удаляет базу и ключ (например, если ключ утерян и данные не открыть) и просит приложение начать заново.
  Future<EncryptionResult> resetStorage() async {
    final enc = encryption;
    final run = exclusive;
    if (enc == null || run == null) return const EncryptionResult.failure('Сброс хранилища недоступен');
    if (_busy) return const EncryptionResult.failure('Операция уже выполняется');
    _busy = true;
    notifyListeners();
    try {
      await run<void>(() => enc.destroy());
      _encrypted = false;
      await onStorageReset?.call();
      return const EncryptionResult.success();
    } catch (e, st) {
      AppLog.e('Сброс хранилища не удался', e, st);
      return const EncryptionResult.failure('Не удалось сбросить хранилище');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
