import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/app.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
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
    expect(find.text('EXECUTIVE DASHBOARD'), findsOneWidget);

    await tester.tap(find.text('ТЕЛО'));
    await tester.pumpAndSettle();
    expect(find.text('АНАТОМИЧЕСКАЯ КАРТА ТЕЛА'), findsOneWidget);

    await tester.tap(find.text('ГРАФ'));
    await tester.pumpAndSettle();
    expect(find.text('SECOND BRAIN GRAPH'), findsOneWidget);

    await tester.tap(find.text('СМЫСЛЫ'));
    await tester.pumpAndSettle();
    expect(find.text('СТРАТЕГИЧЕСКИЕ ЦЕЛИ'), findsOneWidget);

    await tester.tap(find.text('КАПИТАЛ'));
    await tester.pumpAndSettle();
    expect(find.text('КАПИТАЛ И КАРЬЕРА'), findsOneWidget);

    await tester.tap(find.text('HUB'));
    await tester.pumpAndSettle();
    expect(find.text('EXECUTIVE DASHBOARD'), findsOneWidget);

    await shutdown(tester, c);
  });

  testWidgets('предупреждение о недоступном хранилище', (tester) async {
    final c = await boot(tester, repo: MemoryAppRepository(loadError: StateError('диск')));
    expect(find.textContaining('Хранилище недоступно'), findsOneWidget);
    await shutdown(tester, c);
  });

  testWidgets('выбор мышцы синхронизирован между HUB и «Тело»', (tester) async {
    final c = await boot(tester);
    await tester.tap(find.text('ТЕЛО'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Бицепс').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('HUB'));
    await tester.pumpAndSettle();
    // в карточке карты тела на HUB показана выбранная мышца
    expect(find.text('Бицепс'), findsWidgets);
    await shutdown(tester, c);
  });

  testWidgets('запись подхода из журнала доходит до контроллера', (tester) async {
    final c = await boot(tester);
    await tester.tap(find.text('ТЕЛО'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ЖУРНАЛ ТРЕНИРОВОК'));
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
    await tester.tap(find.text('КАПИТАЛ'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('УЧЁТ ОПЕРАЦИЙ'));
    await tester.pumpAndSettle();
    expect(find.text('УЧЁТ ФИНАНСОВ'), findsOneWidget);

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
    await tester.tap(find.text('КАПИТАЛ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('7\u00A0777\u00A0777'), findsWidgets);
    await shutdown(tester, c);
  });

  group('знакомство', () {
    testWidgets('новая установка: прохождение до конца с примерами данных', (tester) async {
      final c = await boot(tester, blank: true);
      expect(find.text('Добро пожаловать в Life OS'), findsOneWidget);
      expect(find.text('EXECUTIVE DASHBOARD'), findsNothing);

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
      expect(find.text('EXECUTIVE DASHBOARD'), findsOneWidget);
      expect(find.text('Мария'), findsOneWidget);
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
      expect(find.text('EXECUTIVE DASHBOARD'), findsOneWidget);
      await shutdown(tester, c);
    });

    testWidgets('существующие данные: знакомство не показывается', (tester) async {
      final c = await boot(tester);
      expect(find.text('Добро пожаловать в Life OS'), findsNothing);
      expect(find.text('EXECUTIVE DASHBOARD'), findsOneWidget);
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
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      expect(find.text('НАСТРОЙКИ'), findsOneWidget);
    }

    testWidgets('смена имени и целей дня отражается в данных и на HUB', (tester) async {
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
      expect(find.text('Мария'), findsOneWidget);
      expect(find.textContaining('Цель: 12'), findsOneWidget);
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
      expect(find.text('НАСТРОЙКИ'), findsNothing);
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
