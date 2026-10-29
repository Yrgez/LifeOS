import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/models/models.dart';
import 'package:life_os/state/app_controller.dart';

void main() {
  late DateTime now;
  late MemoryAppRepository repo;

  AppController make({AppData? data, Object? loadError}) {
    repo = MemoryAppRepository(data: data, loadError: loadError);
    return AppController(repo, clock: () => now, saveDelay: Duration.zero);
  }

  setUp(() => now = DateTime(2026, 10, 24, 12));

  group('смена дня', () {
    test('прошло 2 дня: история сдвигается, дневные счётчики обнуляются', () async {
      final data = AppData.defaults(now: DateTime(2026, 10, 22));
      final c = make(data: data);
      await c.load();
      expect(c.stepsWeekHistory.length, 7);
      expect(c.stepsWeekHistory.last, 0);
      expect(c.stepsWeekHistory[5], 0);
      expect(c.dailySteps, 0);
      expect(c.proteinGrams, 0);
    });

    test('тот же день: ничего не меняется', () async {
      final c = make(data: AppData.defaults(now: now));
      await c.load();
      expect(c.dailySteps, 8420);
    });

    test('пропуск больше недели не выходит за 7 точек', () async {
      final c = make(data: AppData.defaults(now: DateTime(2026, 1, 1)));
      await c.load();
      expect(c.stepsWeekHistory.length, 7);
      expect(c.stepsWeekHistory.every((v) => v == 0), isTrue);
    });

    test('подписи недели заканчиваются сегодняшним днём (24.10.2026 — суббота)', () async {
      final c = make();
      await c.load();
      expect(c.weekLabels.last, 'Сб');
      expect(c.weekLabels.length, 7);
    });
  });

  group('журнал подходов', () {
    test('подход попадает в журнал и обновляет мышцу', () async {
      final c = make();
      await c.load();
      final res = c.logWorkout('chest', 100, 5);
      expect(res.ok, isTrue);
      expect(c.sets.length, 1);
      final m = c.muscles['chest']!;
      expect(m.lastTrainedAt, now);
      expect(m.lastSets.first, '100кг × 5');
      expect(m.lastSets.length, lessThanOrEqualTo(6));
    });

    test('рекорд определяется относительно базы и журнала', () async {
      final c = make();
      await c.load();
      expect(c.logWorkout('chest', 50, 5).isRecord, isFalse); // база 120
      expect(c.logWorkout('chest', 200, 1).isRecord, isTrue);
      expect(c.muscles['chest']!.maxWeight, 200);
      expect(c.logWorkout('chest', 150, 1).isRecord, isFalse);
      expect(c.muscles['chest']!.maxWeight, 200);
    });

    test('прогрессия = база + лучший 1RM за каждый день журнала', () async {
      final c = make();
      await c.load();
      final base = c.progression('abs').length; // 5 базовых точек
      c.logWorkout('abs', 20, 10);
      c.logWorkout('abs', 40, 10); // тот же день — одна точка (лучшая)
      c.logWorkout('abs', 10, 10, daysAgo: 1); // вчера — отдельная точка
      final p = c.progression('abs');
      expect(p.length, base + 2 > 8 ? 8 : base + 2);
      expect(p.last, closeTo(53.3, 0.1)); // сегодня: 40 × 10
      expect(p[p.length - 2], closeTo(13.3, 0.1)); // вчера: 10 × 10
    });

    test('подход задним числом не «омолаживает» мышцу', () async {
      final c = make();
      await c.load();
      final before = c.muscles['chest']!.lastTrainedAt; // 48 ч назад (база)
      c.logWorkout('chest', 60, 5, daysAgo: 5);
      expect(c.muscles['chest']!.lastTrainedAt, before);
    });

    test('журнал отсортирован по времени, даже если вводили вразнобой', () async {
      final c = make();
      await c.load();
      c.logWorkout('chest', 60, 5);
      c.logWorkout('chest', 60, 5, daysAgo: 3);
      c.logWorkout('chest', 60, 5, daysAgo: 1);
      final times = c.sets.map((s) => s.at).toList();
      expect([...times]..sort(), times);
    });

    test('удаление подхода откатывает рекорд, время и последние подходы', () async {
      final c = make();
      await c.load();
      final baseMax = c.muscles['chest']!.maxWeight;
      final baseTrained = c.muscles['chest']!.lastTrainedAt;
      final baseSets = List<String>.of(c.muscles['chest']!.lastSets);
      c.logWorkout('chest', 300, 1); // «опечатка»
      expect(c.muscles['chest']!.maxWeight, 300);
      final removed = c.deleteSet(c.sets.single.id);
      expect(removed, isNotNull);
      final m = c.muscles['chest']!;
      expect(m.maxWeight, baseMax);
      expect(m.lastTrainedAt, baseTrained);
      expect(m.lastSets, baseSets);
      expect(c.sets, isEmpty);
    });

    test('«Отменить» возвращает удалённый подход', () async {
      final c = make();
      await c.load();
      c.logWorkout('chest', 100, 5);
      final removed = c.deleteSet(c.sets.single.id)!;
      c.restoreSet(removed);
      c.restoreSet(removed); // повторный вызов не создаёт дубль
      expect(c.sets.length, 1);
      expect(c.muscles['chest']!.lastSets.first, '100кг × 5');
    });

    test('некорректный ввод и неизвестная мышца отклоняются', () async {
      final c = make();
      await c.load();
      expect(c.logWorkout('chest', 0, 5).ok, isFalse);
      expect(c.logWorkout('chest', 50, 0).ok, isFalse);
      expect(c.logWorkout('chest', 50, 5, daysAgo: -1).ok, isFalse);
      expect(c.logWorkout('нет такой', 50, 5).ok, isFalse);
      expect(c.sets, isEmpty);
    });

    test('lastSetFor возвращает последний подход по мышце', () async {
      final c = make();
      await c.load();
      expect(c.lastSetFor('chest'), isNull);
      c.logWorkout('chest', 80, 8);
      c.logWorkout('abs', 10, 20);
      c.logWorkout('chest', 90, 6);
      expect(c.lastSetFor('chest')!.weight, 90);
    });

    test('после подхода мышца «красная», готовность тела падает', () async {
      final c = make();
      await c.load();
      final before = c.systemReadiness;
      c.logWorkout('chest', 100, 5);
      expect(c.muscles['chest']!.recoveryAt(now), closeTo(0.15, 1e-9));
      expect(c.systemReadiness, lessThan(before));
    });

    test('журнал переживает сохранение и загрузку', () async {
      final c = make();
      await c.load();
      c.logWorkout('chest', 100, 5);
      c.logWorkout('abs', 20, 15, daysAgo: 2);
      await c.flush();
      final c2 = AppController(repo, clock: () => now, saveDelay: Duration.zero);
      await c2.load();
      expect(c2.sets.length, 2);
      expect(c2.sets.last.muscleId, 'chest');
      expect(c2.muscles['chest']!.lastSets.first, '100кг × 5');
    });

    test('журнал ограничен kMaxWorkoutSets (самые старые удаляются)', () async {
      final data = AppData.defaults(now: now);
      for (int i = 0; i < kMaxWorkoutSets; i++) {
        data.workoutSets.add(WorkoutSet(id: 's$i', muscleId: 'abs', at: now.subtract(Duration(days: 30, minutes: kMaxWorkoutSets - i)), weight: 10, reps: 10));
      }
      final c = make(data: data);
      await c.load();
      c.logWorkout('abs', 20, 10);
      expect(c.sets.length, kMaxWorkoutSets);
      expect(c.sets.any((s) => s.id == 's0'), isFalse);
      expect(c.sets.last.weight, 20);
    });
  });

  group('цели', () {
    test('достижение за закрытую цель создаётся ровно один раз', () async {
      final c = make();
      await c.load();
      final goal = c.goals.first;
      for (int i = 0; i < goal.checkpoints.length; i++) {
        c.toggleCheckpoint(goal.id, i, true);
      }
      // переключаем туда-сюда
      c.toggleCheckpoint(goal.id, 0, false);
      c.toggleCheckpoint(goal.id, 0, true);
      expect(c.achievements.where((a) => a.id == 'goal_done_${goal.id}').length, 1);
    });

    test('addGoal разбирает чекпоинты и пропускает пустые строки', () async {
      final c = make();
      await c.load();
      c.addGoal('Цель', '', ['  один ', '', 'два']);
      final g = c.goals.last;
      expect(g.checkpoints.map((e) => e.title), ['один', 'два']);
      expect(g.category, 'Стратегия');
    });

    test('списки изменяемы (раньше const-списки падали на insert/add)', () async {
      final c = make();
      await c.load();
      expect(() => c.addAchievement('Рекорд', ''), returnsNormally);
      expect(() => c.addSalaryStep('2027', 'CTO', 500000), returnsNormally);
    });
  });

  group('граф', () {
    test('удаление узла удаляет его связи', () async {
      final c = make();
      await c.load();
      c.deleteNode('n_sleep');
      expect(c.nodeById('n_sleep'), isNull);
      expect(c.graphEdges.any((e) => e.fromId == 'n_sleep' || e.toId == 'n_sleep'), isFalse);
    });

    test('addEdge: без петель, дублей (в обе стороны) и несуществующих узлов', () async {
      final c = make();
      await c.load();
      expect(c.addEdge('n_salary', 'n_salary'), isFalse);
      expect(c.addEdge('n_salary', 'n_capital'), isFalse);
      expect(c.addEdge('n_capital', 'n_salary'), isFalse);
      expect(c.addEdge('n_salary', 'нет'), isFalse);
      expect(c.addEdge('n_goal_salary', 'n_cushion'), isTrue);
    });

    test('moveNode зажимает позицию в границах холста', () async {
      final c = make();
      await c.load();
      c.moveNode('n_salary', const Offset(5, -5));
      expect(c.nodeById('n_salary')!.position, const Offset(0.95, 0.05));
    });

    test('подписи системных узлов следуют за данными', () async {
      final c = make();
      await c.load();
      c.updateWealth(netWorth: 3000000, income: 450000);
      expect(c.nodeById('n_capital')!.label, 'Капитал 3.00М');
      expect(c.nodeById('n_salary')!.label, 'ЗП: 450к');
    });

    test('addNode: пустое имя отклоняется, история роста узлов обновляется', () async {
      final c = make();
      await c.load();
      expect(c.addNode('   ', 'mind'), isFalse);
      final n = c.graphNodes.length;
      expect(c.addNode('Новый', 'gym'), isTrue);
      expect(c.graphEvolutionHistory.last, (n + 1).toDouble());
    });
  });

  group('сохранение', () {
    test('flush пишет данные в репозиторий', () async {
      final c = make();
      await c.load();
      c.updateWealth(netWorth: 42);
      await c.flush();
      expect(repo.data!.netWorth, 42);
    });

    test('если загрузка не удалась — НИЧЕГО не записывается (данные пользователя в безопасности)', () async {
      final c = make(loadError: StateError('диск недоступен'));
      await c.load();
      expect(c.loaded, isFalse);
      expect(c.loadFailed, isTrue);
      c.updateWealth(netWorth: 1);
      await c.flush();
      expect(repo.saveCalls, 0);
    });

    test('схема новее — запись тоже отключена', () async {
      final c = make(loadError: const SchemaTooNewException(99));
      await c.load();
      await c.flush();
      expect(repo.saveCalls, 0);
    });

    test('первый запуск (данных нет) — запись разрешена', () async {
      final c = make();
      await c.load();
      expect(c.loaded, isTrue);
    });
  });

  group('резервная копия', () {
    test('экспорт → импорт восстанавливает данные', () async {
      final c = make();
      await c.load();
      c.updateWealth(netWorth: 123456);
      final backup = c.exportBackup();

      final c2 = make();
      await c2.load();
      expect(c2.importBackup(backup), isTrue);
      expect(c2.netWorth, 123456);
    });

    test('мусор и чужой JSON отклоняются, данные не тронуты', () async {
      final c = make();
      await c.load();
      final before = c.netWorth;
      expect(c.importBackup('это не json'), isFalse);
      expect(c.importBackup('[1,2,3]'), isFalse);
      expect(c.importBackup('{"netWorth": 1}'), isFalse); // нет schemaVersion
      expect(c.importBackup('{"schemaVersion": 999}'), isFalse);
      expect(c.netWorth, before);
    });
  });

  test('слушатели уведомляются об изменениях', () async {
    final c = make();
    await c.load();
    int calls = 0;
    c.addListener(() => calls++);
    c.updateHealth(steps: 100);
    expect(calls, 1);
  });
}
