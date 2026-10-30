import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/sqlite_app_repository.dart';
import 'package:life_os/security/app_lock.dart';
import 'package:life_os/security/backup_cipher.dart';
import 'package:life_os/security/biometric_authenticator.dart';
import 'package:life_os/security/db_encryption.dart';
import 'package:life_os/security/key_store.dart';
import 'package:life_os/security/screen_security.dart';
import 'package:life_os/security/security_service.dart';
import 'package:life_os/security/security_settings.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeManager extends DbEncryptionManager {
  _FakeManager()
      : super(open: (p, {String? password}) => throw UnimplementedError(), keys: MemoryKeyStore(), path: '/nonexistent', tables: SqliteAppRepository.tables);

  bool encrypted = false;
  int destroyed = 0;

  @override
  Future<bool> isEncrypted() async => encrypted;

  @override
  Future<void> setEncrypted(bool enable) async => encrypted = enable;

  @override
  Future<void> destroy() async {
    destroyed++;
    encrypted = false;
  }
}

Future<T> _run<T>(Future<T> Function() a) => a();

class _Env {
  final AppController c;
  final SecurityService security;
  final FakeAuthenticator auth;
  final FakeScreenSecurity screen;
  final _FakeManager? manager;
  int storageResets = 0;
  _Env(this.c, this.security, this.auth, this.screen, this.manager);
  AppLock get lock => security.lock;
}

