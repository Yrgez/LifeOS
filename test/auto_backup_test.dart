import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catenna/app.dart';
import 'package:catenna/core/backup_schedule.dart';
import 'package:catenna/data/app_data.dart';
import 'package:catenna/data/app_repository.dart';
import 'package:catenna/data/backup_storage.dart';
import 'package:catenna/data/file_source.dart';
import 'package:catenna/models/life_event.dart';
import 'package:catenna/security/app_lock.dart';
import 'package:catenna/security/auto_backup.dart';
import 'package:catenna/security/backup_cipher.dart';
import 'package:catenna/security/biometric_authenticator.dart';
import 'package:catenna/security/key_store.dart';
import 'package:catenna/security/security_service.dart';
import 'package:catenna/security/security_settings.dart';
import 'package:catenna/state/app_controller.dart';
import 'package:catenna/ui/screens/settings_screen.dart';
import 'package:catenna/ui/widgets/backup_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

const fastCipher = BackupCipher(iterations: 1000);

void main() {
  group('правила', () {
    test('имя файла несёт время; чужие файлы не наши', () {
      final t = DateTime(2026, 11, 18, 20, 31);
      expect(backupFileName(t), 'catenna-backup-2026-11-18-2031.catenna');
      expect(backupTimeOf('catenna-backup-2026-11-18-2031.catenna'), t);
      expect(backupTimeOf('catenna-backup-2026-11-18-2031-2.catenna'), t);
      expect(backupTimeOf('заметки.txt'), isNull);
      expect(backupTimeOf('catenna-backup-2026-11-18.catenna'), isNull);
    });

    test('срок копии — по календарным дням', () {
      final now = DateTime(2026, 11, 18, 9);
      expect(backupDue(null, now, 7), isTrue);
      expect(backupDue(DateTime(2026, 11, 12, 23), now, 7), isFalse);
      expect(backupDue(DateTime(2026, 11, 11, 23), now, 7), isTrue);
      expect(backupDue(DateTime(2026, 11, 17, 23, 59), now, 1), isTrue);
      expect(daysSinceBackup(DateTime(2026, 11, 4), now), 14);
      expect(daysSinceBackup(null, now), isNull);
    });

    test('очистка: остаются самые новые свои копии, чужие файлы не трогаются', () {
      final names = [for (var d = 1; d <= 10; d++) backupFileName(DateTime(2026, 11, d, 12)), 'заметки.txt', 'catenna-backup-old.json'];
      final drop = backupsToDelete(names, keep: 8);
      expect(drop, [backupFileName(DateTime(2026, 11, 2, 12)), backupFileName(DateTime(2026, 11, 1, 12))]);
      expect(backupsToDelete(names.take(3), keep: 8), isEmpty);
    });
  });

  group('служба', () {
    late DateTime now;
    late AppController c;
    late MemoryBackupStorage storage;
    late MemoryKeyStore keys;
    late SharedPreferences prefs;

    Future<AutoBackup> make() async {
      final b = AutoBackup(controller: c, storage: storage, keys: keys, cipher: fastCipher, prefs: prefs, clock: () => now);
      await b.init();
      return b;
    }

    setUp(() async {
      now = DateTime(2026, 11, 18, 12);
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));
      await c.load();
      storage = MemoryBackupStorage();
      keys = MemoryKeyStore();
    });

    test('без папки или пароля копия не делается; короткий пароль отвергается', () async {
      final b = await make();
      expect(await b.maybeRun(), isNull);
      expect(await b.runNow(), BackupOutcome.notConfigured);
      expect(await b.setPassword('короткий'.substring(0, 5)), isFalse);
      expect(await b.chooseFolder(), isTrue);
      expect(b.configured, isFalse);
      expect(await b.setPassword('надёжный пароль'), isTrue);
      expect(b.configured, isTrue);
    });

    test('данные прочитаны не полностью — копия не делается и не вытесняет прежние', () async {
      final damaged = AppData.fromJson({...AppData.blank(now: now).toJson(), 'goals': 'не список'}, now: now);
      c = AppController(MemoryAppRepository(data: damaged), clock: () => now, saveDelay: const Duration(days: 1));
      await c.load();
      final b = await make();
      await b.chooseFolder();
      await b.setPassword('надёжный пароль');
      expect(await b.runNow(), BackupOutcome.failed);
      expect(await b.maybeRun(), BackupOutcome.failed);
      expect(storage.folders[b.folder] ?? const {}, isEmpty);
      expect(b.error, contains('не полностью'));
    });

    test('копия зашифрована и восстанавливается в данные один к одному', () async {
      c.addEvent(title: 'Пробежка', dimensions: [LifeDimension.body]);
      final b = await make();
      await b.chooseFolder();
      await b.setPassword('надёжный пароль');
      expect(await b.runNow(), BackupOutcome.done);
      final files = storage.folders[b.folder]!;
      expect(files.keys.single, 'catenna-backup-2026-11-18-1200.catenna');
      final text = utf8.decode(files.values.single);
      expect(BackupCipher.looksEncrypted(text), isTrue);
      expect(text, isNot(contains('Пробежка'))); // без пароля не прочитать
      final restored = AppController(MemoryAppRepository(), clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));
      await restored.load();
      expect(restored.importBackup(await fastCipher.decrypt(text, 'надёжный пароль')), isTrue);
      expect(restored.events.single.title, 'Пробежка');
    });

    test('по расписанию: в тот же день — нет, через срок — да; хранятся 8 последних, чужие файлы целы', () async {
      final b = await make();
      await b.chooseFolder();
      await b.setPassword('надёжный пароль');
      await b.setInterval(1);
      expect(await b.maybeRun(), BackupOutcome.done);
      expect(await b.maybeRun(), isNull); // тот же день
      storage.folders[b.folder]!['заметки.txt'] = Uint8List.fromList([1]);
      for (var i = 1; i <= 10; i++) {
        now = now.add(const Duration(days: 1));
        expect(await b.maybeRun(), BackupOutcome.done);
      }
      final names = storage.folders[b.folder]!.keys.toList();
      expect(names.where((n) => backupTimeOf(n) != null).length, backupKeepCount);
      expect(names, contains('заметки.txt'));
      expect(names, contains(backupFileName(now))); // самая свежая на месте
    });

    test('нет доступа и сбой записи: ошибка запоминается, прошлые копии и время последней не теряются', () async {
      final b = await make();
      await b.chooseFolder();
      await b.setPassword('надёжный пароль');
      await b.runNow();
      final first = b.lastAt;
      now = now.add(const Duration(days: 8));
      storage.writeError = StateError('диск полон');
      expect(await b.runNow(), BackupOutcome.failed);
      expect(b.error, contains('диск полон'));
      expect(b.lastAt, first);
      expect(storage.folders[b.folder]!.length, 1);
      expect(b.needsAttention(now), isTrue);

      storage
        ..writeError = null
        ..access = false;
      expect(await b.runNow(), BackupOutcome.noAccess);
      expect(b.error, contains('нет доступа'));

      storage.access = true;
      expect(await b.runNow(), BackupOutcome.done);
      expect(b.error, isNull);
      expect(b.needsAttention(now), isFalse);
    });

    test('настройки переживают перезапуск; отключение забывает папку и пароль', () async {
      final b = await make();
      await b.chooseFolder();
      await b.setPassword('надёжный пароль');
      await b.setInterval(30);
      await b.runNow();
      final again = await make();
      expect((again.folder, again.intervalDays, again.lastAt, again.hasPassword), (b.folder, 30, b.lastAt, true));
      await again.disable();
      expect(again.configured, isFalse);
      expect(await keys.read(AutoBackup.passKey), isNull);
      expect((await make()).folder, isNull);
    });

    test('напоминание: копий не было — да; свежая — нет; 14 дней — да', () async {
      final b = await make();
      expect(b.needsAttention(now), isTrue);
      await b.chooseFolder();
      await b.setPassword('надёжный пароль');
      await b.runNow();
      expect(b.needsAttention(now.add(const Duration(days: 13))), isFalse);
      expect(b.needsAttention(now.add(const Duration(days: 14))), isTrue);
      expect(AutoBackup.disabled(c).needsAttention(now), isFalse); // где копии недоступны — не напоминаем
    });
  });

  group('экраны', () {
    final now = DateTime(2026, 11, 18, 12);

    testWidgets('восстановление из файла зашифрованной копии', (tester) async {
      final source = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero, initialData: (n) => AppData.blank(now: n));
      await source.load();
      source.addEvent(title: 'Из копии', dimensions: [LifeDimension.mind]);
      final enc = await fastCipher.encrypt(source.exportBackup(), 'надёжный пароль');
      final c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero, initialData: (n) => AppData.blank(now: n));
      await c.load();
      final files = FakeFileSource(PickedFile(backupFileName(now), Uint8List.fromList(utf8.encode(enc))));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => restoreFromFile(context, c, files: files, cipher: fastCipher), child: const Text('восстановить')),
          ),
        ),
      ));
      await tester.tap(find.text('восстановить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'надёжный пароль');
      await tester.tap(find.text('Расшифровать и заменить данные'));
      await tester.pumpAndSettle();
      expect(c.events.single.title, 'Из копии');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      source.dispose();
      c.dispose();
    });

    testWidgets('«Сегодня» напоминает о копии, настройки показывают папку и пароль (360 px)', (tester) async {
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero);
      await c.load();
      final storage = MemoryBackupStorage();
      final backup = AutoBackup(controller: c, storage: storage, keys: MemoryKeyStore(), cipher: fastCipher, prefs: prefs, clock: () => now);
      await backup.init();
      await backup.chooseFolder();
      await backup.setPassword('надёжный пароль');
      storage.access = false;
      await backup.runNow(); // ошибка — повод напомнить
      final lock = AppLock(authenticator: FakeAuthenticator(available: false), settings: SecuritySettings())..start();
      final security = SecurityService(lock: lock, backupCipher: fastCipher, backup: backup);
      await tester.pumpWidget(CatennaApp(controller: c, security: security));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('backup_reminder')), findsOneWidget);
      expect(find.text('Автокопия не получилась'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('backup_reminder')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const ValueKey('backup_status')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Пароль копий'), findsOneWidget);
      expect(find.textContaining('нет доступа'), findsWidgets);
      storage.access = true;
      await tester.runAsync(backup.runNow);
      await tester.pumpAndSettle();
      expect(find.textContaining('Последняя копия: 18.11.2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Назад'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('backup_reminder')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('открытый экспорт — «Сохранить как»: файл с датой в имени и меткой UTF-8; отмена — без сообщения', (tester) async {
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero);
      await c.load();
      final storage = MemoryBackupStorage();
      final backup = AutoBackup(controller: c, storage: storage, keys: MemoryKeyStore(), cipher: fastCipher, prefs: prefs, clock: () => now);
      await backup.init();
      final lock = AppLock(authenticator: FakeAuthenticator(available: false), settings: SecuritySettings())..start();
      final security = SecurityService(lock: lock, backupCipher: fastCipher, backup: backup);
      await tester.pumpWidget(CatennaApp(controller: c, security: security));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute(builder: (_) => SettingsScreen(controller: c, security: security)));
      await tester.pumpAndSettle();
      final tile = find.text('События (CSV)');
      await tester.scrollUntilVisible(tile, 300, scrollable: find.byType(Scrollable).first);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      final file = storage.savedAs['catenna-events-2026-11-18.csv']!;
      expect(file.take(3), [0xEF, 0xBB, 0xBF]);
      expect(find.textContaining('сохранён'), findsOneWidget);

      storage.saveAsCancelled = true;
      ScaffoldMessenger.of(tester.element(tile)).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.textContaining('сохранён'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });
}
