import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catenna/app.dart';
import 'package:catenna/core/review.dart';
import 'package:catenna/data/app_data.dart';
import 'package:catenna/data/app_repository.dart';
import 'package:catenna/models/life_event.dart';
import 'package:catenna/models/life_process.dart';
import 'package:catenna/state/app_controller.dart';

void main() {
  late DateTime now;
  AppController make({InitialData? initial}) => AppController(
        MemoryAppRepository(),
        clock: () => now,
        saveDelay: const Duration(days: 1),
        initialData: initial ?? (n) => AppData.blank(now: n),
      );

  setUp(() => now = DateTime(2026, 11, 18, 20));

  group('обзор недели', () {
    test('заметка: вопросы-заголовки, пустые ответы не пишутся, разбор обратно', () {
      final note = composeReviewNote(['Сдал проект', '', 'Ложиться до 23:00\nбез телефона']);
      expect(note, 'Что получилось?\nСдал проект\n\nЧто меняю на следующей неделе?\nЛожиться до 23:00\nбез телефона');
      expect(parseReviewNote(note), ['Сдал проект', '', 'Ложиться до 23:00\nбез телефона']);
      expect(parseReviewNote('просто текст'), ['', '', '']);
    });

    test('когда предлагать: есть события и прошлого нет; через 7 дней после прошлого', () async {
      final c = make();
      await c.load();
      expect(c.weekReviewDue, isFalse); // обозревать нечего
      c.addEvent(title: 'Урок', dimensions: [LifeDimension.mind]);
      expect(c.weekReviewDue, isTrue);
      expect(c.saveWeekReview(['', '', '']), isNull); // пустой обзор не сохраняется
      expect(c.saveWeekReview(['Учился', '', '']), isNotNull);
      expect(c.weekReviewDue, isFalse);
      now = now.add(const Duration(days: 7));
      expect(c.weekReviewDue, isTrue);
    });

    test('решения по процессам записываются в журнал статусов; обзор не считается тратой ресурсов', () async {
      final c = make();
      await c.load();
      final run = c.addProcess(title: 'Бег', dimensions: [LifeDimension.body])!;
      final java = c.addProcess(title: 'Java', dimensions: [LifeDimension.mind])!;
      c.addEvent(title: 'Урок', dimensions: [LifeDimension.mind], processIds: [java], cost: const ResourceCost(minutes: 60));

      final f = c.weekReviewFacts;
      expect(f.breakdown.total.events, 1);
      expect(f.processes.map((l) => (l.process.title, l.week.events)), [('Бег', 0), ('Java', 1)]);

      now = now.add(const Duration(minutes: 5));
      final id = c.saveWeekReview(['', '', 'Бег на паузу до декабря'], processDecisions: {run: ProcessStatus.paused, java: ProcessStatus.active});
      final review = c.eventById(id!)!;
      expect(review.kind, LifeEventKind.review);
      expect(review.processIds, isEmpty);
      expect(c.processById(run)!.status, ProcessStatus.paused);
      expect(c.processById(run)!.statusLog.last.note, 'по итогам обзора недели');
      expect(c.processById(java)!.statusLog, hasLength(1)); // «оставить» = без записи

      // обзор затрагивает все измерения, но в ресурсах не участвует
      expect(c.resourceBreakdownFor(7).total.events, 1);
      expect(c.resourceBreakdownFor(7).byDimension['body']!.events, 0);
      expect(c.weekReviewFacts.previous!.id, id);
    });
  });

  group('в этот день', () {
    test('год назад: вес и рекорд 1RM — было → стало', () async {
      final c = make();
      await c.load();
      final yearAgo = DateTime(2025, 11, 18, 9);
      c.addWeight(86.4, at: yearAgo.add(const Duration(days: 2)));
      c.addWeight(81.2);
      now = yearAgo;
      c.logWorkout('chest', 80, 5); // 1RM ≈ 90
      now = DateTime(2026, 11, 18, 20);
      c.logWorkout('chest', 100, 5); // 1RM ≈ 112,5
      final m = c.memory!;
      expect(m.daysAgo, 365);
      expect(m.lines.map((l) => l.text), containsAll(['Вес 86,4 кг → сейчас 81,2 кг', '1RM, Грудные мышцы: 90 → сейчас 113 кг']));
    });

    test('нет данных за год — месяц назад; нет ничего — карточки нет', () async {
      final c = make();
      await c.load();
      expect(c.memory, isNull);
      c.addEvent(title: 'Первая пробежка', dimensions: [LifeDimension.body], at: DateTime(2026, 10, 19, 8));
      final m = c.memory!;
      expect(m.daysAgo, 30);
      expect(m.lines.single.text, 'Первая пробежка');
    });
  });

  testWidgets('обзор из плитки на «Сегодня» сохраняется и попадает в хронику', (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), saveDelay: Duration.zero);
    await c.load();
    c.addEvent(title: 'Урок Java', dimensions: [LifeDimension.mind]);
    await tester.pumpWidget(CatennaApp(controller: c));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('review_tile')));
    await tester.pumpAndSettle();
    expect(find.text('Обзор недели'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('review_q0')), 'Начал учить Java');
    await tester.tap(find.byKey(const ValueKey('review_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review_tile')), findsNothing); // до следующей недели не предлагается

    await tester.tap(find.byKey(const ValueKey('tab_chronicle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Обзор недели '), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
