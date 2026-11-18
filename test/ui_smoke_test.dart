import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/models/life_event.dart';
import 'package:life_os/models/models.dart';
import 'package:life_os/state/app_controller.dart';

/// Дымовые тесты интерфейса: после разбиения на экраны проверяют, что каждая вкладка строится,
/// а ключевые сценарии (запись подхода, добавление операции) доходят до контроллера.
void main() {
  Future<AppController> boot(WidgetTester tester, {MemoryAppRepository? repo, bool blank = false}) async {
    // высокая поверхность: все блоки на экране без прокрутки
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final c = AppController(
      repo ?? MemoryAppRepository(),
      saveDelay: Duration.zero,
      initialData: blank ? (n) => AppData.blank(now: n) : null,
    );
    await c.load();
    await tester.pumpWidget(LifeOSApp(controller: c));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> shutdown(WidgetTester tester, AppController c) async {
    await tester.pumpWidget(const SizedBox()); // снимает дерево: отменяются таймеры оболочки
    c.dispose();
  }

  testWidgets('все вкладки строятся', (tester) async {
    final c = await boot(tester);
    expect(find.byKey(const ValueKey('today_date')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab_body')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('weight_tile')), findsOneWidget);
    expect(find.text('Сравнение метрик'), findsOneWidget); // переехало с HUB

    await tester.tap(find.byKey(const ValueKey('tab_mind')));
    await tester.pumpAndSettle();
    expect(find.text('Цели'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open_graph')));
    await tester.pumpAndSettle();
    expect(find.text('SECOND BRAIN GRAPH'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tab_material')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('net_worth')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab_chronicle')));
    await tester.pumpAndSettle();
    expect(find.text('Хроника'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tab_today')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('today_date')), findsOneWidget);

    await shutdown(tester, c);
  });

  testWidgets('события жизни: открыть журнал, зафиксировать событие, отменить', (tester) async {
    final c = await boot(tester);
    await tester.tap(find.byKey(const ValueKey('open_events')));
    await tester.pumpAndSettle();
    expect(find.text('События').last, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add_event')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('event_title')), 'Первое занятие Java');
    await tester.tap(find.byKey(const ValueKey('dim_mind')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('event_save')));
    await tester.pumpAndSettle();
    expect(c.events.single.title, 'Первое занятие Java');
    expect(find.text('Первое занятие Java'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(c.events, isEmpty);
    expect(c.allEvents, hasLength(1)); // в истории осталось

    await shutdown(tester, c);
  });

  testWidgets('процессы: создать, записать событие в процесс, сменить статус', (tester) async {
    final c = await boot(tester);
    await tester.tap(find.byKey(const ValueKey('open_processes')));
    await tester.pumpAndSettle();
    expect(find.text('Процессы').last, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add_process')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('process_title')), 'Изучение Java');
    await tester.tap(find.byKey(const ValueKey('pdim_mind')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('process_save')));
    await tester.pumpAndSettle();
    final p = c.processes.single;

    await tester.tap(find.text('Изучение Java'));
    await tester.pumpAndSettle();
    expect(find.text('ЖУРНАЛ СТАТУСОВ'), findsOneWidget);

    // событие с экрана процесса сразу относится к нему и к его измерениям
    await tester.tap(find.byKey(const ValueKey('add_event')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('event_title')), 'Урок 1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('event_save')));
    await tester.pumpAndSettle();
    expect(c.eventsForProcess(p.id).single.title, 'Урок 1');
    expect(c.events.single.dimensions, ['mind']);

    await tester.tap(find.byKey(const ValueKey('process_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Статус: На паузе'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(c.processById(p.id)!.status, 'paused');

    await shutdown(tester, c);
  });

  testWidgets('ресурсы: карточка на HUB открывает экран, периоды переключаются', (tester) async {
    final c = await boot(tester);
    final p = c.addProcess(title: 'Изучение Java', dimensions: ['mind'])!;
    c.addEvent(title: 'Урок', dimensions: ['mind', 'material'], processIds: [p], cost: const ResourceCost(minutes: 90, money: 1500, energy: 3));
    c.addEvent(title: 'Пробежка', dimensions: ['body'], cost: const ResourceCost(minutes: 30));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('open_resources')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open_resources')));
    await tester.pumpAndSettle();
    expect(find.text('ПО ИЗМЕРЕНИЯМ'), findsOneWidget);
    expect(find.text('Изучение Java'), findsOneWidget);
    expect(find.text('Вне процессов'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('period_365')));
    await tester.pumpAndSettle();
    expect(find.text('ПО ПРОЦЕССАМ'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await shutdown(tester, c);
  });

  testWidgets('хроника: вкладка показывает ленту, тихие дни включаются', (tester) async {
    final c = await boot(tester);
    c.addEvent(title: 'Первая тренировка', dimensions: ['body']);
    c.addProcess(title: 'Бег', dimensions: ['body']);
    await tester.tap(find.byKey(const ValueKey('tab_chronicle')));
    await tester.pumpAndSettle();
    expect(find.text('Первая тренировка'), findsOneWidget);
    expect(find.text('Начат процесс «Бег»'), findsOneWidget);
    expect(find.text('Подушка безопасности 1 000 000 ₽'), findsOneWidget); // достижение из примеров, по месяцу

    await tester.tap(find.byKey(const ValueKey('quiet_days')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await shutdown(tester, c);
  });

  testWidgets('цели: план ресурсов и факт из событий, переход к событиям цели', (tester) async {
    final c = await boot(tester);
    c.addGoal('Стать Java-разработчиком', 'Карьера', ['Основы']);
    final g = c.goals.last.id;
    c.setGoalPlan(g, const GoalPlan(minutes: 6000));
    c.addEvent(title: 'Урок Java', dimensions: ['mind'], goalIds: [g], cost: const ResourceCost(minutes: 90));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab_mind')));
    await tester.pumpAndSettle();
    expect(find.text('Время: 1 ч 30 мин из 100 ч по плану'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('goal_events_$g')));
    await tester.pumpAndSettle();
    expect(find.text('Урок Java'), findsOneWidget);
    expect(find.text('Стать Java-разработчиком'), findsWidgets); // заголовок экрана

    await shutdown(tester, c);
  });

  testWidgets('без ложной точности: восстановление счётом, граф со связанным узлом удалённого процесса', (tester) async {
    final c = await boot(tester);
    expect(find.text('Восстановлено'), findsOneWidget);
    expect(find.textContaining('Готовность тела'), findsNothing);

    final p = c.addProcess(title: 'Изучение Java', dimensions: ['mind'])!;
    c.addNodeFor(NodeRef(NodeRef.process, p));
    c.removeProcess(p);
    await tester.tap(find.byKey(const ValueKey('tab_mind')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open_graph')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab_body')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Корреляция Пирсона'), findsNothing);

    await shutdown(tester, c);
  });

  testWidgets('узкий экран телефона (360 px): все вкладки без переполнения', (tester) async {
    final c = await boot(tester);
    c.addProcess(title: 'Изучение Java', dimensions: ['mind']);
    tester.view.physicalSize = const Size(360, 2600);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final t in ['tab_body', 'tab_mind', 'tab_material', 'tab_chronicle', 'tab_today']) {
      await tester.tap(find.byKey(ValueKey(t)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'вкладка «$t»');
    }
    await shutdown(tester, c);
  });

  testWidgets('предупреждение о недоступном хранилище', (tester) async {
    final c = await boot(tester, repo: MemoryAppRepository(loadError: StateError('диск')));
    expect(find.textContaining('Хранилище недоступно'), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('запись подхода из журнала доходит до контроллера', (tester) async {
    final c = await boot(tester);
    await tester.tap(find.byKey(const ValueKey('tab_body')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Журнал тренировок'));
    await tester.pumpAndSettle();
    expect(find.text('Пока нет записей.\nНажмите «+ Подход», чтобы начать журнал.'), findsOneWidget);

    await tester.tap(find.text('Подход'));
    await tester.pumpAndSettle();
    expect(find.text('Записать подход'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '100');
    await tester.enterText(find.byType(TextField).at(1), '5');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(c.sets.length, 1);
    expect(c.sets.single.weight, 100);
    expect(c.sets.single.reps, 5);
    await shutdown(tester, c);
  });

  testWidgets('добавление операции из учёта финансов', (tester) async {
    final c = await boot(tester);
    await tester.tap(find.byKey(const ValueKey('tab_material')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Учёт операций'));
    await tester.pumpAndSettle();
    expect(find.text('Учёт финансов'), findsOneWidget);

    await tester.tap(find.text('Операция'));
    await tester.pumpAndSettle();
    expect(find.text('Новая операция'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '1500');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(c.transactions.length, 1);
    expect(c.transactions.single.amount, 1500);
    await shutdown(tester, c);
  });

  testWidgets('смена вкладок не теряет данные контроллера', (tester) async {
    final c = await boot(tester);
    c.updateWealth(netWorth: 7777777);
    await tester.tap(find.byKey(const ValueKey('tab_material')));
    await tester.pumpAndSettle();
    expect(find.textContaining('7\u00A0777\u00A0777'), findsWidgets);
    await shutdown(tester, c);
  });

  group('знакомство', () {
    testWidgets('новая установка: прохождение до конца с примерами данных', (tester) async {
      final c = await boot(tester, blank: true);
      expect(find.text('Добро пожаловать в Life OS'), findsOneWidget);
      expect(find.byKey(const ValueKey('today_date')), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'Мария');
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
      expect(find.text('Цели на день'), findsOneWidget);

      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
      expect(find.text('Деньги (по желанию)'), findsOneWidget);

      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
      expect(find.text('Почти готово'), findsOneWidget);
      await tester.tap(find.text('Примеры данных'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Начать'));
      await tester.pumpAndSettle();

      expect(c.onboardingDone, isTrue);
      expect(c.userName, 'Мария');
      expect(c.goals, isNotEmpty);
      expect(find.byKey(const ValueKey('today_date')), findsOneWidget);
      expect(find.textContaining('Мария'), findsOneWidget);
      await shutdown(tester, c);
    });

    testWidgets('чистый старт: цели и деньги из знакомства применяются', (tester) async {
      final c = await boot(tester, blank: true);
      await tester.enterText(find.byType(TextField).first, 'Мария');
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '8000');
      await tester.enterText(find.byType(TextField).at(1), '120');
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '250000');
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Начать'));
      await tester.pumpAndSettle();

      expect(c.stepsGoal, 8000);
      expect(c.proteinGoal, 120);
      expect(c.netWorth, 250000);
      expect(c.goals, isEmpty); // чистый старт
      await shutdown(tester, c);
    });

    testWidgets('«Пропустить» завершает знакомство с умолчаниями', (tester) async {
      final c = await boot(tester, blank: true);
      await tester.tap(find.text('Пропустить'));
      await tester.pumpAndSettle();
      expect(c.onboardingDone, isTrue);
      expect(c.stepsGoal, 10000);
      expect(find.byKey(const ValueKey('today_date')), findsOneWidget);
      await shutdown(tester, c);
    });

    testWidgets('существующие данные: знакомство не показывается', (tester) async {
      final c = await boot(tester);
      expect(find.text('Добро пожаловать в Life OS'), findsNothing);
      expect(find.byKey(const ValueKey('today_date')), findsOneWidget);
      await shutdown(tester, c);
    });

    testWidgets('при недоступном хранилище знакомство не навязывается', (tester) async {
      final c = await boot(tester, blank: true, repo: MemoryAppRepository(loadError: StateError('диск')));
      expect(find.text('Добро пожаловать в Life OS'), findsNothing);
      expect(find.textContaining('Хранилище недоступно'), findsOneWidget);
      await shutdown(tester, c);
    });
  });

  group('настройки', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Настройки'));
      await tester.pumpAndSettle();
      expect(find.text('Настройки'), findsOneWidget);
    }

    testWidgets('смена имени и целей дня отражается в данных и на «Сегодня»', (tester) async {
      final c = await boot(tester);
      await openSettings(tester);

      await tester.tap(find.text('Имя'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Мария');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(c.userName, 'Мария');

      await tester.tap(find.text('Шаги'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '12000');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(c.stepsGoal, 12000);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.textContaining('Мария'), findsOneWidget);
      expect(find.textContaining('Цель 12'), findsOneWidget); // плитка шагов на «Сегодня»
      await shutdown(tester, c);
    });

    testWidgets('недопустимая цель не сохраняется (диалог остаётся открытым)', (tester) async {
      final c = await boot(tester);
      await openSettings(tester);
      await tester.tap(find.text('Шаги'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.text('Цель по шагам на день'), findsOneWidget);
      expect(c.stepsGoal, 10000);
      await shutdown(tester, c);
    });

    testWidgets('сброс данных требует слово-подтверждение', (tester) async {
      final c = await boot(tester);
      expect(c.goals, isNotEmpty);
      await openSettings(tester);

      await tester.tap(find.text('Сбросить все данные'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'нет');
      await tester.tap(find.text('Сбросить'));
      await tester.pumpAndSettle();
      expect(c.goals, isNotEmpty); // не подтверждено

      await tester.enterText(find.byType(TextField), 'сброс');
      await tester.tap(find.text('Сбросить'));
      await tester.pumpAndSettle();
      expect(c.isBlank, isTrue);
      expect(c.userName, 'Александр'); // имя сохраняется
      await shutdown(tester, c);
    });

    testWidgets('загрузка примеров данных требует подтверждения', (tester) async {
      final c = await boot(tester, blank: true);
      await tester.tap(find.text('Пропустить'));
      await tester.pumpAndSettle();
      await openSettings(tester);

      await tester.tap(find.text('Загрузить примеры данных'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(c.goals, isEmpty);

      await tester.tap(find.text('Загрузить примеры данных'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Заменить'));
      await tester.pumpAndSettle();
      expect(c.goals, isNotEmpty);
      await shutdown(tester, c);
    });

    testWidgets('«Пройти знакомство заново» закрывает настройки и показывает знакомство', (tester) async {
      final c = await boot(tester);
      await openSettings(tester);
      await tester.tap(find.text('Пройти знакомство заново'));
      await tester.pumpAndSettle();
      expect(find.text('Добро пожаловать в Life OS'), findsOneWidget);
      expect(find.text('Настройки'), findsNothing);
      expect(c.goals, isNotEmpty); // данные на месте
      await shutdown(tester, c);
    });

    testWidgets('без Health Connect (не Android) раздел показывает ручной ввод', (tester) async {
      final c = await boot(tester);
      await openSettings(tester);
      expect(find.textContaining('Доступен на Android'), findsOneWidget);
      await shutdown(tester, c);
    });
  });
}
