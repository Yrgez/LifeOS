import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catenna/app.dart';
import 'package:catenna/core/bills.dart';
import 'package:catenna/data/app_data.dart';
import 'package:catenna/data/app_repository.dart';
import 'package:catenna/data/sqlite_app_repository.dart';
import 'package:catenna/models/bill.dart';
import 'package:catenna/state/app_controller.dart';
import 'package:catenna/ui/screens/bills_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  late DateTime now;
  AppController make([AppRepository? repo]) =>
      AppController(repo ?? MemoryAppRepository(), clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));
  setUp(() => now = DateTime(2026, 11, 18, 12));

  Bill bill({String first = '2026-01-31', String repeat = BillRepeat.month}) =>
      Bill(id: 'b', title: 'Интернет', amount: 650, firstDue: first, repeat: repeat, createdAt: now);

  test('сроки: конец месяца, 29 февраля, разовый, архив', () {
    final m = bill();
    expect([m.dueAt(0), m.dueAt(1), m.dueAt(2), m.dueAt(12)], [DateTime(2026, 1, 31), DateTime(2026, 2, 28), DateTime(2026, 3, 31), DateTime(2027, 1, 31)]);
    expect(bill(first: '2028-02-29', repeat: BillRepeat.year).dueAt(1), DateTime(2029, 2, 28));
    final once = bill(first: '2026-12-01', repeat: BillRepeat.none);
    expect(nextDue(once), DateTime(2026, 12, 1));
    once.payments.add(BillPayment(due: '2026-12-01', paidAt: now));
    expect(nextDue(once), isNull);
    final paid = bill()..payments.add(BillPayment(due: '2026-01-31', paidAt: now));
    expect(nextDue(paid), DateTime(2026, 2, 28));
    expect(nextDue(bill()..archivedAt = now), isNull);
    expect([dueLabel(DateTime(2026, 11, 18), now), dueLabel(DateTime(2026, 11, 19), now), dueLabel(DateTime(2026, 11, 25), now), dueLabel(DateTime(2026, 11, 16), now)],
        ['сегодня', 'завтра', 'через 7 дн.', 'просрочен на 2 дн.']);
    expect(jsonEncode(Bill.tryFromJson(paid.toJson())!.toJson()), jsonEncode(paid.toJson()));
    expect(Bill.tryFromJson({...paid.toJson(), 'rep': 'week'}), isNull);
    expect(Bill.tryFromJson({...paid.toJson(), 'a': 0}), isNull);
  });

  test('оплата: история, операция расхода, капитал, отмена', () {
    final c = make();
    expect(c.addBill(title: 'Зарплата?', categoryId: 'salary', firstDue: now), isNull); // категория дохода
    final id = c.addBill(title: 'Интернет', amount: 650, categoryId: 'subs', firstDue: DateTime(2026, 11, 16))!;
    expect(c.upcomingBillsWithin(1).single.$2, DateTime(2026, 11, 16)); // просрочен — в списке
    final nw = c.netWorth;
    expect(c.payBill(id), DateTime(2026, 11, 16));
    final tx = c.transactions.single;
    expect((tx.amount, tx.categoryId, tx.note, tx.isIncome), (650, 'subs', 'Счёт: Интернет', false));
    expect(c.netWorth, nw - 650);
    expect(nextDue(c.billById(id)!), DateTime(2026, 12, 16));
    expect(c.upcomingBillsWithin(14), isEmpty);
    // после оплаты график не меняется, описание — можно
    expect(c.updateBill(id, title: 'Интернет', categoryId: 'subs', firstDue: DateTime(2026, 12, 1)), isFalse);
    expect(c.updateBill(id, title: 'Интернет дом', amount: 700, categoryId: 'subs'), isTrue);
    expect(c.undoLastBillPayment(id), isTrue);
    expect(c.transactions, isEmpty);
    expect(c.netWorth, nw);
    expect(nextDue(c.billById(id)!), DateTime(2026, 11, 16));
  });

  test('оплата без суммы — без операции; архив; удаление оставляет операции', () {
    final c = make();
    final id = c.addBill(title: 'Коммуналка', firstDue: DateTime(2026, 11, 20))!;
    c.payBill(id, createTransaction: false);
    expect(c.transactions, isEmpty);
    expect(c.billById(id)!.payments.single.txId, isNull);
    final id2 = c.addBill(title: 'Страховка', amount: 9000, firstDue: now, repeat: BillRepeat.year)!;
    c.payBill(id2);
    expect(c.archiveBill(id), isTrue);
    expect(c.bills.last.id, id); // архив — в конце
    expect(c.removeBill(id2), isTrue);
    expect(c.transactions.single.amount, 9000);
  });

  test('хранится в SQLite; битый счёт в строгом импорте отвергается', () async {
    final db = await SqliteAppRepository.openDb(databaseFactoryFfi, inMemoryDatabasePath);
    addTearDown(db.close);
    final c = make(SqliteAppRepository(opener: () async => db));
    await c.load();
    final id = c.addBill(title: 'Интернет', amount: 650, firstDue: DateTime(2026, 11, 16))!;
    c.payBill(id);
    await c.flush();
    final c2 = make(SqliteAppRepository(opener: () async => db));
    await c2.load();
    expect(jsonEncode(c2.billById(id)!.toJson()), jsonEncode(c.billById(id)!.toJson()));
    final j = jsonDecode(c.exportBackup()) as Map<String, dynamic>;
    expect(j['schemaVersion'], greaterThanOrEqualTo(20));
    expect(() => AppData.fromJson({...j, 'bills': [{'id': 'x'}]}, strict: true), throwsFormatException);
  });

  testWidgets('счета: «Сегодня» напоминает о сроке, «Материальное» показывает ближайшие, оплата в одно нажатие (360 px)', (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero);
    await c.load();
    final id = c.addBill(title: 'Интернет', amount: 650, firstDue: DateTime(2026, 11, 19))!;
    c.addBill(title: 'Страховка', amount: 9000, firstDue: DateTime(2026, 11, 28), repeat: BillRepeat.year);
    await tester.pumpWidget(CatennaApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('hub_bill_$id')), findsOneWidget); // завтра
    await tester.tap(find.byKey(const ValueKey('tab_material')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('bills_tile')));
    expect(find.text('Страховка'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bills_tile')));
    await tester.pumpAndSettle();
    expect(find.byType(BillsScreen), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('pay_$id')));
    await tester.pumpAndSettle();
    expect(c.billById(id)!.payments.length, 1);
    expect(find.textContaining('оплачен'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    c.dispose();
  });
}
