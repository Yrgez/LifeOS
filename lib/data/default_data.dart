import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';

/// Создаёт демо-мышцу. Время последней тренировки задаётся и как текущее ([lastTrainedAt]),
/// и как БАЗОВОЕ ([baseTrainedAt]): от базы отталкивается пересчёт после добавления/удаления подхода
/// (см. AppController._recomputeMuscle). Без базы удаление подхода «стирало» время тренировки,
/// а подход задним числом подменял его более старой датой.
MuscleGroup _m(
  DateTime base,
  String id,
  String name,
  int hoursAgo,
  double max,
  List<String> sets,
  List<double> hist,
) {
  final trainedAt = base.subtract(Duration(hours: hoursAgo));
  return MuscleGroup(
    id: id,
    name: name,
    recoveryHours: MuscleGroup.defaultRecoveryHours[id] ?? 48,
    lastTrainedAt: trainedAt,
    baseTrainedAt: trainedAt,
    maxWeight: max,
    lastSets: sets,
    history1RM: hist,
  );
}

/// [now] — «точка отсчёта» для времени последних тренировок (детерминированно в тестах).
Map<String, MuscleGroup> defaultMuscles({DateTime? now}) {
  final b = now ?? DateTime.now();
  return {
    'delts': _m(b, 'delts', 'Дельтовидные', 14, 36, ['14кг × 15', '16кг × 12'], [28, 30, 32, 34, 36]),
    'chest': _m(b, 'chest', 'Грудные мышцы', 48, 120, ['80кг × 12', '100кг × 6'], [95, 100, 107, 115, 120]),
    'abs': _m(b, 'abs', 'Пресс и Кор', 72, 25, ['Скручивания +15кг × 20'], [15, 18, 20, 22, 25]),
    'biceps': _m(b, 'biceps', 'Бицепс', 36, 45, ['35кг × 10', '40кг × 8'], [35, 37, 40, 42, 45]),
    'forearms': _m(b, 'forearms', 'Предплечья', 120, 40, ['Хват 40кг × 40с'], [30, 32, 35, 38, 40]),
    'quads': _m(b, 'quads', 'Квадрицепсы', 30, 150, ['100кг × 10', '120кг × 8'], [120, 130, 135, 142, 150]),
    'traps': _m(b, 'traps', 'Трапеции', 96, 110, ['Шраги 90кг × 12'], [90, 95, 100, 105, 110]),
    'lats': _m(b, 'lats', 'Широчайшие спины', 16, 135, ['Подтягивания +20кг × 6'], [110, 118, 125, 130, 135]),
    'triceps': _m(b, 'triceps', 'Трицепс', 72, 50, ['Французский жим 45кг × 8'], [38, 40, 44, 47, 50]),
    'glutes': _m(b, 'glutes', 'Ягодичные', 40, 160, ['Мостик 140кг × 10'], [130, 140, 145, 152, 160]),
    'hamstrings': _m(b, 'hamstrings', 'Бицепс бедра', 24, 140, ['Мертвая тяга 120кг × 8'], [115, 122, 128, 135, 140]),
    'calves': _m(b, 'calves', 'Икроножные', 80, 120, ['Подъемы 100кг × 15'], [95, 100, 108, 114, 120]),
  };
}

List<GlobalGoal> defaultGoals() => [
      GlobalGoal(
        id: 'g1',
        title: 'Карьерный левел-ап: доход 500 000 ₽ / мес',
        category: 'Карьера и Финансы',
        checkpoints: [
          GoalCheckpoint(title: 'Пройти аудит навыков и System Design', isCompleted: true),
          GoalCheckpoint(title: 'Грейд Lead / Head (ЗП 380 000 ₽)', isCompleted: true),
          GoalCheckpoint(title: 'Запустить 2-й поток дохода (консалтинг)'),
          GoalCheckpoint(title: 'Оффер на 500к+ с бонусами'),
        ],
      ),
      GlobalGoal(
        id: 'g2',
        title: 'Спорт: Жим 100 кг и Полумарафон',
        category: 'Спорт и Тело',
        checkpoints: [
          GoalCheckpoint(title: 'Жим 90 кг на 5 повторов', isCompleted: true),
          GoalCheckpoint(title: 'Пробежать 10 км без остановки', isCompleted: true),
          GoalCheckpoint(title: 'Жим 100 кг на 1 раз'),
          GoalCheckpoint(title: 'Финиш полумарафона (21.1 км)'),
        ],
      ),
    ];

// ВАЖНО: список НЕ const — иначе insert()/remove() падали с UnsupportedError.
List<AchievementItem> defaultAchievements() => [
      const AchievementItem(id: 'a1', title: 'Подушка безопасности 1 000 000 ₽', date: 'Октябрь 2026', category: 'Финансы', iconKey: 'savings'),
      const AchievementItem(id: 'a2', title: 'Жим штанги лежа 95 кг', date: 'Сентябрь 2026', category: 'Сила', iconKey: 'fitness'),
      const AchievementItem(id: 'a3', title: 'Повышение до Lead Engineer', date: 'Август 2026', category: 'Карьера', iconKey: 'career'),
    ];

