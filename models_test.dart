import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/models/models.dart';

MuscleGroup muscle({DateTime? at, double rh = 48}) => MuscleGroup(
      id: 'chest',
      name: 'Грудь',
      recoveryHours: rh,
      lastTrainedAt: at,
      maxWeight: 100,
      lastSets: [],
      history1RM: [100],
    );

void main() {
  group('MuscleGroup.recoveryAt', () {
    final t0 = DateTime(2026, 10, 1, 12);
    test('сразу после тренировки — 15%', () => expect(muscle(at: t0).recoveryAt(t0), closeTo(0.15, 1e-9)));
    test('через recoveryHours — 100%', () => expect(muscle(at: t0).recoveryAt(t0.add(const Duration(hours: 48))), 1.0));
    test('середина периода — линейно', () => expect(muscle(at: t0).recoveryAt(t0.add(const Duration(hours: 24))), closeTo(0.575, 1e-9)));
    test('не тренировалась — 100%', () => expect(muscle().recoveryAt(t0), 1.0));
    test('не превышает 100%', () => expect(muscle(at: t0).recoveryAt(t0.add(const Duration(days: 30))), 1.0));
  });

  group('MuscleGroup JSON', () {
    test('круговая сериализация', () {
      final m = muscle(at: DateTime.fromMillisecondsSinceEpoch(1760000000000));
      final back = MuscleGroup.fromJson(m.toJson());
      expect(back.lastTrainedAt, m.lastTrainedAt);
      expect(back.maxWeight, 100);
      expect(back.history1RM, [100]);
    });

    test('миграция старого формата: recovery 0.5 → ≈50%', () {
      final m = MuscleGroup.fromJson({'id': 'chest', 'name': 'Грудь', 'recovery': 0.5, 'maxWeight': 100, 'lastSets': [], 'history1RM': [100]});
      expect(m.recovery, closeTo(0.5, 0.01));
    });

    test('нет поля истории 1RM — базой становится рекорд', () {
      final m = MuscleGroup.fromJson({'id': 'x', 'name': 'X', 'maxWeight': 70});
      expect(m.history1RM, [70]);
    });

    test('пустая история 1RM остаётся пустой (чистый старт), круг JSON её не меняет', () {
      final m = MuscleGroup.fromJson({'id': 'x', 'name': 'X', 'maxWeight': 0, 'history1RM': []});
      expect(m.history1RM, isEmpty);
      expect(MuscleGroup.fromJson(m.toJson()).history1RM, isEmpty);
    });
  });

  group('GraphNode JSON', () {
    test('новый формат (доли)', () {
      final n = GraphNode.fromJson({'id': 'a', 'label': 'A', 'fx': 0.25, 'fy': 0.75, 'color': 0xFF00E676});
      expect(n.position, const Offset(0.25, 0.75));
    });
    test('старый формат (пиксели) переводится в доли и зажимается в [0.06, 0.94]', () {
      final n = GraphNode.fromJson({'id': 'a', 'label': 'A', 'dx': 180, 'dy': 9999});
      expect(n.position.dx, closeTo(0.5, 1e-9));
      expect(n.position.dy, 0.94);
    });
  });

  group('GlobalGoal', () {
    test('прогресс', () {
      final g = GlobalGoal(id: 'g', title: 't', category: 'c', checkpoints: [
        GoalCheckpoint(title: 'a', isCompleted: true),
        GoalCheckpoint(title: 'b'),
      ]);
      expect(g.progress, 0.5);
    });
    test('пустой список чекпоинтов — 0, а не NaN', () {
      expect(GlobalGoal(id: 'g', title: 't', category: 'c', checkpoints: []).progress, 0);
    });
  });

  group('WorkoutSet', () {
    test('объём = вес × повторы', () {
      final s = WorkoutSet(id: 'x', muscleId: 'chest', at: DateTime(2026, 1, 1), weight: 82.5, reps: 4);
      expect(s.volume, 330);
    });
    test('расчётный 1RM округляется до 0.1', () {
      final s = WorkoutSet(id: 'x', muscleId: 'chest', at: DateTime(2026, 1, 1), weight: 100, reps: 5);
      expect(s.estimated1RM, 112.5);
    });
    test('JSON туда-обратно', () {
      final s = WorkoutSet(id: 'x', muscleId: 'chest', at: DateTime.fromMillisecondsSinceEpoch(1760000000000), weight: 82.5, reps: 4);
      final back = WorkoutSet.fromJson(s.toJson());
      expect(back.at, s.at);
      expect(back.weight, 82.5);
      expect(back.label, '82.5кг × 4');
    });
  });

  group('MuscleGroup базовое состояние', () {
    test('старое сохранение без base*: базой становится текущее', () {
      final m = MuscleGroup.fromJson({'id': 'chest', 'name': 'Грудь', 'maxWeight': 120, 'lastSets': ['80кг × 12'], 'history1RM': [100, 120], 'lastTrainedAtMs': 1760000000000});
      expect(m.baseMax, 120);
      expect(m.baseSets, ['80кг × 12']);
      expect(m.baseTrainedAt, DateTime.fromMillisecondsSinceEpoch(1760000000000));
    });
  });

  group('MetricLink', () {
    test('JSON туда-обратно', () {
      const l = MetricLink(kind: MetricLink.oneRM, muscleId: 'chest', target: 100.5);
      final back = MetricLink.fromJson(l.toJson());
      expect(back.kind, MetricLink.oneRM);
      expect(back.muscleId, 'chest');
      expect(back.target, 100.5);
      expect(back.unit, 'кг');
    });
    test('денежные метрики — рубли', () => expect(const MetricLink(kind: MetricLink.income, target: 1).unit, '₽'));
  });

  test('GlobalGoal.isComplete: пустая цель не выполнена', () {
    expect(GlobalGoal(id: 'g', title: 't', category: 'c', checkpoints: []).isComplete, isFalse);
  });
}
