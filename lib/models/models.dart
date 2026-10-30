import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';

class MuscleGroup {
  static const Map<String, double> defaultRecoveryHours = {
    'delts': 48, 'chest': 60, 'abs': 36, 'biceps': 48, 'forearms': 36, 'quads': 72,
    'traps': 48, 'lats': 72, 'triceps': 48, 'glutes': 72, 'hamstrings': 72, 'calves': 36,
  };

  final String id;
  final String name;
  final double recoveryHours; // за сколько часов мышца восстанавливается полностью
  DateTime? lastTrainedAt;
  double maxWeight;
  List<String> lastSets;

  /// БАЗОВАЯ история 1RM — то, что было до появления журнала подходов. Не меняется:
  /// дальнейшая прогрессия считается из журнала ([WorkoutSet]), поэтому удаление подхода ничего не ломает.
  final List<double> history1RM;

  /// Базовое состояние до журнала: от него отталкивается пересчёт после добавления/удаления подхода.
  final double baseMax;
  final DateTime? baseTrainedAt;
  final List<String> baseSets;

  MuscleGroup({
    required this.id,
    required this.name,
    required this.recoveryHours,
    required this.lastTrainedAt,
    required this.maxWeight,
    required this.lastSets,
    required this.history1RM,
    double? baseMax,
    DateTime? baseTrainedAt,
    List<String>? baseSets,
  })  : baseMax = baseMax ?? maxWeight,
        baseTrainedAt = baseTrainedAt ?? lastTrainedAt,
        baseSets = List<String>.of(baseSets ?? lastSets);

  /// Восстановление считается от времени последней тренировки (раньше было статичным числом).
  double get recovery => recoveryAt(DateTime.now());

  /// Восстановление на заданный момент (удобно для тестов и детерминированных расчётов).
  double recoveryAt(DateTime now) {
    final t = lastTrainedAt;
    if (t == null) return 1.0;
    final hours = now.difference(t).inMinutes / 60.0;
    return clampD(0.15 + 0.85 * hours / recoveryHours, 0.15, 1.0);
  }

  String get lastTrained {
    final t = lastTrainedAt;
    if (t == null) return 'Не тренировалась';
    final h = DateTime.now().difference(t).inHours;
    if (h < 1) return 'Только что';
    if (h < 24) return '$hч назад';
    return '${h ~/ 24} дн. назад';
  }

  Color get color {
    final r = recovery;
    if (r >= 0.8) return AppColors.green;
    if (r >= 0.45) return AppColors.amber;
    return AppColors.red;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'recoveryHours': recoveryHours,
        'lastTrainedAtMs': lastTrainedAt?.millisecondsSinceEpoch,
        'maxWeight': maxWeight,
        'lastSets': lastSets,
        'history1RM': history1RM,
        'baseMax': baseMax,
        'baseTrainedAtMs': baseTrainedAt?.millisecondsSinceEpoch,
        'baseSets': baseSets,
      };

  factory MuscleGroup.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final rh = (json['recoveryHours'] as num?)?.toDouble() ?? defaultRecoveryHours[id] ?? 48.0;
    DateTime? at;
    if (json['lastTrainedAtMs'] is int) {
      at = DateTime.fromMillisecondsSinceEpoch(json['lastTrainedAtMs'] as int);
    } else if (json['recovery'] is num) {
      // миграция со старого формата: восстанавливаем время тренировки из процента
      final r = (json['recovery'] as num).toDouble();
      final frac = clampD((r - 0.15) / 0.85, 0, 1);
      at = DateTime.now().subtract(Duration(minutes: (frac * rh * 60).round()));
    }
    final maxW = (json['maxWeight'] as num).toDouble();
    // Поля нет (очень старое сохранение) — база истории = текущий рекорд. Пустой список — норма
    // (мышца без истории после чистого старта) и остаётся пустым, иначе состояние «плывёт» при каждой загрузке.
    final rawHist = json['history1RM'];
    final hist = rawHist is List ? rawHist.map((e) => (e as num).toDouble()).toList() : <double>[maxW];
    return MuscleGroup(
      id: id,
      name: json['name'] as String,
      recoveryHours: rh,
      lastTrainedAt: at,
      maxWeight: maxW,
      lastSets: List<String>.from((json['lastSets'] as List?) ?? []),
      history1RM: hist,
      // старые сохранения без базового состояния: базой считается текущее
      baseMax: (json['baseMax'] as num?)?.toDouble(),
      baseTrainedAt: json['baseTrainedAtMs'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['baseTrainedAtMs'] as int)
          : null,
      baseSets: (json['baseSets'] as List?)?.map((e) => e.toString()).toList(),
    );
  }
}