List<SalaryStep> defaultSalary() => [
      const SalaryStep(year: '2023', role: 'Junior', salary: 90000),
      const SalaryStep(year: '2024', role: 'Middle', salary: 180000),
      const SalaryStep(year: '2025', role: 'Senior', salary: 280000),
      const SalaryStep(year: '2026', role: 'Lead', salary: 380000),
    ];

List<GraphNode> defaultGraphNodes() => [
      GraphNode(id: 'n_goal_salary', label: 'Цель: 500к', category: 'mind', position: const Offset(0.22, 0.20), color: AppColors.violet),
      GraphNode(id: 'n_salary', label: 'ЗП: 380к', category: 'wealth', position: const Offset(0.53, 0.33), color: AppColors.green),
      GraphNode(id: 'n_capital', label: 'Капитал 2.45М', category: 'wealth', position: const Offset(0.78, 0.20), color: AppColors.gold),
      GraphNode(id: 'n_cushion', label: 'Подушка 1М', category: 'wealth', position: const Offset(0.84, 0.46), color: AppColors.gold),
      GraphNode(id: 'n_sleep', label: 'Сон / Отдых', category: 'health', position: const Offset(0.53, 0.56), color: Colors.cyanAccent),
      GraphNode(id: 'n_goal_bench', label: 'Цель: Жим 100', category: 'mind', position: const Offset(0.19, 0.75), color: AppColors.violet),
      GraphNode(id: 'n_chest', label: 'Грудь (1RM 120)', category: 'gym', position: const Offset(0.44, 0.86), color: AppColors.green),
      GraphNode(id: 'n_protein', label: 'Белок: 145г', category: 'health', position: const Offset(0.72, 0.74), color: Colors.cyanAccent),
      GraphNode(id: 'n_activity', label: 'Шаги: 8.4k', category: 'health', position: const Offset(0.84, 0.90), color: Colors.cyanAccent),
    ];

List<GraphEdge> defaultGraphEdges() => [
      GraphEdge('n_goal_salary', 'n_salary', kind: EdgeKind.supports, weight: 2),
      GraphEdge('n_salary', 'n_capital', kind: EdgeKind.supports, weight: 3),
      GraphEdge('n_capital', 'n_cushion', kind: EdgeKind.supports, weight: 2),
      GraphEdge('n_goal_bench', 'n_chest', kind: EdgeKind.supports, weight: 2),
      GraphEdge('n_chest', 'n_protein'),
      GraphEdge('n_protein', 'n_activity'),
      GraphEdge('n_sleep', 'n_chest', kind: EdgeKind.supports, weight: 2),
      GraphEdge('n_sleep', 'n_salary', kind: EdgeKind.supports),
    ];

// ---------------- чистый старт (новая установка) ----------------

/// Мышцы без истории: 12 групп, ни одной тренировки, нулевые рекорды.
Map<String, MuscleGroup> blankMuscles() {
  const names = {
    'delts': 'Дельтовидные',
    'chest': 'Грудные мышцы',
    'abs': 'Пресс и Кор',
    'biceps': 'Бицепс',
    'forearms': 'Предплечья',
    'quads': 'Квадрицепсы',
    'traps': 'Трапеции',
    'lats': 'Широчайшие спины',
    'triceps': 'Трицепс',
    'glutes': 'Ягодичные',
    'hamstrings': 'Бицепс бедра',
    'calves': 'Икроножные',
  };
  return {
    for (final e in names.entries)
      e.key: MuscleGroup(
        id: e.key,
        name: e.value,
        recoveryHours: MuscleGroup.defaultRecoveryHours[e.key] ?? 48,
        lastTrainedAt: null,
        baseTrainedAt: null,
        maxWeight: 0,
        lastSets: [],
        history1RM: [],
      ),
  };
}

/// Стартовый граф: только «живые» узлы, значения которых подставляются из данных.
List<GraphNode> blankGraphNodes() {
  GraphNode n(String id, String label, String category, double x, double y) =>
      GraphNode(id: id, label: label, category: category, position: Offset(x, y), color: nodeColorFor(category));
  return [
    n('n_salary', 'ЗП: 0к', 'wealth', 0.22, 0.20),
    n('n_capital', 'Капитал 0.00М', 'wealth', 0.76, 0.20),
    n('n_sleep', 'Сон / Отдых', 'health', 0.22, 0.56),
    n('n_chest', 'Грудь (1RM 0)', 'gym', 0.56, 0.62),
    n('n_protein', 'Белок: 0 г', 'health', 0.78, 0.80),
    n('n_activity', 'Шаги: 0.0k', 'health', 0.40, 0.88),
  ];
}

List<GraphEdge> blankGraphEdges() => [
      GraphEdge('n_salary', 'n_capital', kind: EdgeKind.supports, weight: 3),
      GraphEdge('n_sleep', 'n_chest', kind: EdgeKind.supports, weight: 2),
      GraphEdge('n_sleep', 'n_salary', kind: EdgeKind.supports),
      GraphEdge('n_chest', 'n_protein'),
      GraphEdge('n_protein', 'n_activity'),
    ];
