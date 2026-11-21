import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:catenna/app.dart';
import 'package:catenna/data/app_repository.dart';
import 'package:catenna/models/experiment.dart';
import 'package:catenna/models/life_event.dart';
import 'package:catenna/security/app_lock.dart';
import 'package:catenna/security/biometric_authenticator.dart';
import 'package:catenna/security/security_service.dart';
import 'package:catenna/security/security_settings.dart';
import 'package:catenna/state/app_controller.dart';
import 'package:catenna/ui/screens/bills_screen.dart';
import 'package:catenna/ui/screens/categories_screen.dart';
import 'package:catenna/ui/screens/checkin_screen.dart';
import 'package:catenna/ui/screens/chronicle_screen.dart';
import 'package:catenna/ui/screens/events_screen.dart';
import 'package:catenna/ui/screens/experiments_screen.dart';
import 'package:catenna/ui/screens/finance_screen.dart';
import 'package:catenna/ui/screens/graph_screen.dart';
import 'package:catenna/ui/screens/journal_screen.dart';
import 'package:catenna/ui/screens/onboarding_screen.dart';
import 'package:catenna/ui/screens/processes_screen.dart';
import 'package:catenna/ui/screens/resources_screen.dart';
import 'package:catenna/ui/screens/review_screen.dart';
import 'package:catenna/ui/screens/search_screen.dart';
import 'package:catenna/ui/screens/settings_screen.dart';
import 'package:catenna/ui/screens/statement_import_screen.dart';
import 'package:catenna/ui/screens/tasks_screen.dart';
import 'package:catenna/ui/widgets/event_dialog.dart';
import 'package:catenna/ui/widgets/goals_ui.dart';
import 'package:catenna/ui/widgets/lock_layer.dart';
import 'package:catenna/ui/widgets/log_set_dialog.dart';
import 'package:catenna/ui/widgets/process_ui.dart';
import 'package:catenna/ui/widgets/task_ui.dart';

/// Системный шрифт от обычного до крупного (Android допускает до 200 %) на телефоне 360 × 780: каждый экран
/// и каждый диалог открывается и прокручивается до конца без переполнений и без слов, разорванных переносом
/// посередине («Груд|ные»). 130 % — порог, с которого плитки и кнопки встают друг под другом (`AdaptivePair`).
/// Ошибка называет место в коде или разорванное слово.
void main() {
  // шаги размера шрифта в настройках Android
  for (final scale in [1.0, 1.15, 1.3, 1.5, 1.8, 2.0]) {
    group('шрифт ${(scale * 100).round()} %', () => _suite(scale));
  }
}

