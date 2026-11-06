import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/models/models.dart';

void main() {
  test('круговая сериализация значений по умолчанию', () {
    final d = AppData.defaults(now: DateTime(2026, 10, 24));
    final back = AppData.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
    expect(back.netWorth, d.netWorth);
    expect(back.muscles.keys, d.muscles.keys);
    expect(back.goals.length, d.goals.length);
    expect(back.graphNodes.length, d.graphNodes.length);
    expect(back.stepsWeekHistory, d.stepsWeekHistory);
    expect(back.lastDay, '2026-10-24');
  });

  test('toJson содержит версию схемы', () {
    expect(AppData.defaults().toJson()['schemaVersion'], kSchemaVersion);
  });

  test('пустой объект → всё по умолчанию', () {
    final d = AppData.fromJson({}, now: DateTime(2026, 10, 24));
    expect(d.netWorth, AppData.defaults().netWorth);
    expect(d.muscles, isNotEmpty);
  });

  test('повреждённое поле заменяется дефолтом, остальные сохраняются', () {
    final d = AppData.fromJson({'netWorth': 'не число', 'monthlyIncome': 123, 'goals': 42});
    expect(d.netWorth, AppData.defaults().netWorth);
    expect(d.monthlyIncome, 123);
    expect(d.goals, isNotEmpty);
  });

  test('недельные ряды приводятся к 7 точкам', () {
    final d = AppData.fromJson({'stepsWeekHistory': [1, 2, 3]});
    expect(d.stepsWeekHistory.length, 7);
  });

  test('журнал подходов сериализуется и сортируется по времени при чтении', () {
    final d = AppData.defaults(now: DateTime(2026, 10, 24));
    d.workoutSets.addAll([
      WorkoutSet(id: 'b', muscleId: 'chest', at: DateTime(2026, 10, 23, 10), weight: 80.5, reps: 8),
      WorkoutSet(id: 'a', muscleId: 'abs', at: DateTime(2026, 10, 22, 9), weight: 20, reps: 15),
    ]);
    final back = AppData.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
    expect(back.workoutSets.map((s) => s.id), ['a', 'b']);
    expect(back.workoutSets.last.weight, 80.5);
  });

  test('старое сохранение без журнала — журнал пуст', () {
    expect(AppData.fromJson({'netWorth': 1}).workoutSets, isEmpty);
  });

  test('операции и состояние Health Connect сериализуются', () {
    final d = AppData.defaults(now: DateTime(2026, 10, 24));
    d.transactions.addAll([
      MoneyTx(id: 'b', at: DateTime(2026, 10, 23, 10), isIncome: false, amount: 500, categoryId: 'food'),
      MoneyTx(id: 'a', at: DateTime(2026, 10, 1, 9), isIncome: true, amount: 100000, categoryId: 'salary', note: 'аванс'),
    ]);
    d.healthEnabled = true;
    d.lastHealthSyncMs = 1760000000000;
    final back = AppData.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
    expect(back.transactions.map((t) => t.id), ['a', 'b']); // отсортированы по времени
    expect(back.transactions.first.note, 'аванс');
    expect(back.healthEnabled, isTrue);
    expect(back.lastHealthSyncMs, 1760000000000);
  });

  test('старое сохранение: операций нет, Health Connect выключен', () {
    final d = AppData.fromJson({'netWorth': 1});
    expect(d.transactions, isEmpty);
    expect(d.healthEnabled, isFalse);
    expect(d.lastHealthSyncMs, isNull);
  });

  test('лимиты и правила повторяющихся операций сериализуются', () {
    final d = AppData.defaults(now: DateTime(2026, 10, 24));
    d.budgets['food'] = 20000;
    d.recurring.add(RecurringTx(id: 'r1', categoryId: 'housing', amount: 40000, dayOfMonth: 25, start: DateTime(2026, 10, 24), note: 'аренда', lastMonth: '2026-10'));
    d.transactions.add(MoneyTx(id: 't1', at: DateTime(2026, 10, 25, 9), isIncome: false, amount: 40000, categoryId: 'housing', recurringId: 'r1'));
    final back = AppData.fromJson(jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>);
    expect(back.budgets, {'food': 20000});
    expect(back.recurring.single.note, 'аренда');
    expect(back.recurring.single.lastMonth, '2026-10');
    expect(back.recurring.single.dayOfMonth, 25);
    expect(back.transactions.single.recurringId, 'r1');
  });

  test('старое сохранение: лимитов и правил нет', () {
    final d = AppData.fromJson({'netWorth': 1});
    expect(d.budgets, isEmpty);
    expect(d.recurring, isEmpty);
  });

  test('strict import rejects journals above their in-memory limits', () {
    final workout = WorkoutSet(
      id: 'set',
      muscleId: 'chest',
      at: DateTime(2026, 10, 24),
      weight: 50,
      reps: 8,
    ).toJson();
    final transaction = MoneyTx(
      id: 'tx',
      at: DateTime(2026, 10, 24),
      isIncome: false,
      amount: 100,
      categoryId: 'food',
    ).toJson();

    expect(
      () => AppData.fromJson(
        {
          'schemaVersion': kSchemaVersion,
          'workoutSets': List<Map<String, dynamic>>.filled(
            kMaxWorkoutSets + 1,
            workout,
          ),
        },
        strict: true,
      ),
      throwsFormatException,
    );
    expect(
      () => AppData.fromJson(
        {
          'schemaVersion': kSchemaVersion,
          'transactions': List<Map<String, dynamic>>.filled(
            kMaxTransactions + 1,
            transaction,
          ),
        },
        strict: true,
      ),
      throwsFormatException,
    );
  });


  test('strict import rejects duplicate primary keys in both journals', () {
    final set = WorkoutSet(
      id: 'duplicate-set',
      muscleId: 'chest',
      at: DateTime(2026, 10, 24),
      weight: 50,
      reps: 8,
    ).toJson();
    final tx = MoneyTx(
      id: 'duplicate-tx',
      at: DateTime(2026, 10, 24),
      isIncome: false,
      amount: 100,
      categoryId: 'food',
    ).toJson();

    expect(
      () => AppData.fromJson({
        'schemaVersion': kSchemaVersion,
        'workoutSets': [set, Map<String, dynamic>.of(set)],
      }, strict: true),
      throwsFormatException,
    );
    expect(
      () => AppData.fromJson({
        'schemaVersion': kSchemaVersion,
        'transactions': [tx, Map<String, dynamic>.of(tx)],
      }, strict: true),
      throwsFormatException,
    );
  });


  test('strict import rejects duplicate IDs in SQLite document collections', () {
    final data = AppData.defaults(now: DateTime(2026, 10, 24));
    final goal = GlobalGoal(
      id: 'duplicate-goal',
      title: 'Goal',
      category: 'mind',
      checkpoints: [],
    ).toJson();
    final achievement = const AchievementItem(
      id: 'duplicate-achievement',
      title: 'Achievement',
      date: '2026-10-24',
      category: 'mind',
    ).toJson();
    final salary = const SalaryStep(
      year: '2026',
      role: 'Analyst',
      salary: 100,
    ).toJson();
    final node = data.graphNodes.first.toJson();
    final edge = const GraphEdge('source', 'target').toJson();
    final recurring = RecurringTx(
      id: 'duplicate-recurring',
      categoryId: 'housing',
      amount: 100,
      dayOfMonth: 1,
      start: DateTime(2026, 10, 1),
    ).toJson();

    final duplicateCollections = <String, List<Map<String, dynamic>>>{
      'goals': [goal, Map<String, dynamic>.of(goal)],
      'achievements': [achievement, Map<String, dynamic>.of(achievement)],
      'salaryHistory': [salary, Map<String, dynamic>.of(salary)],
      'graphNodes': [node, Map<String, dynamic>.of(node)],
      'graphEdges': [edge, Map<String, dynamic>.of(edge)],
      'recurring': [recurring, Map<String, dynamic>.of(recurring)],
    };

    for (final entry in duplicateCollections.entries) {
      final backup = data.toJson()..[entry.key] = entry.value;
      expect(
        () => AppData.fromJson(backup, strict: true),
        throwsFormatException,
        reason: 'duplicate key in ${entry.key}',
      );
    }
  });

}
