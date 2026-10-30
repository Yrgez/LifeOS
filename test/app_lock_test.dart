import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/security/app_lock.dart';
import 'package:life_os/security/biometric_authenticator.dart';
import 'package:life_os/security/screen_security.dart';
import 'package:life_os/security/security_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late FakeAuthenticator auth;
  late FakeScreenSecurity screen;

  Future<AppLock> make({bool enabled = true, int timeout = 30, bool protect = false}) async {
    SharedPreferences.setMockInitialValues({});
    final s = await SecuritySettings.load();
    s
      ..lockEnabled = enabled
      ..lockTimeoutSec = timeout
      ..screenProtection = protect;
    return AppLock(authenticator: auth, settings: s, screen: screen, clock: () => now)..start();
  }

  setUp(() {
    now = DateTime(2026, 10, 24, 12);
    auth = FakeAuthenticator();
    screen = FakeScreenSecurity();
  });

  group('запуск и разблокировка', () {
    test('холодный старт: заблокировано, если блокировка включена', () async {
      expect((await make()).locked, isTrue);
      expect((await make(enabled: false)).locked, isFalse);
    });

    test('успешная разблокировка снимает блокировку', () async {
      final l = await make();
      expect(await l.unlock(), AuthOutcome.success);
      expect(l.locked, isFalse);
      expect(l.message, isNull);
    });

    test('неудача и блокировка системой оставляют приложение закрытым и объясняют причину', () async {
      final l = await make();
      auth.nextOutcome = AuthOutcome.failed;
      await l.unlock();
      expect(l.locked, isTrue);
      expect(l.message, contains('Не удалось'));

      auth.nextOutcome = AuthOutcome.lockedOut;
      await l.unlock();
      expect(l.locked, isTrue);
      expect(l.message, contains('Слишком много'));
    });

    test('отмена запроса не показывает ошибку', () async {
      final l = await make();
      auth.nextOutcome = AuthOutcome.cancelled;
      await l.unlock();
      expect(l.locked, isTrue);
      expect(l.message, isNull);
    });

    test('защита экрана снята с устройства: приложение открывается, блокировка отключается и это запоминается', () async {
      final l = await make();
      auth.available = false;
      expect(await l.unlock(), AuthOutcome.notAvailable);
      expect(l.locked, isFalse);
      expect(l.enabled, isFalse);
      expect(l.message, contains('не настроена защита экрана'));
      final reloaded = await SecuritySettings.load();
      expect(reloaded.lockEnabled, isFalse);
    });

    test('разблокировка без блокировки не вызывает запрос', () async {
      final l = await make(enabled: false);
      expect(await l.unlock(), AuthOutcome.success);
      expect(auth.calls, 0);
    });
  });

  group('блокировка при уходе в фон', () {
    test('короткий уход (меньше таймаута) не блокирует', () async {
      final l = await make(timeout: 30);
      await l.unlock();
      l.onLifecycle(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 29));
      l.onLifecycle(AppLifecycleState.resumed);
      expect(l.locked, isFalse);
    });

    test('уход дольше таймаута блокирует', () async {
      final l = await make(timeout: 30);
      await l.unlock();
      l.onLifecycle(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 31));
      l.onLifecycle(AppLifecycleState.resumed);
      expect(l.locked, isTrue);
    });

    test('таймаут 0: блокировка срабатывает сразу при уходе в фон', () async {
      final l = await make(timeout: 0);
      await l.unlock();
      l.onLifecycle(AppLifecycleState.paused);
      expect(l.locked, isTrue); // до возврата — чтобы содержимое не мелькнуло
    });

    test('состояние hidden приравнено к фону', () async {
      final l = await make(timeout: 0);
      await l.unlock();
      l.onLifecycle(AppLifecycleState.hidden);
      expect(l.locked, isTrue);
    });

    test('только inactive (шторка уведомлений, системные диалоги) не блокирует', () async {
      final l = await make(timeout: 0);
      await l.unlock();
      l.onLifecycle(AppLifecycleState.inactive);
      now = now.add(const Duration(minutes: 10));
      l.onLifecycle(AppLifecycleState.resumed);
      expect(l.locked, isFalse);
    });

    test('блокировка выключена — фон ничего не блокирует', () async {
      final l = await make(enabled: false, timeout: 0);
      l.onLifecycle(AppLifecycleState.paused);
      now = now.add(const Duration(hours: 1));
      l.onLifecycle(AppLifecycleState.resumed);
      expect(l.locked, isFalse);
    });

    test('события жизненного цикла во время системного запроса игнорируются (нет зацикливания)', () async {
      final l = await make(timeout: 0);
      auth.duringAuth = () async {
        l.onLifecycle(AppLifecycleState.inactive);
        l.onLifecycle(AppLifecycleState.paused);
      };
      await l.unlock();
      l.onLifecycle(AppLifecycleState.resumed); // возврат из системного диалога
      expect(l.locked, isFalse);
    });

    test('lockNow блокирует только при включённой блокировке', () async {
      final l = await make();
      await l.unlock();
      l.lockNow();
      expect(l.locked, isTrue);
      final off = await make(enabled: false);
      off.lockNow();
      expect(off.locked, isFalse);
    });
  });

  group('шторка и защита от скриншотов', () {
    test('шторка появляется при уходе из приложения и исчезает при возврате', () async {
      final l = await make(enabled: false, protect: true);
      l.onLifecycle(AppLifecycleState.inactive);
      expect(l.shielded, isTrue);
      l.onLifecycle(AppLifecycleState.resumed);
      expect(l.shielded, isFalse);
    });

    test('без защиты экрана шторки нет', () async {
      final l = await make(enabled: false, protect: false);
      l.onLifecycle(AppLifecycleState.paused);
      expect(l.shielded, isFalse);
    });

    test('когда приложение заблокировано, шторка не нужна — всё закрывает экран блокировки', () async {
      final l = await make(protect: true);
      l.onLifecycle(AppLifecycleState.paused);
      expect(l.locked, isTrue);
      expect(l.shielded, isFalse);
    });

    test('настройка применяется к защите от скриншотов при запуске и при изменении', () async {
      final l = await make(protect: true);
      expect(screen.secure, isTrue);
      await l.setScreenProtection(false);
      expect(screen.secure, isFalse);
      expect((await SecuritySettings.load()).screenProtection, isFalse);
    });
  });

  group('включение и выключение блокировки', () {
    test('включение требует подтверждения и сохраняется', () async {
      final l = await make(enabled: false);
      expect(await l.setEnabled(true), AuthOutcome.success);
      expect(l.enabled, isTrue);
      expect(l.locked, isFalse); // только что подтвердили личность
      expect(auth.reasons.single, contains('включить'));
      expect((await SecuritySettings.load()).lockEnabled, isTrue);
    });

    test('без защиты экрана на устройстве включить нельзя', () async {
      final l = await make(enabled: false);
      auth.available = false;
      expect(await l.setEnabled(true), AuthOutcome.notAvailable);
      expect(l.enabled, isFalse);
      expect(l.message, contains('Сначала настройте'));
    });

    test('отмена подтверждения не меняет настройку', () async {
      final l = await make(enabled: false);
      auth.nextOutcome = AuthOutcome.cancelled;
      expect(await l.setEnabled(true), AuthOutcome.cancelled);
      expect(l.enabled, isFalse);
    });

    test('выключение тоже требует подтверждения личности', () async {
      final l = await make();
      await l.unlock();
      auth.nextOutcome = AuthOutcome.failed;
      expect(await l.setEnabled(false), AuthOutcome.failed);
      expect(l.enabled, isTrue);
      auth.nextOutcome = AuthOutcome.success;
      expect(await l.setEnabled(false), AuthOutcome.success);
      expect(l.enabled, isFalse);
      expect(auth.reasons.last, contains('отключить'));
    });

    test('повторная установка того же значения ничего не делает', () async {
      final l = await make();
      final before = auth.calls;
      expect(await l.setEnabled(true), AuthOutcome.success);
      expect(auth.calls, before);
    });
  });

  group('таймаут', () {
    test('допустимое значение сохраняется, недопустимое игнорируется', () async {
      final l = await make();
      await l.setTimeout(300);
      expect(l.timeoutSec, 300);
      await l.setTimeout(7);
      expect(l.timeoutSec, 300);
      expect((await SecuritySettings.load()).lockTimeoutSec, 300);
    });
  });

  group('SecuritySettings', () {
    test('круг сохранения и загрузки', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await SecuritySettings.load();
      s
        ..lockEnabled = true
        ..lockTimeoutSec = 60
        ..screenProtection = true;
      await s.save();
      final back = await SecuritySettings.load();
      expect(back.lockEnabled, isTrue);
      expect(back.lockTimeoutSec, 60);
      expect(back.screenProtection, isTrue);
    });

    test('значения по умолчанию и недопустимый таймаут в хранилище', () async {
      SharedPreferences.setMockInitialValues({'sec_lock_timeout_sec': 12345});
      final s = await SecuritySettings.load();
      expect(s.lockEnabled, isFalse);
      expect(s.screenProtection, isFalse);
      expect(s.lockTimeoutSec, 30);
    });
  });
}