void _suite(double scale) {
  late List<String> problems;

  // настоящий шрифт приложения: с тестовым (каждая буква — квадрат) переносы были бы не те, что на телефоне
  Future<void> loadInter(WidgetTester tester) => tester.runAsync(() async {
        final inter = FontLoader('Inter');
        for (final f in ['Inter-Regular.ttf', 'Inter-Medium.ttf']) {
          inter.addFont(Future.value(File('assets/fonts/$f').readAsBytesSync().buffer.asByteData()));
        }
        await inter.load();
      });

  /// Слова, разорванные переносом строки посередине («Груд|ные»): буква до и после переноса.
  void checkWordBreaks(WidgetTester tester, String where) {
    bool letter(int c) => RegExp(r'[A-Za-zА-Яа-яЁё0-9]').hasMatch(String.fromCharCode(c));
    for (final r in tester.allRenderObjects.whereType<RenderParagraph>()) {
      if (r.maxLines == 1 || !r.hasSize) continue;
      final text = r.text.toPlainText(includeSemanticsLabels: false, includePlaceholders: false);
      for (var i = 1; i < text.length; i++) {
        if (!letter(text.codeUnitAt(i - 1)) || !letter(text.codeUnitAt(i))) continue;
        final up = r.getOffsetForCaret(TextPosition(offset: i, affinity: TextAffinity.upstream), Rect.zero);
        final down = r.getOffsetForCaret(TextPosition(offset: i), Rect.zero);
        if (down.dy > up.dy + 1) {
          final from = text.lastIndexOf(RegExp(r'[^A-Za-zА-Яа-яЁё0-9]'), i - 1) + 1;
          var to = text.indexOf(RegExp(r'[^A-Za-zА-Яа-яЁё0-9]'), i);
          if (to < 0) to = text.length;
          final p = 'слово разорвано: «${text.substring(from, i)}|${text.substring(i, to)}» в «${text.length > 50 ? '${text.substring(0, 50)}…' : text}»';
          if (!problems.contains(p)) problems.add(p);
          break;
        }
      }
    }
  }

  void Function(FlutterErrorDetails)? savedOnError;

  Future<AppController> boot(WidgetTester tester, {DateTime Function()? clock, bool checkIn = true}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    problems = [];
    savedOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final where = RegExp(r'lib/ui/[^ :]+\.dart:\d+').allMatches(d.toString()).map((m) => m.group(0)).toSet();
      problems.add('${d.exceptionAsString().split('\n').first} ${where.join(', ')}');
    };

    await loadInter(tester);
    final c = AppController(MemoryAppRepository(), saveDelay: Duration.zero, clock: clock);
    await c.load();
    // данные, при которых экраны показывают свои блоки, а не пустые состояния
    final goal = c.goals.first.id;
    final p = c.addProcess(title: 'Изучение английского языка', dimensions: [LifeDimension.mind], goalIds: [goal], defaultMinutes: 45)!;
    c.addEvent(
      title: 'Занятие с преподавателем по разговорной практике',
      dimensions: [LifeDimension.mind, LifeDimension.material],
      processIds: [p],
      goalIds: [goal],
      note: 'Длинная заметка о событии, чтобы проверить перенос строк при крупном шрифте',
      cost: const ResourceCost(minutes: 90, money: 2500, energy: 3),
    );
    c.addTask(title: 'Подготовить презентацию для собеседования', dimensions: [LifeDimension.mind], processId: p, minutes: 60);
    c.addTask(title: 'Без даты: разобрать документы', dimensions: [LifeDimension.material], day: null);
    c.addBill(title: 'Интернет и мобильная связь', amount: 650, firstDue: c.now);
    c.addExperiment(title: 'Ранний отход ко сну', metric: ExperimentMetric.steps, startedAt: c.now.subtract(const Duration(days: 3)), days: 14);
    if (checkIn) c.setCheckIn(c.now, rating: 4, tags: ['спорт'], note: 'Хороший день');
    c.addTransaction(categoryId: 'food', amount: 1200, note: 'Продукты на неделю');
    await tester.pumpWidget(CatennaApp(controller: c, security: SecurityService.disabled()));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> shutdown(WidgetTester tester, AppController c) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  }

  /// Прокрутка всех вертикальных списков до конца: ленивые элементы строятся только на экране.
  Future<void> scrollThrough(WidgetTester tester) async {
    checkWordBreaks(tester, 'начало');
    final lists = find.byWidgetPredicate((w) => w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.vertical);
    for (var i = 0; i < lists.evaluate().length; i++) {
      for (var step = 0; step < 40; step++) {
        final state = tester.state<ScrollableState>(lists.at(i));
        final pos = state.position;
        if (!pos.hasContentDimensions || pos.pixels >= pos.maxScrollExtent) break;
        pos.jumpTo((pos.pixels + 400).clamp(0, pos.maxScrollExtent));
        await tester.pumpAndSettle();
        checkWordBreaks(tester, 'прокрутка');
      }
    }
  }

  /// Обработчик ошибок возвращается до проверки: иначе тестовая среда не примет провал.
  void expectClean(String what) {
    FlutterError.onError = savedOnError;
    expect(problems, isEmpty, reason: '$what при шрифте ${(scale * 100).round()} %');
  }

  final screens = <String, Widget Function(AppController)>{
    'Счета': (c) => BillsScreen(controller: c),
    'Категории': (c) => CategoriesScreen(controller: c),
    'Отметка дня': (c) => CheckInScreen(controller: c, day: c.now),
    'Хроника': (c) => ChronicleScreen(controller: c),
    'События': (c) => EventsScreen(controller: c),
    'События процесса': (c) => EventsScreen(controller: c, processId: c.processes.first.id),
    'События цели': (c) => EventsScreen(controller: c, goalId: c.goals.first.id),
    'Эксперименты': (c) => ExperimentsScreen(controller: c),
    'Новый эксперимент': (c) => NewExperimentScreen(controller: c),
    'Эксперимент': (c) => ExperimentScreen(controller: c, id: c.experiments.first.id),
    'Финансы': (c) => FinanceScreen(controller: c),
    'Граф': (c) => GraphScreen(controller: c),
    'Журнал тренировок': (c) => JournalScreen(controller: c),
    'Знакомство': (c) => OnboardingScreen(controller: c),
    'Процессы': (c) => ProcessesScreen(controller: c),
    'Ресурсы': (c) => ResourcesScreen(controller: c),
    'Обзор недели': (c) => ReviewScreen(controller: c),
    'Поиск': (c) => SearchScreen(controller: c),
    'Настройки': (c) => SettingsScreen(controller: c, security: SecurityService.disabled()),
    'Импорт выписки': (c) => StatementImportScreen(controller: c),
    'Задачи': (c) => TasksScreen(controller: c),
  };

  for (final tab in ['tab_today', 'tab_body', 'tab_mind', 'tab_material', 'tab_chronicle']) {
    testWidgets('вкладка $tab', (tester) async {
      final c = await boot(tester);
      await tester.tap(find.byKey(ValueKey(tab)));
      await tester.pumpAndSettle();
      await scrollThrough(tester);
      expectClean(tab);
      await shutdown(tester, c);
    });
  }

  for (final e in screens.entries) {
    testWidgets('экран «${e.key}»', (tester) async {
      final c = await boot(tester);
      tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute(builder: (_) => e.value(c)));
      await tester.pumpAndSettle();
      if (e.key == 'Поиск') {
        await tester.enterText(find.byKey(const ValueKey('search_field')), 'а');
        await tester.pumpAndSettle();
      }
      await scrollThrough(tester);
      expectClean(e.key);
      await shutdown(tester, c);
    });
  }

  final dialogs = <String, void Function(BuildContext, AppController)>{
    'событие': (ctx, c) => showEventDialog(ctx, now: c.now, goals: c.goals, processes: c.processes),
    'правка события': (ctx, c) => showEventDialog(ctx, now: c.now, goals: c.goals, processes: c.processes, initial: c.allEvents.first),
    'процесс': (ctx, c) => showProcessDialog(ctx, now: c.now, goals: c.goals),
    'задача': (ctx, c) => showTaskSheet(ctx, c),
    'подход': (ctx, c) => showLogSetDialog(ctx, c, muscleId: 'chest'),
    'новая цель': (ctx, c) => showNewGoalDialog(ctx, c),
    'правка цели': (ctx, c) => showEditGoalDialog(ctx, c, c.goals.first),
    'план ресурсов цели': (ctx, c) => showGoalPlanDialog(ctx, c, c.goals.first),
    'чекпоинт': (ctx, c) => showAddCheckpointDialog(ctx, c, c.goals.first),
    'операция': (ctx, c) => showTransactionDialog(ctx, c),
    'лимиты': (ctx, c) => showBudgetDialog(ctx, c),
    'регулярный платёж': (ctx, c) => showRecurringDialog(ctx, c),
    'регулярные платежи': (ctx, c) => showRecurringSheet(ctx, c),
  };

  for (final e in dialogs.entries) {
    testWidgets('диалог «${e.key}»', (tester) async {
      final c = await boot(tester);
      e.value(tester.element(find.byType(Scaffold).first), c);
      await tester.pumpAndSettle();
      await scrollThrough(tester);
      expectClean(e.key);
      await shutdown(tester, c);
    });
  }

  testWidgets('«Сегодня» вечером: вопрос об оценке дня', (tester) async {
    final evening = DateTime.now().copyWith(hour: 21, minute: 30);
    final c = await boot(tester, clock: () => evening, checkIn: false);
    final asked = c.checkInPromptDay != null;
    await scrollThrough(tester);
    expectClean('вечерняя отметка');
    expect(asked, isTrue);
    await shutdown(tester, c);
  });

  testWidgets('граф: панель выбранного узла', (tester) async {
    final h = tester.ensureSemantics();
    final c = await boot(tester);
    tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute(builder: (_) => GraphScreen(controller: c)));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel(RegExp('^${RegExp.escape(c.graphNodes.first.label)}\\. ')));
    await tester.pumpAndSettle();
    await scrollThrough(tester);
    expectClean('панель узла');
    await shutdown(tester, c);
    h.dispose();
  });

  testWidgets('меню задачи и подтверждение', (tester) async {
    final c = await boot(tester);
    tester.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute(builder: (_) => TasksScreen(controller: c)));
    await tester.pumpAndSettle();
    final menu = find.byKey(ValueKey('task_menu_${c.tasks.first.id}'));
    // строку — к верху экрана: внизу её закрывает кнопка «+»
    await tester.runAsync(() => Scrollable.ensureVisible(tester.element(menu)));
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить задачу').last);
    await tester.pumpAndSettle();
    final dialogs = find.byType(AlertDialog).evaluate().length;
    expectClean('меню и подтверждение');
    expect(dialogs, 1);
    await shutdown(tester, c);
  });

  testWidgets('экран блокировки', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final lock = AppLock(authenticator: FakeAuthenticator(nextOutcome: AuthOutcome.cancelled), settings: SecuritySettings());
    await tester.pumpWidget(MaterialApp(home: LockScreen(lock: lock)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    lock.dispose();
  });
}
