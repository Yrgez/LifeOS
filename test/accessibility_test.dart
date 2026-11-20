import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app.dart';
import 'package:life_os/core/chart_text.dart';
import 'package:life_os/core/theme.dart';
import 'package:life_os/core/utils.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/state/app_controller.dart';

/// Доступность: программа чтения экрана (TalkBack) и области нажатия.
/// Каждое нажимаемое место подписано, не меньше 48 × 48 px (рекомендация Android),
/// нарисованные графики и фигура описаны текстом, системные тексты — по-русски.
void main() {
  Future<AppController> boot(WidgetTester tester, {DateTime Function()? clock}) async {
    tester.view.physicalSize = const Size(360, 3000); // ширина телефона; высокая — все блоки без прокрутки
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = AppController(MemoryAppRepository(), saveDelay: Duration.zero, clock: clock);
    await c.load();
    await tester.pumpWidget(LifeOSApp(controller: c));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> shutdown(WidgetTester tester, AppController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  Future<void> go(WidgetTester tester, List<Finder> path) async {
    for (final f in path) {
      await tester.tap(f.first);
      await tester.pumpAndSettle();
    }
  }

  ValueKey<String> k(String s) => ValueKey(s);
  final screens = <String, List<Finder>>{
    'Сегодня': [find.byKey(k('tab_today'))],
    'События': [find.byKey(k('tab_today')), find.byKey(k('open_events'))],
    'Задачи': [find.byKey(k('tab_today')), find.byKey(k('open_tasks'))],
    'Настройки': [find.byKey(k('tab_today')), find.byTooltip('Настройки')],
    'Тело': [find.byKey(k('tab_body'))],
    'Разум': [find.byKey(k('tab_mind'))],
    'Граф': [find.byKey(k('tab_mind')), find.byKey(k('open_graph'))],
    'Процессы': [find.byKey(k('tab_mind')), find.text('Процессы')],
    'Эксперименты': [find.byKey(k('tab_mind')), find.byKey(k('open_experiments'))],
    'Материальное': [find.byKey(k('tab_material'))],
    'Финансы': [find.byKey(k('tab_material')), find.byKey(k('open_finance'))],
    'Хроника': [find.byKey(k('tab_chronicle'))],
  };

  for (final e in screens.entries) {
    testWidgets('${e.key}: всё нажимаемое подписано и не меньше 48 px', (tester) async {
      final h = tester.ensureSemantics();
      final c = await boot(tester);
      await go(tester, e.value);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await shutdown(tester, c);
      h.dispose();
    });
  }

  // вечером на «Сегодня» — вопрос об оценке дня (кнопки 1–5); тест не зависит от того, когда его запускают
  testWidgets('Сегодня вечером: оценка дня подписана и не меньше 48 px', (tester) async {
    final h = tester.ensureSemantics();
    final evening = DateTime.now().copyWith(hour: 21, minute: 30);
    final c = await boot(tester, clock: () => evening);
    expect(c.checkInPromptDay, isNotNull);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    expect(find.semantics.byLabel('Оценка 3 из 5'), findsOne);
    await shutdown(tester, c);
    h.dispose();
  });

  // крупный системный шрифт (Android допускает до 200 %) на узком экране: ничего не вылезает за край
  for (final e in screens.entries) {
    testWidgets('${e.key}: шрифт 200 % на 360 px — без переполнения', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await boot(tester);
      await go(tester, e.value);
      expect(tester.takeException(), isNull);
      await shutdown(tester, c);
    });
  }

  test('цвета текста контрастны (WCAG AA, 4.5:1) на всех поверхностях', () {
    double ratio(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
    }

    const texts = {
      'text': AppColors.text,
      'muted': AppColors.muted,
      'green': AppColors.green,
      'red': AppColors.red,
      'body': AppColors.body,
      'mind': AppColors.mind,
      'material': AppColors.material,
    };
    const surfaces = {'background': AppColors.background, 'card': AppColors.card, 'raised': AppColors.raised, 'field': AppColors.field};
    for (final t in texts.entries) {
      for (final s in surfaces.entries) {
        expect(ratio(t.value, s.value), greaterThanOrEqualTo(4.5), reason: '${t.key} на ${s.key}');
      }
    }
  });

  test('описание ряда: короткий — все значения, длинный — края и размах, без выводов', () {
    expect(describeSeries([]), 'нет данных');
    expect(describeSeries([5200, 6100.0, 80.5], labels: ['пн', 'вт', 'ср']), 'пн ${fmtMoney(5200)}, вт ${fmtMoney(6100)}, ср 80,5');
    expect(describeSeries([1, 2, 3]), '1, 2, 3');
    expect(describeSeries([for (var i = 0; i < 30; i++) 80 + (i % 5)], maxListed: 12), 'точек: 30; первое 80, последнее 84, наименьшее 80, наибольшее 84');
    expect(speakNum(-1500), '−${fmtMoney(1500)}');
  });

  testWidgets('системные тексты — по-русски (их читает TalkBack)', (tester) async {
    final c = await boot(tester);
    await go(tester, screens['События']!);
    expect(find.byTooltip('Назад'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    await shutdown(tester, c);
  });

  SemanticsNode node(Pattern label) => find.semantics.byLabel(label).evaluate().single;
  bool selected(Pattern label) => node(label).flagsCollection.isSelected == Tristate.isTrue;

  testWidgets('фигура тела: каждая мышца — подписанная кнопка, выбор с программой чтения экрана', (tester) async {
    final h = tester.ensureSemantics();
    final c = await boot(tester);
    await go(tester, screens['Тело']!);
    final chest = RegExp(r'^Грудные мышцы\. .*\(оценка\)$');
    expect(selected(chest), isTrue); // выбрана по умолчанию
    expect(node(chest).getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    final delts = RegExp(r'^Дельтовидные\. ');
    tester.semantics.tap(find.semantics.byLabel(delts));
    await tester.pumpAndSettle();
    expect(find.text('Дельтовидные'), findsWidgets); // карточка выбранной мышцы
    expect(selected(delts), isTrue);
    expect(selected(chest), isFalse);

    // ракурс — переключатель с состоянием «выбрано»
    expect(selected('Сзади'), isFalse);
    tester.semantics.tap(find.semantics.byLabel('Сзади'));
    await tester.pumpAndSettle();
    expect(selected('Сзади'), isTrue);
    expect(find.semantics.byLabel(RegExp(r'^Широчайшие спины\. ')), findsOne);
    await shutdown(tester, c);
    h.dispose();
  });

  testWidgets('графики описаны данными: сравнение метрик, доход и расход', (tester) async {
    final h = tester.ensureSemantics();
    final c = await boot(tester);
    await go(tester, screens['Тело']!);
    // «Сравнение метрик»: оба ряда — по дням недели, с подписями
    final label = node(RegExp(r'^Сравнение\. Шаги \(7 дн\): ')).label;
    expect(label, contains('${c.weekLabels.last} ${speakNum(c.stepsWeekHistory.last)}'));
    expect(label, contains('Калории (7 дн): '));

    await go(tester, screens['Финансы']!);
    expect(find.semantics.byLabel(RegExp(r'^Доход и расход за 6 месяцев: .*доход .*расход ')), findsOne);
    await shutdown(tester, c);
    h.dispose();
  });

  testWidgets('граф: узлы — подписанные кнопки, выбор узла без зрения', (tester) async {
    final h = tester.ensureSemantics();
    final c = await boot(tester);
    await go(tester, screens['Граф']!);
    final n = c.graphNodes.first;
    final label = RegExp('^${RegExp.escape(n.label)}\\. (Без связей|Связей: \\d+)\$');
    expect(selected(label), isFalse);
    tester.semantics.tap(find.semantics.byLabel(label));
    await tester.pumpAndSettle();
    expect(selected(label), isTrue);
    await shutdown(tester, c);
    h.dispose();
  });
}
