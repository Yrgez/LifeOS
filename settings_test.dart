import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/graph_stats.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/models/models.dart';
import 'package:life_os/state/app_controller.dart';

void main() {
  late DateTime now;
  late MemoryAppRepository repo;

  Future<AppController> make({bool blank = false, AppData? data}) async {
    repo = MemoryAppRepository(data: data);
    final c = AppController(
      repo,
      clock: () => now,
      saveDelay: Duration.zero,
      initialData: blank ? (n) => AppData.blank(now: n) : null,
    );
    await c.load();
    return c;
  }

  setUp(() => now = DateTime(2026, 10, 24, 12));

  group('чистый старт', () {
    test('новая установка: пусто, знакомство не пройдено', () async {
      final c = await make(blank: true);
      expect(c.onboardingDone, isFalse);
      expect(c.isBlank, isTrue);
      expect(c.netWorth, 0);
      expect(c.goals, isEmpty);
      expect(c.achievements, isEmpty);
      expect(c.salaryHistory, isEmpty);
      expect(c.transactions, isEmpty);
      expect(c.sets, isEmpty);
      expect(c.muscles.length, 12);
      expect(c.userName, '');
      expect(c.stepsGoal, 10000);
      expect(c.proteinGoal, 140);
    });

    test('мышцы без истории: 100% готовности, нулевой рекорд, прогрессия начинается с журнала', () async {
      final c = await make(blank: true);
      expect(c.systemReadiness, 100);
      expect(c.muscles['chest']!.maxWeight, 0);
      expect(c.progression('chest'), [0]); // нет данных
      c.logWorkout('chest', 100, 5);
      expect(c.progression('chest'), [112.5]); // без «нулевой» базовой точки
      expect(c.logWorkout('abs', 20, 10).isRecord, isTrue); // первый результат — всегда рекорд
    });

    test('стартовый граф: только «живые» узлы, без изолированных; списки изменяемы', () async {
      final c = await make(blank: true);
      expect(c.graphNodes.map((n) => n.id).toSet(), AppController.autoNodeIds.union({'n_sleep'}));
      expect(isolatedNodeIds(c.graphNodes, c.graphEdges), isEmpty);
      expect(() => c.addNode('Идея', 'mind'), returnsNormally);
      expect(() => c.updateHealth(steps: 5000), returnsNormally); // недельные истории не фиксированной длины
      c.refresh();
      expect(c.stepsWeekHistory.length, 7);
    });

    test('подписи «живых» узлов подстраиваются под данные', () async {
      final c = await make(blank: true);
      c.updateWealth(netWorth: 1500000, income: 200000);
      expect(c.nodeById('n_capital')!.label, 'Капитал 1.50М');
      expect(c.nodeById('n_salary')!.label, 'ЗП: 200к');
    });

    test('чистое состояние сохраняется и читается', () async {
      final c = await make(blank: true);
      await c.flush();
      final c2 = AppController(repo, clock: () => now, saveDelay: Duration.zero);
      await c2.load();
      expect(c2.onboardingDone, isFalse);
      expect(c2.muscles.length, 12);
      expect(c2.goals, isEmpty);
    });
  });

  group('существующие данные', () {
    test('старое сохранение без новых полей: знакомство не показывается, имя прежнее', () {
      final d = AppData.fromJson({'netWorth': 5});
      expect(d.onboardingDone, isTrue);
      expect(d.userName, 'Александр');
      expect(d.stepsGoal, 10000);
      expect(d.proteinGoal, 140);
    });

    test('демо-данные по умолчанию — «как у существующего пользователя»', () async {
      final c = await make();
      expect(c.onboardingDone, isTrue);
      expect(c.userName, 'Александр');
      expect(c.isBlank, isFalse);
    });

    test('импорт старой резервной копии не запускает знакомство', () async {
      final c = await make(blank: true);
      final old = AppData.defaults(now: now).toJson()
        ..remove('onboardingDone')
        ..remove('userName');
      c.importBackup(_encode(old));
      expect(c.onboardingDone, isTrue);
    });
  });

  group('настройки', () {
    test('имя очищается: пробелы, переносы, длина', () async {
      final c = await make();
      expect(c.updateSettings(userName: '   Мария   Иванова \n'), isTrue);
      expect(c.userName, 'Мария Иванова');
      c.updateSettings(userName: 'А' * 80);
      expect(c.userName.length, 40);
      c.updateSettings(userName: '   ');
      expect(c.userName, '');
    });

    test('цели дня: допустимые значения применяются, недопустимые отклоняются целиком', () async {
      final c = await make();
      expect(c.updateSettings(stepsGoal: 12000, proteinGoal: 150), isTrue);
      expect(c.stepsGoal, 12000);
      expect(c.proteinGoal, 150);

      expect(c.updateSettings(stepsGoal: 0), isFalse);
      expect(c.updateSettings(stepsGoal: 100001), isFalse);
      expect(c.updateSettings(proteinGoal: 0), isFalse);
      expect(c.updateSettings(proteinGoal: 1001), isFalse);
      expect(c.updateSettings(userName: 'Не должно примениться', stepsGoal: -5), isFalse);
      expect(c.stepsGoal, 12000);
      expect(c.userName, isNot('Не должно примениться'));
    });

    test('настройки переживают сохранение', () async {
      final c = await make();
      c.updateSettings(userName: 'Мария', stepsGoal: 8000, proteinGoal: 120);
      await c.flush();
      final c2 = AppController(repo, clock: () => now, saveDelay: Duration.zero);
      await c2.load();
      expect(c2.userName, 'Мария');
      expect(c2.stepsGoal, 8000);
      expect(c2.proteinGoal, 120);
    });
  });

  group('знакомство', () {
    test('завершение применяет имя, цели и деньги', () async {
      final c = await make(blank: true);
      c.completeOnboarding(userName: ' Мария ', stepsGoal: 9000, proteinGoal: 110, netWorth: 250000, income: 90000, expense: 60000);
      expect(c.onboardingDone, isTrue);
      expect(c.userName, 'Мария');
      expect(c.stepsGoal, 9000);
      expect(c.proteinGoal, 110);
      expect(c.netWorth, 250000);
      expect(c.monthlyIncome, 90000);
      expect(c.monthlyExpense, 60000);
      expect(c.isBlank, isFalse); // капитал указан
    });

    test('пустые и недопустимые значения не затирают умолчания', () async {
      final c = await make(blank: true);
      c.completeOnboarding(userName: '', stepsGoal: 0, proteinGoal: 5000, income: -1, expense: -1);
      expect(c.onboardingDone, isTrue);
      expect(c.stepsGoal, 10000);
      expect(c.proteinGoal, 140);
      expect(c.monthlyIncome, 0);
      expect(c.monthlyExpense, 0);
    });

    test('«примеры данных» заполняют пустое приложение, настройки сохраняются', () async {
      final c = await make(blank: true);
      c.completeOnboarding(userName: 'Мария', stepsGoal: 9000, demo: true);
      expect(c.goals, isNotEmpty);
      expect(c.muscles['chest']!.maxWeight, 120);
      expect(c.userName, 'Мария');
      expect(c.stepsGoal, 9000);
      expect(c.onboardingDone, isTrue);
    });

    test('«примеры данных» НЕ затирают реальные данные при повторном знакомстве', () async {
      final c = await make(blank: true);
      c.completeOnboarding(userName: 'Мария');
      c.logWorkout('chest', 100, 5);
      c.addTransaction(categoryId: 'food', amount: 700);
      c.restartOnboarding();
      expect(c.onboardingDone, isFalse);
      c.completeOnboarding(userName: 'Мария', demo: true);
      expect(c.sets.length, 1);
      expect(c.transactions.length, 1);
      expect(c.goals, isEmpty);
    });

    test('restartOnboarding не меняет данные', () async {
      final c = await make();
      final w = c.netWorth;
      c.restartOnboarding();
      expect(c.onboardingDone, isFalse);
      expect(c.netWorth, w);
      expect(c.goals, isNotEmpty);
    });

    test('состояние знакомства переживает перезапуск', () async {
      final c = await make(blank: true);
      c.completeOnboarding(userName: 'Мария');
      await c.flush();
      final c2 = AppController(repo, clock: () => now, saveDelay: Duration.zero, initialData: (n) => AppData.blank(now: n));
      await c2.load();
      expect(c2.onboardingDone, isTrue);
      expect(c2.userName, 'Мария');
    });
  });

  group('сброс данных', () {
    test('чистый сброс: данные очищены, имя/цели/Health Connect сохранены', () async {
      final c = await make();
      c.updateSettings(userName: 'Мария', stepsGoal: 8000, proteinGoal: 120);
      c.logWorkout('chest', 100, 5);
      c.addTransaction(categoryId: 'food', amount: 700);
      c.addRecurring(categoryId: 'subs', amount: 500, dayOfMonth: 24);
      c.setBudget('food', 1000);
      c.resetAllData();
      expect(c.isBlank, isTrue);
      expect(c.sets, isEmpty);
      expect(c.transactions, isEmpty);
      expect(c.recurring, isEmpty);
      expect(c.budgets, isEmpty);
      expect(c.goals, isEmpty);
      expect(c.userName, 'Мария');
      expect(c.stepsGoal, 8000);
      expect(c.proteinGoal, 120);
      expect(c.onboardingDone, isTrue); // знакомство повторно не запускается
    });

    test('сброс с примерами', () async {
      final c = await make(blank: true);
      c.completeOnboarding(userName: 'Мария');
      c.resetAllData(demo: true);
      expect(c.goals, isNotEmpty);
      expect(c.userName, 'Мария');
    });

    test('сброс доходит до хранилища (строки удаляются)', () async {
      final c = await make();
      c.logWorkout('chest', 100, 5);
      await c.flush();
      expect(repo.data!.workoutSets, isNotEmpty);
      c.resetAllData();
      await c.flush();
      expect(repo.data!.workoutSets, isEmpty);
      expect(repo.data!.goals, isEmpty);
    });
  });

  test('AppData.blank: круг JSON', () {
    final d = AppData.blank(now: DateTime(2026, 10, 24));
    final back = AppData.fromJson(d.toJson());
    expect(back.onboardingDone, isFalse);
    expect(back.muscles.length, 12);
    expect(back.graphNodes.length, 6);
    expect(back.userName, '');
    expect(back.lastDay, '2026-10-24');
  });
}

String _encode(Map<String, dynamic> m) => jsonEncode(m);