/// Один подход в журнале. Объём (тоннаж) = вес × повторы.
class WorkoutSet {
  final String id;
  final String muscleId;
  final DateTime at;
  final double weight;
  final int reps;

  const WorkoutSet({
    required this.id,
    required this.muscleId,
    required this.at,
    required this.weight,
    required this.reps,
  });

  double get volume => weight * reps;

  /// Расчётный 1RM, округлённый до 0.1 кг.
  double get estimated1RM => round1(oneRM(weight, reps));

  String get label => '${trimNum(weight)}кг × $reps';

  Map<String, dynamic> toJson() => {
        'id': id,
        'm': muscleId,
        't': at.millisecondsSinceEpoch,
        'w': weight,
        'r': reps,
      };

  factory WorkoutSet.fromJson(Map<String, dynamic> j) => WorkoutSet(
        id: j['id'] as String,
        muscleId: j['m'] as String,
        at: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
        weight: (j['w'] as num).toDouble(),
        reps: (j['r'] as num).toInt(),
      );
}

/// Привязка чекпоинта к метрике: чекпоинт выполнен автоматически, пока значение метрики ≥ цели.
class MetricLink {
  static const oneRM = 'oneRM'; // расчётный рекорд 1RM по мышце (кг)
  static const netWorth = 'netWorth'; // чистый капитал (₽)
  static const income = 'income'; // доход в месяц (₽)

  final String kind;
  final String? muscleId; // только для oneRM
  final double target;

  const MetricLink({required this.kind, this.muscleId, required this.target});

  String get unit => kind == oneRM ? 'кг' : '₽';

  Map<String, dynamic> toJson() => {'kind': kind, 'muscleId': muscleId, 'target': target};

  factory MetricLink.fromJson(Map<String, dynamic> j) => MetricLink(
        kind: j['kind'] as String,
        muscleId: j['muscleId'] as String?,
        target: (j['target'] as num).toDouble(),
      );
}

class GoalCheckpoint {
  String title;
  bool isCompleted; // для чекпоинтов с [link] пересчитывается контроллером из метрики
  final MetricLink? link;
  GoalCheckpoint({required this.title, this.isCompleted = false, this.link});

  Map<String, dynamic> toJson() => {'title': title, 'isCompleted': isCompleted, 'link': link?.toJson()};
  factory GoalCheckpoint.fromJson(Map<String, dynamic> json) => GoalCheckpoint(
        title: json['title'] as String,
        isCompleted: json['isCompleted'] as bool? ?? false,
        link: json['link'] is Map ? MetricLink.fromJson(Map<String, dynamic>.from(json['link'] as Map)) : null,
      );
}

class GlobalGoal {
  final String id;
  String title;
  String category;
  DateTime? deadline; // только дата, без времени
  bool celebrated; // достижение за цель уже выдано (чтобы не создавать повторно / после ручного удаления)
  List<GoalCheckpoint> checkpoints;

  GlobalGoal({
    required this.id,
    required this.title,
    required this.category,
    required this.checkpoints,
    this.deadline,
    this.celebrated = false,
  });

  double get progress {
    if (checkpoints.isEmpty) return 0;
    return checkpoints.where((c) => c.isCompleted).length / checkpoints.length;
  }

