// Процесс жизни: длительное направление усилий — «Изучение Java», «Набор массы», «Ремонт квартиры».
// Чистый Dart, без Flutter.
//
// Процесс не хранит собственных чисел: всё, что в него вложено, складывается из событий журнала,
// которые на него ссылаются (LifeEvent.processIds). Процесс — это рамка, а доказательства — события.
//
// Целостность истории: смена статуса не затирает прежний, а дописывается в [statusLog].

import 'life_event.dart';

const int _maxMs = 8640000000000000;

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
DateTime? _time(Object? v) {
  if (v is! num || !v.isFinite || v != v.roundToDouble() || v.abs() > _maxMs) return null;
  return DateTime.fromMillisecondsSinceEpoch(v.toInt());
}

/// Состояние процесса.
class ProcessStatus {
  static const active = 'active'; // идёт
  static const paused = 'paused'; // приостановлен (намерение вернуться)
  static const completed = 'completed'; // завершён: результат достигнут
  static const stopped = 'stopped'; // прекращён: решено не продолжать

  static const all = [active, paused, completed, stopped];
  static const labels = {active: 'Идёт', paused: 'На паузе', completed: 'Завершён', stopped: 'Прекращён'};
  static bool isValid(String s) => labels.containsKey(s);
  static bool isOpen(String s) => s == active || s == paused;
}

/// Запись о смене статуса: когда, на какой, почему (необязательно).
class ProcessStatusChange {
  static const maxNote = 1000;

  final DateTime at;
  final String status;
  final String note;
  const ProcessStatusChange({required this.at, required this.status, this.note = ''});

  bool get isValid => ProcessStatus.isValid(status) && note.length <= maxNote;

  Map<String, dynamic> toJson() => {'t': at.millisecondsSinceEpoch, 's': status, if (note.isNotEmpty) 'n': note};

  static ProcessStatusChange? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = _time(raw['t']);
    final s = raw['s'];
    final n = raw['n'] ?? '';
    if (at == null || s is! String || n is! String) return null;
    final c = ProcessStatusChange(at: at, status: s, note: n);
    return c.isValid ? c : null;
  }
}

/// Период ритма.
class RhythmPeriod {
  static const week = 'week';
  static const month = 'month';
  static const all = [week, month];
  static const maxTimes = {week: 7, month: 31};
  static const labels = {week: 'в неделю', month: 'в месяц'};
}

/// Запись журнала ритма: с момента [at] процесс задуман как [times] раз за [period].
/// [times] == 0 — ритм снят. Смена ритма дописывается, а не затирает прежний: прошлые недели
/// сверяются с тем ритмом, что действовал тогда.
class ProcessRhythm {
  final DateTime at;
  final int times;
  final String period;
  const ProcessRhythm({required this.at, required this.times, this.period = RhythmPeriod.week});

  bool get isSet => times > 0;
  bool get isValid => RhythmPeriod.all.contains(period) && times >= 0 && times <= RhythmPeriod.maxTimes[period]!;

  Map<String, dynamic> toJson() => {'t': at.millisecondsSinceEpoch, 'n': times, 'p': period};

  static ProcessRhythm? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = _time(raw['t']);
    final n = raw['n'];
    final p = raw['p'];
    if (at == null || n is! num || n != n.roundToDouble() || p is! String) return null;
    final r = ProcessRhythm(at: at, times: n.toInt(), period: p);
    return r.isValid ? r : null;
  }
}

class LifeProcess {
  static const maxTitle = 120;
  static const maxDescription = 4000;
  static const maxLog = 1000;

  final String id;
  String title;
  String description;
  List<String> _dimensions;
  List<String> goalIds; // цели, которым служит процесс
  int? defaultMinutes; // обычная длительность события процесса — подставляется при записи; null — не задана
  final DateTime createdAt;
  final List<ProcessStatusChange> statusLog; // по возрастанию времени, первая запись — начало процесса
  final List<ProcessRhythm> rhythmLog; // по возрастанию времени; пусто — ритм не задавался

  LifeProcess({
    required this.id,
    required this.title,
    this.description = '',
    required Iterable<String> dimensions,
    Iterable<String> goalIds = const [],
    this.defaultMinutes,
    required this.createdAt,
    required List<ProcessStatusChange> statusLog,
    List<ProcessRhythm> rhythmLog = const [],
  })  : _dimensions = LifeEvent.normalizeDimensions(dimensions),
        goalIds = goalIds.toSet().toList(),
        statusLog = List.of(statusLog),
        rhythmLog = List.of(rhythmLog);

  /// Текущий ритм; null — не задан или снят.
  ProcessRhythm? get rhythm => rhythmLog.isEmpty || !rhythmLog.last.isSet ? null : rhythmLog.last;

  /// Ритм, действовавший в момент [t]; null — не был задан.
  ProcessRhythm? rhythmAt(DateTime t) {
    ProcessRhythm? r;
    for (final x in rhythmLog) {
      if (x.at.isAfter(t)) break;
      r = x;
    }
    return r != null && r.isSet ? r : null;
  }

