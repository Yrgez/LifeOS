import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catenna/app.dart';
import 'package:catenna/core/chronicle.dart';
import 'package:catenna/data/app_data.dart';
import 'package:catenna/data/app_repository.dart';
import 'package:catenna/data/sqlite_app_repository.dart';
import 'package:catenna/models/models.dart';
import 'package:catenna/state/app_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late DateTime now;
  AppController make([AppRepository? repo]) =>
      AppController(repo ?? MemoryAppRepository(), clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));
  setUp(() => now = DateTime(2026, 11, 18, 12));

  group('капитал по счетам', () {
    test('сумма последних остатков; снимки не перезаписываются; ручной капитал больше не правится', () async {
      final c = make();
      await c.load();
      c.updateWealth(netWorth: 100000);
      expect((c.netWorth, c.netWorthFromAccounts), (100000, false));
      final dep = c.addAccount('Вклад', 1800000)!;
      c.addAccount('Кредитка', -20000);
      expect(c.netWorth, 1780000);
      expect(c.netWorthFromAccounts, isTrue);
      now = now.add(const Duration(days: 3));
      expect(c.setAccountBalance(dep, 1810000), isTrue);
      expect(c.setAccountBalance(dep, 1, at: now.subtract(const Duration(days: 10))), isFalse); // не раньше последнего снимка
      expect(c.accounts.first.history.map((h) => h.amount), [1800000, 1810000]);
      expect(c.netWorth, 1790000);
      c.updateWealth(netWorth: 5); // при счетах ручной капитал игнорируется
      expect(c.netWorth, 1790000);
      expect(c.addAccount(' ', 1), isNull);
      expect(c.snapshotFor(now)!.netWorth, 1790000); // дневной снимок — по счетам
    });

    test('счёт: битый снимок отвергает счёт; копия и SQLite сохраняют историю', () async {
      final a = Account(id: 'a', name: 'Брокер', history: [BalanceSnapshot(DateTime(2026, 1, 1), 100)]).toJson();
      expect(Account.tryFromJson(a)!.latest.amount, 100);
      expect(Account.tryFromJson({...a, 'hist': [{'t': 1, 'a': 1.5}]}), isNull);
      expect(Account.tryFromJson({...a, 'hist': []}), isNull);

      final db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
      addTearDown(db.close);
      final c = make(SqliteAppRepository(opener: () async => db));
      await c.load();
      final id = c.addAccount('Брокер', 520000)!;
      now = now.add(const Duration(days: 1));
      c.setAccountBalance(id, 530000);
      await c.flush();
      final c2 = make(SqliteAppRepository(opener: () async => db));
      await c2.load();
      expect(jsonEncode(c2.accounts.map((a) => a.toJson()).toList()), jsonEncode(c.accounts.map((a) => a.toJson()).toList()));
      expect(c2.accounts.single.history, hasLength(2));
      final j = jsonDecode(c.exportBackup()) as Map<String, dynamic>;
      expect(() => AppData.fromJson({...j, 'accounts': [{'id': 'x', 'name': 'y', 'hist': []}]}, strict: true), throwsFormatException);
    });
  });

  test('доход для чекпоинтов: последний полный месяц по журналу, иначе план', () async {
    final c = make();
    await c.load();
    c.updateWealth(income: 300000);
    expect(c.incomeEvidence, 300000);
    c.addTransaction(categoryId: 'salary', amount: 250000, at: DateTime(2026, 10, 5));
    c.addTransaction(categoryId: 'salary', amount: 999999, at: DateTime(2026, 11, 5)); // текущий месяц не полный
    expect(c.incomeEvidence, 250000);
  });

  group('история целей', () {
    test('постановка, правки, план и достижение — в журнал цели и в хронику', () async {
      final c = make();
      await c.load();
      c.addGoal('Доход 300 тыс.', 'Карьера', ['Шаг']);
      final g = c.goals.single.id;
      now = now.add(const Duration(days: 30));
      c.updateGoal(g, title: 'Доход 500 тыс.', category: 'Карьера', deadline: DateTime(2027, 6, 1));
      c.setGoalPlan(g, const GoalPlan(minutes: 6000));
      c.toggleCheckpoint(g, 0, true);
      final hist = c.goals.single.history.map((h) => h.text).toList();
      expect(hist, [
        'Цель поставлена',
        'Формулировка: «Доход 300 тыс.» → «Доход 500 тыс.»',
        'Срок: без срока → 01.06.2027',
        'План ресурсов: не задан → 100 ч',
        'Цель достигнута',
      ]);
      expect(c.goals.single.createdAt, DateTime(2026, 11, 18, 12));
      final ach = c.achievements.first;
      expect(ach.at, now); // точная дата, а не только месяц
      final entries = c.chronicle;
      expect(entries.where((e) => e.kind == ChronicleKind.goal), hasLength(5));
      expect(entries.firstWhere((e) => e.kind == ChronicleKind.achievement).monthOnly, isFalse);
      // круг через JSON
      final back = GlobalGoal.tryFromJson(jsonDecode(jsonEncode(c.goals.single.toJson())) as Map<String, dynamic>)!;
      expect(back.history.length, 5);
    });

    test('старые данные: без журнала и даты — читаются; достижение без точной даты — по месяцу', () {
      final g = GlobalGoal.tryFromJson({'id': 'g', 'title': 't', 'checkpoints': []})!;
      expect(g.createdAt, isNull);
      expect(g.history, isEmpty);
      final a = AchievementItem.tryFromJson({'id': 'a', 'title': 't', 'date': 'Октябрь 2026'})!;
      expect(a.at, isNull);
    });
  });

  testWidgets('«Материальное»: счёт добавляется, капитал — по счетам', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), saveDelay: Duration.zero);
    await c.load();
    await tester.pumpWidget(CatennaApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab_material')));
    await tester.pumpAndSettle();
    expect(find.text('Чистый капитал · указан вручную'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('add_account')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Вклад');
    await tester.enterText(find.byType(TextField).at(1), '1000000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    expect(find.text('Чистый капитал · по счетам'), findsOneWidget);
    expect(c.netWorth, 1000000);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
