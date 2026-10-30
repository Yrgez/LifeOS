import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/utils.dart';

// ---------------- безопасный разбор JSON ----------------

const int _maxMs = 8640000000000000; // предел DateTime.fromMillisecondsSinceEpoch

String? _id(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
double? _d(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
int? _i(Object? v) => v is num && v.isFinite ? v.toInt() : null;

DateTime? _dt(Object? v) {
  final ms = _i(v);
  if (ms == null || ms.abs() > _maxMs) return null;
  return DateTime.fromMillisecondsSinceEpoch(ms);
}

/// Разбирает список записей: битые (null или исключение) пропускает и сообщает в [onSkip].
/// В загрузчике передайте `onSkip: AppLog.<ваш метод записи>`; по умолчанию — debugPrint.
List<T> parseList<T>(
  Object? raw,
  T? Function(Map<String, dynamic>) parse,
  String tag, {
  void Function(String)? onSkip,
}) {
  final log = onSkip ?? (m) => debugPrint(m);
  final out = <T>[];
  if (raw is! List) {
    if (raw != null) log('parse[$tag]: ожидался список');
    return out;
  }
  for (var i = 0; i < raw.length; i++) {
    T? v;
    try {
      final e = raw[i];
      v = e is Map ? parse(Map<String, dynamic>.from(e)) : null;
    } catch (err) {
      v = null;
    }
    if (v == null) {
      log('parse[$tag]: запись #$i пропущена');
    } else {
      out.add(v);
    }
  }
  return out;
}

/// Связи: отбрасывает петли, дубли и (если передан [nodeIds]) связи с несуществующими узлами.
/// Для «Связаны» направление не важно (A–B == B–A), для направленных учитывается.
List<GraphEdge> parseEdges(Object? raw, {Set<String>? nodeIds, void Function(String)? onSkip}) {
  final log = onSkip ?? (m) => debugPrint(m);
  final seen = <String>{};
  final out = <GraphEdge>[];
  for (final e in parseList(raw, GraphEdge.tryFromJson, 'edge', onSkip: onSkip)) {
    if (nodeIds != null && (!nodeIds.contains(e.fromId) || !nodeIds.contains(e.toId))) {
      log('parse[edge]: связь ${e.key} ведёт к несуществующему узлу');
      continue;
    }
    final k = EdgeKind.isDirected(e.kind)
        ? 'd:${e.key}'
        : 'r:${e.fromId.compareTo(e.toId) < 0 ? '${e.fromId}|${e.toId}' : '${e.toId}|${e.fromId}'}';
    if (!seen.add(k)) {
      log('parse[edge]: дубль связи ${e.key}');
      continue;
    }
    out.add(e);
  }
  return out;
}

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
    this.baseTrainedAt,
    List<String>? baseSets,
  })  : baseMax = baseMax ?? maxWeight,
        baseSets = List<String>.of(baseSets ?? lastSets);

  /// Восстановление считается от времени последней тренировки.
  double get recovery => recoveryAt(DateTime.now());

  /// Восстановление на заданный момент (удобно для тестов и детерминированных расчётов).
  double recoveryAt(DateTime now) {
    if (recoveryHours <= 0) return 1.0;
    final t = lastTrainedAt;
    if (t == null) return 1.0;
    final hours = now.difference(t).inMinutes / 60.0;
    return clampD(0.15 + 0.85 * hours / recoveryHours, 0.15, 1.0);
  }

  String get lastTrained => lastTrainedOn(DateTime.now());

  /// Детерминированный текст для тестов и снапшотов.
  String lastTrainedOn(DateTime now) {
    final t = lastTrainedAt;
    if (t == null) return 'Не тренировалась';
    final h = now.difference(t).inHours;
    if (h < 1) return 'Только что';
    if (h < 24) return '${h}ч назад';
    return '${h ~/ 24} дн. назад';
  }

  Color get color => colorAt(DateTime.now());

  /// Детерминированный цвет для тестов.
  Color colorAt(DateTime now) {
    final r = recoveryAt(now);
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
        'lastSets': List<String>.of(lastSets),
        'history1RM': List<double>.of(history1RM),
        'baseMax': baseMax,
        'baseTrainedAtMs': baseTrainedAt?.millisecondsSinceEpoch,
        'baseSets': List<String>.of(baseSets),
      };

  /// Строгий вариант: бросает [FormatException] на битой записи. Для загрузки списков используйте [tryFromJson].
  factory MuscleGroup.fromJson(Map<String, dynamic> json) =>
      tryFromJson(json) ?? (throw const FormatException('MuscleGroup'));

  /// null — запись непригодна (нет id).
  static MuscleGroup? tryFromJson(Map<String, dynamic> json) {
    final id = _id(json['id']);
    if (id == null) return null;
    final rhRaw = _d(json['recoveryHours']);
    final rh = (rhRaw != null && rhRaw > 0) ? rhRaw : (defaultRecoveryHours[id] ?? 48.0);

    DateTime? at = _dt(json['lastTrainedAtMs']);
    final oldRecovery = _d(json['recovery']);
    if (at == null && oldRecovery != null) {
      // миграция со старого формата: восстанавливаем время тренировки из процента
      final frac = clampD((oldRecovery - 0.15) / 0.85, 0, 1);
      at = DateTime.now().subtract(Duration(minutes: (frac * rh * 60).round()));
    }

    final maxW = _d(json['maxWeight']) ?? 0.0;
    // Поля нет (очень старое сохранение) — база истории = текущий рекорд. Пустой список — норма
    // (мышца без истории после чистого старта) и остаётся пустым, иначе состояние «плывёт» при каждой загрузке.
    final rawHist = json['history1RM'];
    final hist = rawHist is List
        ? rawHist.map(_d).whereType<double>().toList()
        : <double>[maxW];

    final hasBase = json.containsKey('baseTrainedAtMs') || json.containsKey('baseMax');
    final baseAt = _dt(json['baseTrainedAtMs']) ?? (hasBase ? null : at);

    return MuscleGroup(
      id: id,
      name: json['name'] is String ? json['name'] as String : id,
      recoveryHours: rh,
      lastTrainedAt: at,
      maxWeight: maxW,
      lastSets: ((json['lastSets'] as List?) ?? const []).map((e) => e.toString()).toList(),
      history1RM: hist,
      // null → конструктор возьмёт текущий maxWeight (старые сохранения без базового состояния)
      baseMax: _d(json['baseMax']),
      baseTrainedAt: baseAt,
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

  factory WorkoutSet.fromJson(Map<String, dynamic> j) =>
      tryFromJson(j) ?? (throw const FormatException('WorkoutSet'));

  /// null — нет id/мышцы/времени, либо вес или повторы не положительные.
  static WorkoutSet? tryFromJson(Map<String, dynamic> j) {
    final id = _id(j['id']);
    final m = _id(j['m']);
    final at = _dt(j['t']);
    final w = _d(j['w']);
    final r = _i(j['r']);
    if (id == null || m == null || at == null || w == null || r == null || w <= 0 || r <= 0) return null;
    return WorkoutSet(id: id, muscleId: m, at: at, weight: w, reps: r);
  }
}

/// Привязка чекпоинта к метрике: чекпоинт выполнен автоматически, пока значение метрики ≥ цели.
class MetricLink {
  static const oneRM = 'oneRM'; // расчётный рекорд 1RM по мышце (кг)
  static const netWorth = 'netWorth'; // чистый капитал (₽)
  static const income = 'income'; // доход в месяц (₽)
  static const _kinds = {oneRM, netWorth, income};

  final String kind;
  final String? muscleId; // только для oneRM
  final double target;

  const MetricLink({required this.kind, this.muscleId, required this.target});

  String get unit => kind == oneRM ? 'кг' : '₽';

  Map<String, dynamic> toJson() => {'kind': kind, 'muscleId': muscleId, 'target': target};

  factory MetricLink.fromJson(Map<String, dynamic> j) =>
      tryFromJson(j) ?? (throw const FormatException('MetricLink'));

  /// null — неизвестный вид метрики, нет цели, либо oneRM без мышцы.
  static MetricLink? tryFromJson(Map<String, dynamic> j) {
    final kind = j['kind'];
    final target = _d(j['target']);
    if (kind is! String || !_kinds.contains(kind) || target == null) return null;
    final muscle = j['muscleId'] is String ? j['muscleId'] as String : null;
    if (kind == oneRM && _id(muscle) == null) return null;
    return MetricLink(kind: kind, muscleId: muscle, target: target);
  }
}

class GoalCheckpoint {
  String title;
  bool isCompleted; // для чекпоинтов с [link] пересчитывается контроллером из метрики
  final MetricLink? link;
  GoalCheckpoint({required this.title, this.isCompleted = false, this.link});

  Map<String, dynamic> toJson() => {'title': title, 'isCompleted': isCompleted, 'link': link?.toJson()};

  factory GoalCheckpoint.fromJson(Map<String, dynamic> json) =>
      tryFromJson(json) ?? (throw const FormatException('GoalCheckpoint'));

  /// null — нет названия, либо привязка к метрике есть, но битая
  /// (молча превращать такой чекпоинт в ручной нельзя: пропадёт автоматика).
  static GoalCheckpoint? tryFromJson(Map<String, dynamic> json) {
    final title = json['title'];
    if (title is! String) return null;
    MetricLink? link;
    final rawLink = json['link'];
    if (rawLink != null) {
      if (rawLink is! Map) return null;
      link = MetricLink.tryFromJson(Map<String, dynamic>.from(rawLink));
      if (link == null) return null;
    }
    return GoalCheckpoint(title: title, isCompleted: json['isCompleted'] as bool? ?? false, link: link);
  }
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

  factory GlobalGoal.fromJson(Map<String, dynamic> json) =>
      tryFromJson(json) ?? (throw const FormatException('GlobalGoal'));

  /// null — нет id или названия. Битые чекпоинты пропускаются по отдельности.
  static GlobalGoal? tryFromJson(Map<String, dynamic> json, {void Function(String)? onSkip}) {
    final id = _id(json['id']);
    final title = json['title'];
    if (id == null || title is! String) return null;
    final g = GlobalGoal(
      id: id,
      title: title,
      category: json['category'] as String? ?? 'Стратегия',
      deadline: _dt(json['deadlineMs']),
      checkpoints: parseList(json['checkpoints'], GoalCheckpoint.tryFromJson, 'checkpoint', onSkip: onSkip),
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

  factory AchievementItem.fromJson(Map<String, dynamic> json) =>
      tryFromJson(json) ?? (throw const FormatException('AchievementItem'));

  /// null — нет id или названия.
  static AchievementItem? tryFromJson(Map<String, dynamic> json) {
    final id = _id(json['id']);
    final title = json['title'];
    if (id == null || title is! String) return null;
    return AchievementItem(
      id: id,
      title: title,
      date: json['date']?.toString() ?? '',
      category: json['category'] as String? ?? '',
      iconKey: json['iconKey'] as String? ?? 'star',
    );
  }
}

class SalaryStep {
  final String year;
  final String role;
  final int salary;

  const SalaryStep({required this.year, required this.role, required this.salary});

  Map<String, dynamic> toJson() => {'year': year, 'role': role, 'salary': salary};

  factory SalaryStep.fromJson(Map<String, dynamic> json) =>
      tryFromJson(json) ?? (throw const FormatException('SalaryStep'));

  /// null — нет года или зарплата не число / отрицательная.
  static SalaryStep? tryFromJson(Map<String, dynamic> json) {
    final year = json['year']?.toString();
    final salary = _i(json['salary']);
    if (year == null || year.isEmpty || salary == null || salary < 0) return null;
    return SalaryStep(year: year, role: json['role'] as String? ?? '', salary: salary);
  }
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

  /// Пользовательский цвет; null — цвет берётся из категории и не рассинхронизируется при её смене.
  Color? _override;

  GraphNode({
    required this.id,
    required this.label,
    required this.category,
    required this.position,
    Color? color,
  }) {
    _override = (color == null || color == nodeColorFor(category)) ? null : color;
  }

  Color get color => _override ?? nodeColorFor(category);

  set color(Color c) => _override = c == nodeColorFor(category) ? null : c;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'category': category,
        'fx': position.dx,
        'fy': position.dy,
        'color': color.toARGB32(),
      };

  factory GraphNode.fromJson(Map<String, dynamic> j) =>
      tryFromJson(j) ?? (throw const FormatException('GraphNode'));

  /// null — нет id.
  static GraphNode? tryFromJson(Map<String, dynamic> j) {
    final id = _id(j['id']);
    if (id == null) return null;
    double fx, fy;
    final jx = _d(j['fx']);
    final jy = _d(j['fy']);
    if (jx != null && jy != null) {
      fx = jx;
      fy = jy;
    } else {
      // миграция со старого формата (пиксели)
      fx = (_d(j['dx']) ?? 180) / 360;
      fy = (_d(j['dy']) ?? 240) / 480;
    }
    final cat = j['category'] as String? ?? 'mind';
    final rawColor = _i(j['color']);
    return GraphNode(
      id: id,
      label: j['label'] as String? ?? '',
      category: cat,
      position: Offset(clampD(fx, 0.06, 0.94), clampD(fy, 0.06, 0.94)),
      color: rawColor == null ? null : Color(rawColor & 0xFFFFFFFF),
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

  factory GraphEdge.fromJson(Map<String, dynamic> json) =>
      tryFromJson(json) ?? (throw const FormatException('GraphEdge'));

  /// null — пустой конец или петля (A→A). Дубли и «висячие» связи отсекает [parseEdges].
  static GraphEdge? tryFromJson(Map<String, dynamic> json) {
    final from = _id(json['fromId']);
    final to = _id(json['toId']);
    if (from == null || to == null || from == to) return null;
    final k = json['kind'];
    return GraphEdge(
      from,
      to,
      kind: (k is String && EdgeKind.isValid(k)) ? k : EdgeKind.related,
      weight: clampI(_i(json['weight']) ?? 1, 1, 3),
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

  factory MoneyTx.fromJson(Map<String, dynamic> j) =>
      tryFromJson(j) ?? (throw const FormatException('MoneyTx'));

  /// null — нет id, даты, типа (доход/расход) или положительной суммы.
  static MoneyTx? tryFromJson(Map<String, dynamic> j) {
    final id = _id(j['id']);
    final at = _dt(j['t']);
    final amount = _i(j['a']);
    final isIncome = j['in'];
    if (id == null || at == null || amount == null || amount <= 0 || isIncome is! bool) return null;
    return MoneyTx(
      id: id,
      at: at,
      isIncome: isIncome,
      amount: amount,
      categoryId: j['c'] as String? ?? '',
      note: j['n'] as String? ?? '',
      affectsNetWorth: j['nw'] as bool? ?? true,
      recurringId: j['rid'] as String?,
    );
  }
}

/// Правило повторяющейся операции: каждый месяц в [dayOfMonth]-е число (в коротких месяцах — в последний день).
class RecurringTx {
  static final _monthRe = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');

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

  factory RecurringTx.fromJson(Map<String, dynamic> j) =>
      tryFromJson(j) ?? (throw const FormatException('RecurringTx'));

  /// null — нет id, даты старта, суммы или дня, либо битый lastMonth.
  /// Битый lastMonth нельзя заменять на '' — правило заново создаст операции за все прошлые месяцы.
  static RecurringTx? tryFromJson(Map<String, dynamic> j) {
    final id = _id(j['id']);
    final start = _dt(j['s']);
    final amount = _i(j['a']);
    final day = _i(j['d']);
    final lm = j['lm'] ?? '';
    if (id == null || start == null || amount == null || amount <= 0 || day == null) return null;
    if (lm is! String || (lm.isNotEmpty && !_monthRe.hasMatch(lm))) return null;
    return RecurringTx(
      id: id,
      categoryId: j['c'] as String? ?? '',
      amount: amount,
      dayOfMonth: clampI(day, 1, 31),
      note: j['n'] as String? ?? '',
      affectsNetWorth: j['nw'] as bool? ?? true,
      start: start,
      lastMonth: lm,
    );
  }
}