void main() {
  const testCipher = BackupCipher(iterations: 1000);

  Future<_Env> boot(
    WidgetTester tester, {
    bool lockEnabled = false,
    int timeout = 30,
    bool protect = false,
    bool encryptionSupported = false,
    AuthOutcome firstAuth = AuthOutcome.success,
    MemoryAppRepository? repo,
  }) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final c = AppController(repo ?? MemoryAppRepository(), saveDelay: const Duration(days: 1));
    await c.load();

    final auth = FakeAuthenticator(nextOutcome: firstAuth);
    final screen = FakeScreenSecurity();
    final settings = SecuritySettings(lockEnabled: lockEnabled, lockTimeoutSec: timeout, screenProtection: protect);
    final lock = AppLock(authenticator: auth, settings: settings, screen: screen)..start();
    final manager = encryptionSupported ? _FakeManager() : null;
    late _Env env;
    final security = SecurityService(
      lock: lock,
      encryption: manager,
      flushStorage: c.flush,
      exclusive: manager == null ? null : _run,
      onStorageReset: () async => env.storageResets++,
      backupCipher: testCipher,
    );
    await security.init();
    env = _Env(c, security, auth, screen, manager);

    await tester.pumpWidget(LifeOSApp(controller: c, security: security));
    await tester.pumpAndSettle();
    return env;
  }

  Future<void> shutdown(WidgetTester tester, _Env e) async {
    await tester.pumpWidget(const SizedBox());
    e.c.dispose();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
  }

  Finder hubVisible() => find.text('EXECUTIVE DASHBOARD').hitTestable();

  group('экран блокировки', () {
    testWidgets('биометрия подтверждена — приложение открывается само', (tester) async {
      final e = await boot(tester, lockEnabled: true);
      expect(find.text('Life OS заблокирован'), findsNothing);
      expect(hubVisible(), findsOneWidget);
      expect(e.auth.calls, 1);
      await shutdown(tester, e);
    });

    testWidgets('запрос отменён — содержимое закрыто, кнопка разблокирует', (tester) async {
      final e = await boot(tester, lockEnabled: true, firstAuth: AuthOutcome.cancelled);
      expect(find.text('Life OS заблокирован'), findsOneWidget);
      expect(hubVisible(), findsNothing); // под слоем блокировки содержимое недоступно

      e.auth.nextOutcome = AuthOutcome.success;
      await tester.tap(find.text('Разблокировать'));
      await tester.pumpAndSettle();
      expect(find.text('Life OS заблокирован'), findsNothing);
      expect(hubVisible(), findsOneWidget);
      await shutdown(tester, e);
    });

    testWidgets('сообщение об ошибке показывается на экране блокировки', (tester) async {
      final e = await boot(tester, lockEnabled: true, firstAuth: AuthOutcome.failed);
      expect(find.textContaining('Не удалось подтвердить личность'), findsOneWidget);
      await shutdown(tester, e);
    });

    testWidgets('возврат из фона при нулевом таймауте блокирует приложение', (tester) async {
      final e = await boot(tester, lockEnabled: true, timeout: 0);
      e.auth.nextOutcome = AuthOutcome.cancelled;
      e.lock.onLifecycle(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(find.text('Life OS заблокирован'), findsOneWidget);
      expect(hubVisible(), findsNothing);
      await shutdown(tester, e);
    });

    testWidgets('блокировка закрывает и открытые экраны (настройки)', (tester) async {
      final e = await boot(tester, lockEnabled: true, timeout: 0);
      await openSettings(tester);
      expect(find.text('НАСТРОЙКИ'), findsOneWidget);
      e.auth.nextOutcome = AuthOutcome.cancelled;
      e.lock.onLifecycle(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(find.text('Life OS заблокирован'), findsOneWidget);
      expect(find.text('НАСТРОЙКИ').hitTestable(), findsNothing);
      await shutdown(tester, e);
    });
  });

  group('шторка', () {
    testWidgets('при уходе из приложения содержимое скрывается, при возврате — нет', (tester) async {
      final e = await boot(tester, protect: true);
      e.lock.onLifecycle(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byIcon(Icons.lock_outline).hitTestable(), findsOneWidget);
      expect(hubVisible(), findsNothing);

      e.lock.onLifecycle(AppLifecycleState.resumed);
      await tester.pump();
      expect(hubVisible(), findsOneWidget);
      await shutdown(tester, e);
    });

    testWidgets('без защиты экрана шторки нет', (tester) async {
      final e = await boot(tester, protect: false);
      e.lock.onLifecycle(AppLifecycleState.inactive);
      await tester.pump();
      expect(hubVisible(), findsOneWidget);
      await shutdown(tester, e);
    });
  });

  group('настройки безопасности', () {
    testWidgets('включение блокировки требует подтверждения и открывает связанные пункты', (tester) async {
      final e = await boot(tester);
      await openSettings(tester);
      expect(find.text('Блокировать'), findsNothing);

      await tester.tap(find.text('Блокировка приложения'));
      await tester.pumpAndSettle();
      expect(e.lock.enabled, isTrue);
      expect(e.auth.reasons.single, contains('включить'));
      expect(find.text('Блокировать'), findsOneWidget);
      expect(find.text('Заблокировать сейчас'), findsOneWidget);
      await shutdown(tester, e);
    });

    testWidgets('на устройстве нет защиты экрана — блокировку включить нельзя, объяснение показано', (tester) async {
      final e = await boot(tester);
      e.auth.available = false;
      await openSettings(tester);
      await tester.tap(find.text('Блокировка приложения'));
      await tester.pumpAndSettle();
      expect(e.lock.enabled, isFalse);
      expect(find.textContaining('Сначала настройте'), findsWidgets);
      await shutdown(tester, e);
    });

    testWidgets('выключение блокировки тоже требует подтверждения', (tester) async {
      final e = await boot(tester, lockEnabled: true);
      await openSettings(tester);
      final before = e.auth.calls;
      await tester.tap(find.text('Блокировка приложения'));
      await tester.pumpAndSettle();
      expect(e.auth.calls, before + 1);
      expect(e.lock.enabled, isFalse);
      await shutdown(tester, e);
    });

    testWidgets('выбор времени блокировки', (tester) async {
      final e = await boot(tester, lockEnabled: true);
      await openSettings(tester);
      expect(find.text('Через 30 секунд'), findsOneWidget);

      await tester.tap(find.text('Блокировать'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Через 5 минут').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(e.lock.timeoutSec, 300);
      await shutdown(tester, e);
    });

    testWidgets('«Заблокировать сейчас» закрывает приложение', (tester) async {
      final e = await boot(tester, lockEnabled: true);
      await openSettings(tester);
      e.auth.nextOutcome = AuthOutcome.cancelled;
      await tester.tap(find.text('Заблокировать сейчас'));
      await tester.pumpAndSettle();
      expect(find.text('Life OS заблокирован'), findsOneWidget);
      await shutdown(tester, e);
    });

    testWidgets('защита содержимого включается и передаётся нативной части', (tester) async {
      final e = await boot(tester);
      await openSettings(tester);
      await tester.tap(find.text('Скрывать содержимое'));
      await tester.pumpAndSettle();
      expect(e.lock.screenProtection, isTrue);
      expect(e.screen.secure, isTrue);
      await shutdown(tester, e);
    });
  });

  group('шифрование базы в настройках', () {
    testWidgets('без поддержки пункта нет', (tester) async {
      final e = await boot(tester, encryptionSupported: false);
      await openSettings(tester);
      expect(find.text('Шифровать базу данных'), findsNothing);
      await shutdown(tester, e);
    });

    testWidgets('включение с подтверждением', (tester) async {
      final e = await boot(tester, encryptionSupported: true);
      await openSettings(tester);
      await tester.tap(find.text('Шифровать базу данных'));
      await tester.pumpAndSettle();
      expect(find.text('Зашифровать базу данных?'), findsOneWidget);
      expect(find.textContaining('Сначала сделайте экспорт'), findsOneWidget);

      await tester.tap(find.text('Зашифровать'));
      await tester.pumpAndSettle();
      expect(e.manager!.encrypted, isTrue);
      expect(e.security.encrypted, isTrue);
      expect(find.textContaining('Включено'), findsOneWidget);
      await shutdown(tester, e);
    });

    testWidgets('отмена подтверждения ничего не меняет', (tester) async {
      final e = await boot(tester, encryptionSupported: true);
      await openSettings(tester);
      await tester.tap(find.text('Шифровать базу данных'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(e.manager!.encrypted, isFalse);
      await shutdown(tester, e);
    });

    testWidgets('хранилище недоступно: предлагается сброс, нужно слово-подтверждение', (tester) async {
      final e = await boot(tester, encryptionSupported: true, repo: MemoryAppRepository(loadError: StateError('нет ключа')));
      await openSettings(tester);
      expect(find.text('ХРАНИЛИЩЕ НЕДОСТУПНО'), findsOneWidget);

      await tester.tap(find.text('Сбросить хранилище'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'нет');
      await tester.tap(find.text('Удалить и начать заново'));
      await tester.pumpAndSettle();
      expect(e.manager!.destroyed, 0);

      await tester.enterText(find.byType(TextField), 'сброс');
      await tester.tap(find.text('Удалить и начать заново'));
      await tester.pumpAndSettle();
      expect(e.manager!.destroyed, 1);
      expect(e.storageResets, 1);
      await shutdown(tester, e);
    });

    testWidgets('когда хранилище в порядке, раздела сброса нет', (tester) async {
      final e = await boot(tester, encryptionSupported: true);
      await openSettings(tester);
      expect(find.text('ХРАНИЛИЩЕ НЕДОСТУПНО'), findsNothing);
      await shutdown(tester, e);
    });
  });

  group('зашифрованные резервные копии', () {
    String? clipboard;

    setUp(() {
      clipboard = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      });
    });
    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    Future<void> exportEncrypted(WidgetTester tester, String password) async {
      await tester.tap(find.text('Экспорт резервной копии'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), password);
      await tester.enterText(find.byType(TextField).at(1), password);
      await tester.tap(find.text('Экспортировать'));
      await tester.pumpAndSettle();
    }

    testWidgets('экспорт с паролем кладёт в буфер зашифрованную копию', (tester) async {
      final e = await boot(tester);
      e.c.updateWealth(netWorth: 5555555);
      await openSettings(tester);
      await exportEncrypted(tester, 'надёжный пароль 1');

      expect(clipboard, isNotNull);
      expect(BackupCipher.looksEncrypted(clipboard!), isTrue);
      expect(clipboard, isNot(contains('5555555')));
      expect(await testCipher.decrypt(clipboard!, 'надёжный пароль 1'), contains('5555555'));
      await shutdown(tester, e);
    });

    testWidgets('пароли не совпадают или слишком короткие — экспорт не выполняется', (tester) async {
      final e = await boot(tester);
      await openSettings(tester);
      await tester.tap(find.text('Экспорт резервной копии'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'длинный пароль 1');
      await tester.enterText(find.byType(TextField).at(1), 'другой пароль 2');
      await tester.tap(find.text('Экспортировать'));
      await tester.pumpAndSettle();
      expect(clipboard, isNull);
      expect(find.text('Экспорт резервной копии'), findsWidgets); // диалог остался

      await tester.enterText(find.byType(TextField).at(0), 'short');
      await tester.enterText(find.byType(TextField).at(1), 'short');
      await tester.tap(find.text('Экспортировать'));
      await tester.pumpAndSettle();
      expect(clipboard, isNull);
      await shutdown(tester, e);
    });

    testWidgets('экспорт без шифрования доступен, но явно помечен', (tester) async {
      final e = await boot(tester);
      await openSettings(tester);
      await tester.tap(find.text('Экспорт резервной копии'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Без шифрования').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Экспортировать'));
      await tester.pumpAndSettle();
      expect(clipboard, isNotNull);
      expect(BackupCipher.looksEncrypted(clipboard!), isFalse);
      expect(find.textContaining('без шифрования'), findsWidgets);
      await shutdown(tester, e);
    });

    Future<void> importText(WidgetTester tester, String text) async {
      await tester.tap(find.text('Импорт резервной копии'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), text);
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
    }

    testWidgets('импорт зашифрованной копии с верным паролем восстанавливает данные', (tester) async {
      final e = await boot(tester);
      e.c.updateWealth(netWorth: 5555555);
      final enc = await testCipher.encrypt(e.c.exportBackup(), 'надёжный пароль 1');
      e.c.updateWealth(netWorth: 1);

      await openSettings(tester);
      await importText(tester, enc);
      expect(find.text('Копия зашифрована'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'надёжный пароль 1');
      await tester.tap(find.text('Расшифровать и заменить данные'));
      await tester.pumpAndSettle();

      expect(e.c.netWorth, 5555555);
      await shutdown(tester, e);
    });

    testWidgets('неверный пароль: данные не тронуты, понятное сообщение', (tester) async {
      final e = await boot(tester);
      e.c.updateWealth(netWorth: 5555555);
      final enc = await testCipher.encrypt(e.c.exportBackup(), 'надёжный пароль 1');
      e.c.updateWealth(netWorth: 1);

      await openSettings(tester);
      await importText(tester, enc);
      await tester.enterText(find.byType(TextField), 'неверный пароль 22');
      await tester.tap(find.text('Расшифровать и заменить данные'));
      await tester.pumpAndSettle();

      expect(e.c.netWorth, 1);
      expect(find.textContaining('Неверный пароль'), findsOneWidget);
      await shutdown(tester, e);
    });

    testWidgets('обычная (незашифрованная) копия по-прежнему импортируется', (tester) async {
      final e = await boot(tester);
      e.c.updateWealth(netWorth: 4444444);
      final plain = e.c.exportBackup();
      e.c.updateWealth(netWorth: 1);
      await openSettings(tester);
      await importText(tester, plain);
      expect(e.c.netWorth, 4444444);
      await shutdown(tester, e);
    });
  });
}