  bool get isComplete => checkpoints.isNotEmpty && progress == 1.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'deadlineMs': deadline?.millisecondsSinceEpoch,
        'celebrated': celebrated,
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
      };

  factory GlobalGoal.fromJson(Map<String, dynamic> json) {
    final g = GlobalGoal(
      id: json['id'] as String,
      title: json['title'] as String,
      category: json['category'] as String,
      deadline: json['deadlineMs'] is int ? DateTime.fromMillisecondsSinceEpoch(json['deadlineMs'] as int) : null,
      checkpoints: (json['checkpoints'] as List).map((c) => GoalCheckpoint.fromJson(Map<String, dynamic>.from(c as Map))).toList(),
    );
    // старые сохранения: уже выполненная цель считается отпразднованной (достижение уже есть или удалено вручную)
    g.celebrated = json['celebrated'] as bool? ?? g.isComplete;
    return g;
  }
}

class AchievementItem {
  final String id;
  final String title;
  final String date;
  final String category;
  final String iconKey;

  const AchievementItem({
    required this.id,
    required this.title,
    required this.date,
    required this.category,
    this.iconKey = 'star',
  });

  IconData get icon {
    switch (iconKey) {
      case 'savings':
        return Icons.savings;
      case 'fitness':
        return Icons.fitness_center;
      case 'career':
        return Icons.trending_up;
      case 'verified':
        return Icons.verified;
      default:
        return Icons.stars;
    }
  }

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'date': date, 'category': category, 'iconKey': iconKey};

  factory AchievementItem.fromJson(Map<String, dynamic> json) => AchievementItem(
        id: json['id'] as String,
        title: json['title'] as String,
        date: json['date'] as String,
        category: json['category'] as String,
        iconKey: json['iconKey'] as String? ?? 'star',
      );
}

class SalaryStep {
  final String year;
  final String role;
  final int salary;

  const SalaryStep({required this.year, required this.role, required this.salary});

  Map<String, dynamic> toJson() => {'year': year, 'role': role, 'salary': salary};
  factory SalaryStep.fromJson(Map<String, dynamic> json) => SalaryStep(
        year: json['year'] as String,
        role: json['role'] as String,
        salary: (json['salary'] as num).toInt(),
      );
}

/// Цвет узла по сфере жизни.
Color nodeColorFor(String category) {
  switch (category) {
    case 'wealth':
      return AppColors.gold;
    case 'gym':
      return AppColors.green;
    case 'health':
      return const Color(0xFF18FFFF); // Colors.cyanAccent
    default:
      return AppColors.violet;
  }
}

class GraphNode {
  final String id;
  String label;
  String category;
  Offset position; // ДОЛИ холста (0..1), а не пиксели — граф не «вылезает» на других экранах
  Color color;

  GraphNode({required this.id, required this.label, required this.category, required this.position, required this.color});

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'category': category,
        'fx': position.dx,
        'fy': position.dy,
        'color': color.toARGB32(),
      };

  factory GraphNode.fromJson(Map<String, dynamic> j) {
    double fx, fy;
    if (j['fx'] is num) {
      fx = (j['fx'] as num).toDouble();
      fy = (j['fy'] as num).toDouble();
    } else {
      // миграция со старого формата (пиксели)
      fx = ((j['dx'] as num?)?.toDouble() ?? 180) / 360;
      fy = ((j['dy'] as num?)?.toDouble() ?? 240) / 480;
    }
    return GraphNode(
      id: j['id'] as String,
      label: j['label'] as String,
      category: j['category'] as String? ?? 'mind',
      position: Offset(clampD(fx, 0.06, 0.94), clampD(fy, 0.06, 0.94)),
      color: Color(j['color'] as int? ?? 0xFF00E676),
    );
  }
}

/// Тип связи между узлами графа.
class EdgeKind {
  static const related = 'related'; // просто связаны (без направления)
  static const supports = 'supports'; // A помогает B (направленная)
  static const conflicts = 'conflicts'; // A мешает B (направленная)

  static const labels = {related: 'Связаны', supports: 'Помогает', conflicts: 'Мешает'};
  static bool isValid(String k) => labels.containsKey(k);
  static bool isDirected(String k) => k != related;
}

