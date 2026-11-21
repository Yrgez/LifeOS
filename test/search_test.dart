import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catenna/app.dart';
import 'package:catenna/core/search.dart';
import 'package:catenna/data/app_data.dart';
import 'package:catenna/data/app_repository.dart';
import 'package:catenna/models/life_event.dart';
import 'package:catenna/state/app_controller.dart';

void main() {
  final now = DateTime(2026, 11, 18, 12);
  AppController make() =>
      AppController(MemoryAppRepository(), clock: () => now, saveDelay: const Duration(days: 1), initialData: (n) => AppData.blank(now: n));

  group('логика', () {
    test('слова без учёта регистра и «ё»; число — сумма', () {
      expect(searchTokens('  Стоматолог  ЁЛКА '), ['стоматолог', 'елка']);
      expect(searchTokens('   '), isEmpty);
      expect(searchAmount('1 500'), 1500);
      expect(searchAmount('5'), isNull); // одна цифра — слишком общо для суммы
      expect(searchAmount('кофе 500'), isNull);
    });

    test('фрагмент вокруг совпадения', () {
      const note = 'Утром долго собирался, потом поехал к стоматологу на Ленина, вечером читал';
      final s = searchSnippet(note, ['стоматолог'], radius: 15);
      expect(s, startsWith('…'));
      expect(s, contains('стоматологу'));
      expect(s, endsWith('…'));
      expect(searchSnippet(note, ['зуб']), '');
    });
  });

  group('контроллер', () {
    test('события: последняя версия, отменённые с пометкой, несколько слов — все; новые сверху', () {
      final c = make();
      final first = c.addEvent(title: 'Стоматолог', dimensions: [LifeDimension.body], at: DateTime(2026, 3, 2, 10), note: 'пломба')!;
      c.reviseEvent(first, kind: LifeEventKind.action, title: 'Стоматолог: пломба', dimensions: [LifeDimension.body], at: DateTime(2026, 3, 2, 10), note: 'пломба слева');
      final cancelled = c.addEvent(title: 'Стоматолог (перенос)', dimensions: [LifeDimension.body], at: DateTime(2026, 10, 1, 9))!;
      c.voidEvent(cancelled);
      final hits = c.search('стоматолог');
      expect(hits.map((h) => h.title), ['Стоматолог (перенос)', 'Стоматолог: пломба']); // старой версии нет
      expect(hits.first.voided, isTrue);
      expect(c.search('стоматолог слева').single.title, 'Стоматолог: пломба');
      expect(c.search('стоматолог справа'), isEmpty);
    });

    test('операции по заметке, категории и сумме; отметки по меткам; процессы, счета', () {
      final c = make();
      c.addTransaction(categoryId: 'health', amount: 4500, note: 'Клиника «Улыбка»');
      c.setCheckIn(now, rating: 3, tags: ['зубы болят'], note: 'после клиники');
      c.addProcess(title: 'Лечение зубов', dimensions: [LifeDimension.body], description: 'курс у стоматолога');
      c.addBill(title: 'Стоматология рассрочка', amount: 3000, firstDue: DateTime(2026, 11, 25));
      expect(c.search('улыбка').single.kind, SearchKind.transaction);
      expect(c.search('здоровье').single.kind, SearchKind.transaction); // по названию категории
      expect(c.search('4 500').single.kind, SearchKind.transaction);
      expect(c.search('зуб').map((h) => h.kind).toSet(), {SearchKind.checkIn, SearchKind.process}); // «зубы», «зубов»
      expect(c.search('стоматолог').map((h) => h.kind).toSet(), {SearchKind.process, SearchKind.bill});
      expect(c.search('стоматолог').last.kind, SearchKind.bill); // без даты — в конце
    });
  });

  testWidgets('поиск с «Сегодня»: результаты, фильтр, открытие записи (360 px)', (tester) async {
    tester.view.physicalSize = const Size(360, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), clock: () => now, saveDelay: Duration.zero);
    await c.load();
    c.addEvent(title: 'Стоматолог', dimensions: [LifeDimension.body], note: 'пломба');
    c.addTransaction(categoryId: 'health', amount: 4500, note: 'стоматолог');
    await tester.pumpWidget(CatennaApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open_search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('search_field')), 'стоматолог');
    await tester.pumpAndSettle();
    expect(find.text('Найдено: 2'), findsOneWidget);
    final ev = c.events.single;
    await tester.tap(find.byKey(const ValueKey('search_kind_tx')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('hit_event_${ev.id}')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('search_kind_event')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('hit_event_${ev.id}')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget); // открылось событие для правки
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
