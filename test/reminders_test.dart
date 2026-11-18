import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/reminders.dart';
import 'package:life_os/core/sections.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/data/reminder_scheduler.dart';
import 'package:life_os/models/bill.dart';
import 'package:life_os/security/app_lock.dart';
import 'package:life_os/security/biometric_authenticator.dart';
import 'package:life_os/security/security_service.dart';
import 'package:life_os/security/security_settings.dart';
import 'package:life_os/state/app_controller.dart';
import 'package:life_os/state/reminders.dart';
import 'package:life_os/ui/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 18.11.2026, среда, 12:00
  final now = DateTime(2026, 11, 18, 12);

  group('расписание', () {
    test('отметка дня: 7 вечеров вперёд, отмеченные дни пропускаются, прошедшее время — нет', () {
      final p = planReminders(
        now: now,
        prefs: const ReminderPrefs(checkIn: true),
        checkedDays: {'2026-11-18', '2026-11-20'},
        bills: const [],
      );
      expect([for (final r in p) r.at.day], [19, 21, 22, 23, 24]);
      expect(p.every((r) => r.at.hour == 21 && r.kind == 'checkin'), isTrue);
      final late = planReminders(now: DateTime(2026, 11, 18, 22), prefs: const ReminderPrefs(checkIn: true), checkedDays: {}, bills: const []);
      expect(late.first.at, DateTime(2026, 11, 19, 21)); // сегодняшние 21:00 уже прошли
    });

    test('счета: накануне и в день срока; просроченный — одно напоминание сегодня', () {
      final bills = [
        Bill(id: 'a', title: 'Интернет', amount: 650, firstDue: '2026-11-20', createdAt: now),
        Bill(id: 'b', title: 'Аренда', firstDue: '2026-11-16', createdAt: now),
        Bill(id: 'c', title: 'Страховка', amount: 9000, firstDue: '2027-03-01', repeat: BillRepeat.year, createdAt: now),
      ];
      final p = planReminders(now: DateTime(2026, 11, 18, 8), prefs: const ReminderPrefs(bills: true), checkedDays: {}, bills: bills);
      expect([for (final r in p) '${r.at.day}.${r.at.hour} ${r.title}: ${r.body}'], [
        '18.10 Аренда: Срок оплаты прошёл',
        '19.10 Интернет: Завтра срок оплаты · 650 ₽',
        '20.10 Интернет: Сегодня срок оплаты · 650 ₽',
      ]);
    });

    test('обзор: одно напоминание в день, когда пора; нет обзоров — нет напоминаний', () {
      ReminderPrefs on = const ReminderPrefs(review: true);
      expect(planReminders(now: now, prefs: on, checkedDays: {}, bills: const [], reviewDueAt: now).single.at, DateTime(2026, 11, 18, 19));
      expect(planReminders(now: DateTime(2026, 11, 18, 20), prefs: on, checkedDays: {}, bills: const [], reviewDueAt: now).single.at,
          DateTime(2026, 11, 19, 19));
      expect(planReminders(now: now, prefs: on, checkedDays: {}, bills: const [], reviewDueAt: DateTime(2026, 11, 21, 9)).single.at,
          DateTime(2026, 11, 21, 19));
      expect(planReminders(now: now, prefs: on, checkedDays: {}, bills: const []), isEmpty);
      expect(planReminders(now: now, prefs: const ReminderPrefs(), checkedDays: {}, bills: const [], reviewDueAt: now), isEmpty);
    });

    test('время кодируется туда-обратно; всё по возрастанию и с пределом', () {
      expect(ReminderTime.decode(const ReminderTime(7, 45).encoded).label, '07:45');
      final many = [for (var i = 0; i < 40; i++) Bill(id: 'b$i', title: 'Счёт $i', firstDue: '2026-11-21', createdAt: now)];
      final p = planReminders(now: now, prefs: const ReminderPrefs(checkIn: true, bills: true), checkedDays: {}, bills: many);
      expect(p.length, reminderMaxCount);
      for (var i = 1; i < p.length; i++) {
        expect(p[i].at.isBefore(p[i - 1].at), isFalse);
      }
    });
  });

  group('служба', () {
    late AppController c;
    late MemoryReminderScheduler scheduler;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));
      await c.load();
      scheduler = MemoryReminderScheduler();
    });

    Future<Reminders> make() async {
      final r = Reminders(controller: c, scheduler: scheduler, prefs: prefs);
      await r.init();
      return r;
    }

    test('по умолчанию выключено; включение спрашивает разрешение и ставит расписание', () async {
      final r = await make();
      await r.resync();
      expect(scheduler.scheduled, isEmpty);
      await r.update(const ReminderPrefs(checkIn: true));
      expect(r.permitted, isTrue);
      expect(scheduler.scheduled.first.at, DateTime(2026, 11, 18, 21));
      c.setCheckIn(now, rating: 4);
      await r.resync();
      expect(scheduler.scheduled.first.at, DateTime(2026, 11, 19, 21)); // сегодня уже отмечено
    });

    test('разрешение не дано — ничего не ставится, видно в состоянии', () async {
      scheduler.grantOnRequest = false;
      final r = await make();
      await r.update(const ReminderPrefs(checkIn: true, bills: true));
      expect(r.permitted, isFalse);
      expect(scheduler.scheduled, isEmpty);
      scheduler.grantOnRequest = true;
      expect(await r.requestPermission(), isTrue);
      expect(scheduler.scheduled, isNotEmpty);
    });

    test('скрытый раздел не напоминает; настройки переживают перезапуск', () async {
      final r = await make();
      await r.update(const ReminderPrefs(checkIn: true, checkInTime: ReminderTime(22, 30)));
      c.setSectionShown(Sections.checkIn, false);
      await r.resync();
      expect(scheduler.scheduled, isEmpty);
      final again = await make();
      expect((again.prefs.checkIn, again.prefs.checkInTime.label), (true, '22:30'));
    });

    test('без плагина (не Android) — молча ничего', () async {
      final r = Reminders.disabled(c);
      await r.init();
      await r.update(const ReminderPrefs(checkIn: true));
      expect((r.supported, r.permitted), (false, false));
    });
  });

  testWidgets('настройки: включить напоминание, отказ в разрешении виден (360 px)', (tester) async {
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero);
    await c.load();
    final scheduler = MemoryReminderScheduler(grantOnRequest: false);
    final reminders = Reminders(controller: c, scheduler: scheduler, prefs: await SharedPreferences.getInstance());
    await reminders.init();
    final lock = AppLock(authenticator: FakeAuthenticator(available: false), settings: SecuritySettings())..start();
    final security = SecurityService(lock: lock, reminders: reminders);
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(controller: c, security: security)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const ValueKey('reminder_checkin')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('reminder_checkin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminders_denied')), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder_checkin_time')), findsOneWidget);
    scheduler.grantOnRequest = true;
    await tester.tap(find.text('Разрешить'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminders_denied')), findsNothing);
    expect(find.textContaining('Ближайшее: 18.11.2026 21:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
