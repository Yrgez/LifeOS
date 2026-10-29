import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' show getDatabasesPath;

import 'app.dart';
import 'core/app_log.dart';
import 'data/app_data.dart';
import 'data/app_repository.dart';
import 'data/health_connect_source.dart';
import 'data/sqlcipher_opener.dart';
import 'data/sqlite_app_repository.dart';
import 'security/app_lock.dart';
import 'security/backup_cipher.dart';
import 'security/db_encryption.dart';
import 'security/local_auth_authenticator.dart';
import 'security/screen_security.dart';
import 'security/secure_key_store.dart';
import 'security/security_service.dart';
import 'security/security_settings.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Глобальный перехват ошибок: больше никаких тихих падений.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLog.e('FlutterError', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLog.e('Необработанная ошибка', error, stack);
    return true;
  };

  // ---- хранилище: SQLite (при включённом шифровании — SQLCipher с ключом из Keystore) ----
  final dbPath = p.join(await getDatabasesPath(), 'life_os.db');
  final keys = SecureKeyStore();
  final encryption = DbEncryptionManager(open: openSqlCipher, keys: keys, path: dbPath, tables: SqliteAppRepository.tables);
  try {
    await encryption.recover(); // доводит или откатывает прерванную смену шифрования — до открытия базы
  } catch (e, st) {
    AppLog.e('Не удалось восстановить состояние шифрования', e, st);
  }

  final repository = SqliteAppRepository(
    // ключ читается при каждом открытии: после смены шифрования база откроется уже с актуальным ключом
    opener: () async => openSqlCipher(dbPath, password: await keys.read(DbEncryptionManager.keyName)),
    legacy: PrefsAppRepository(), // данные прежних версий (SharedPreferences) переезжают автоматически
  );

  final controller = AppController(
    repository,
    health: HealthConnectSource(),
    // новая установка начинается с чистого листа; примеры данных — по выбору на экране знакомства
    initialData: (now) => AppData.blank(now: now),
  );
  await controller.load(); // при сбое (нет ключа, повреждение) приложение стартует в режиме «только чтение»

  // ---- безопасность: блокировка, шифрование базы и копий ----
  final lock = AppLock(
    authenticator: LocalAuthAuthenticator(),
    settings: await SecuritySettings.load(),
    screen: MethodChannelScreenSecurity(),
  )
    ..start() // холодный старт: если блокировка включена — приложение сразу заблокировано
    ..attach();

  final security = SecurityService(
    lock: lock,
    encryption: encryption,
    flushStorage: controller.flush,
    exclusive: repository.exclusive,
    onStorageReset: controller.onResume, // после сброса хранилища данные читаются (создаются) заново
    backupCipher: const BackupCipher(useIsolate: true),
  );
  await security.init();

  runApp(LifeOSApp(controller: controller, security: security));
}