  /// Статус процесса в момент [t]; null — процесс ещё не начат.
  String? statusAt(DateTime t) {
    String? s;
    for (final c in statusLog) {
      if (c.at.isAfter(t)) break;
      s = c.status;
    }
    return s;
  }

  /// Шёл ли процесс в полуинтервале [from, to): на его конец статус «идёт» или «идёт» набралось
  /// хотя бы на сутки. Пауза с утра понедельника — неделя на паузе, а не «0 из 3».
  bool activeDuring(DateTime from, DateTime to) {
    if (statusAt(to.subtract(const Duration(milliseconds: 1))) == ProcessStatus.active) return true;
    var total = Duration.zero;
    for (var i = 0; i < statusLog.length; i++) {
      if (statusLog[i].status != ProcessStatus.active) continue;
      final start = statusLog[i].at.isBefore(from) ? from : statusLog[i].at;
      final rawEnd = i + 1 < statusLog.length ? statusLog[i + 1].at : to;
      final end = rawEnd.isAfter(to) ? to : rawEnd;
      if (end.isAfter(start)) total += end.difference(start);
    }
    return total >= const Duration(days: 1);
  }

  List<String> get dimensions => List.unmodifiable(_dimensions);
  set dimensions(Iterable<String> ds) => _dimensions = LifeEvent.normalizeDimensions(ds);

  String get status => statusLog.last.status;
  bool get isOpen => ProcessStatus.isOpen(status);
  DateTime get startedAt => statusLog.first.at;

  /// Когда процесс закрыт (завершён или прекращён); null — открыт.
  DateTime? get endedAt => isOpen ? null : statusLog.last.at;

  bool touches(String dimension) => _dimensions.contains(dimension);

  bool get isValid =>
      _str(id) != null &&
      title.trim().isNotEmpty &&
      title.length <= maxTitle &&
      description.length <= maxDescription &&
      _dimensions.isNotEmpty &&
      goalIds.length <= LifeEvent.maxLinks &&
      goalIds.every((g) => _str(g) != null) &&
      (defaultMinutes == null || (defaultMinutes! > 0 && defaultMinutes! <= ResourceCost.maxMinutes)) &&
      statusLog.isNotEmpty &&
      statusLog.length <= maxLog &&
      statusLog.every((c) => c.isValid) &&
      _sorted(statusLog) &&
      rhythmLog.length <= maxLog &&
      rhythmLog.every((r) => r.isValid) &&
      [for (var i = 1; i < rhythmLog.length; i++) !rhythmLog[i].at.isBefore(rhythmLog[i - 1].at)].every((x) => x);

  static bool _sorted(List<ProcessStatusChange> log) {
    for (var i = 1; i < log.length; i++) {
      if (log[i].at.isBefore(log[i - 1].at)) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (description.isNotEmpty) 'desc': description,
        'dims': _dimensions,
        if (goalIds.isNotEmpty) 'goals': goalIds,
        'ct': createdAt.millisecondsSinceEpoch,
        'log': statusLog.map((c) => c.toJson()).toList(),
        if (defaultMinutes != null) 'defMin': defaultMinutes,
        if (rhythmLog.isNotEmpty) 'rh': rhythmLog.map((r) => r.toJson()).toList(),
      };

  factory LifeProcess.fromJson(Map<String, dynamic> j) =>
      tryFromJson(j) ?? (throw const FormatException('LifeProcess'));

  /// null — запись нарушает инварианты (частично битый процесс не «чинится» молча).
  static LifeProcess? tryFromJson(Map<String, dynamic> j) {
    final id = _str(j['id']);
    final title = j['title'];
    final desc = j['desc'] ?? '';
    final dims = j['dims'];
    final goals = j['goals'] ?? const [];
    final ct = _time(j['ct']);
    final logRaw = j['log'];
    if (id == null || title is! String || desc is! String || ct == null) return null;
    if (dims is! List || !dims.every((d) => d is String && LifeDimension.isValid(d))) return null;
    if (goals is! List || !goals.every((g) => _str(g) != null)) return null;
    if (logRaw is! List) return null;
    final log = <ProcessStatusChange>[];
    for (final r in logRaw) {
      final c = ProcessStatusChange.tryFromJson(r);
      if (c == null) return null;
      log.add(c);
    }
    final rhRaw = j['rh'] ?? const [];
    if (rhRaw is! List) return null;
    final rh = <ProcessRhythm>[];
    for (final r in rhRaw) {
      final x = ProcessRhythm.tryFromJson(r);
      if (x == null) return null;
      rh.add(x);
    }
    final p = LifeProcess(
      id: id,
      title: title,
      description: desc,
      dimensions: dims.cast<String>(),
      goalIds: goals.cast<String>(),
      defaultMinutes: _defMin(j['defMin']),
      createdAt: ct,
      statusLog: log,
      rhythmLog: rh,
    );
    return p.isValid ? p : null;
  }
}

/// Обычная длительность из JSON: отсутствует — null; неверное значение — -1 (запись не пройдёт проверку, а не «починится»).
int? _defMin(Object? v) => v == null ? null : (v is num && v.isFinite && v == v.roundToDouble() ? v.toInt() : -1);