class GraphEdge {
  final String fromId;
  final String toId;
  final String kind;
  final int weight; // сила связи 1..3

  const GraphEdge(this.fromId, this.toId, {this.kind = EdgeKind.related, this.weight = 1});

  /// Ключ связи для выбора и правок (направление учитывается).
  String get key => '$fromId>$toId';

  GraphEdge copyWith({String? kind, int? weight}) =>
      GraphEdge(fromId, toId, kind: kind ?? this.kind, weight: weight ?? this.weight);

  Map<String, dynamic> toJson() => {'fromId': fromId, 'toId': toId, 'kind': kind, 'weight': weight};

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    final k = json['kind'] as String?;
    return GraphEdge(
      (json['fromId'] as String?) ?? '',
      (json['toId'] as String?) ?? '',
      kind: (k != null && EdgeKind.isValid(k)) ? k : EdgeKind.related,
      weight: clampI((json['weight'] as num?)?.toInt() ?? 1, 1, 3),
    );
  }
}


/// Денежная операция. Сумма всегда положительная, знак задаёт [isIncome].
class MoneyTx {
  final String id;
  final DateTime at;
  final bool isIncome;
  final int amount; // ₽
  final String categoryId;
  final String note;

  /// Изменяла ли операция чистый капитал при добавлении (нужно, чтобы удаление откатило ровно то же).
  final bool affectsNetWorth;

  /// Создана правилом повторяющейся операции (id правила); null — введена вручную.
  final String? recurringId;

  const MoneyTx({
    required this.id,
    required this.at,
    required this.isIncome,
    required this.amount,
    required this.categoryId,
    this.note = '',
    this.affectsNetWorth = true,
    this.recurringId,
  });

  int get signed => isIncome ? amount : -amount;

  Map<String, dynamic> toJson() => {
        'id': id,
        't': at.millisecondsSinceEpoch,
        'in': isIncome,
        'a': amount,
        'c': categoryId,
        'n': note,
        'nw': affectsNetWorth,
        'rid': recurringId,
      };

  factory MoneyTx.fromJson(Map<String, dynamic> j) => MoneyTx(
        id: j['id'] as String,
        at: DateTime.fromMillisecondsSinceEpoch((j['t'] as num).toInt()),
        isIncome: j['in'] as bool,
        amount: (j['a'] as num).toInt(),
        categoryId: j['c'] as String,
        note: j['n'] as String? ?? '',
        affectsNetWorth: j['nw'] as bool? ?? true,
        recurringId: j['rid'] as String?,
      );
}


/// Правило повторяющейся операции: каждый месяц в [dayOfMonth]-е число (в коротких месяцах — в последний день).
class RecurringTx {
  final String id;
  final String categoryId;
  final int amount;
  final int dayOfMonth; // 1..31
  final String note;
  final bool affectsNetWorth;
  final DateTime start; // первая операция — не раньше этой даты
  String lastMonth; // «гггг-мм» последнего обработанного месяца; пусто — ничего не создавалось

  RecurringTx({
    required this.id,
    required this.categoryId,
    required this.amount,
    required this.dayOfMonth,
    required this.start,
    this.note = '',
    this.affectsNetWorth = true,
    this.lastMonth = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'c': categoryId,
        'a': amount,
        'd': dayOfMonth,
        'n': note,
        'nw': affectsNetWorth,
        's': start.millisecondsSinceEpoch,
        'lm': lastMonth,
      };

  factory RecurringTx.fromJson(Map<String, dynamic> j) => RecurringTx(
        id: j['id'] as String,
        categoryId: j['c'] as String,
        amount: (j['a'] as num).toInt(),
        dayOfMonth: clampI((j['d'] as num).toInt(), 1, 31),
        note: j['n'] as String? ?? '',
        affectsNetWorth: j['nw'] as bool? ?? true,
        start: DateTime.fromMillisecondsSinceEpoch((j['s'] as num).toInt()),
        lastMonth: j['lm'] as String? ?? '',
      );
}
