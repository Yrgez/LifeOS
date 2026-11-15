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

class LifeProcess {
  static const maxTitle = 120;
  static const maxDescription = 4000;
  static const maxLog = 1000;

  final String id;
  String title;
  String description;
  List<String> _dimensions;
  List<String> goalIds; // цели, которым служит процесс
  final DateTime createdAt;
  final List<ProcessStatusChange> statusLog; // по возрастанию времени, первая запись — начало процесса

  LifeProcess({
    required this.id,
    required this.title,
    this.description = '',
    required Iterable<String> dimensions,
    Iterable<String> goalIds = const [],
    required this.createdAt,
    required List<ProcessStatusChange> statusLog,
  })  : _dimensions = LifeEvent.normalizeDimensions(dimensions),
        goalIds = goalIds.toSet().toList(),
        statusLog = List.of(statusLog);

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
      statusLog.isNotEmpty &&
      statusLog.length <= maxLog &&
      statusLog.every((c) => c.isValid) &&
      _sorted(statusLog);

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
    final p = LifeProcess(
      id: id,
      title: title,
      description: desc,
      dimensions: dims.cast<String>(),
      goalIds: goals.cast<String>(),
      createdAt: ct,
      statusLog: log,
    );
    return p.isValid ? p : null;
  }
}
