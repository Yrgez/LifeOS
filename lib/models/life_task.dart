// Задача — намерение на будущее: «записаться к стоматологу», «сдать отчёт». Чистый Dart, без Flutter.
//
// Задача не факт, поэтому в журнал событий не пишется. Факт появляется при выполнении: «Сделано» создаёт
// обычное событие со ссылкой на задачу — ресурсы, процессы и цели считаются уже по нему.
// История задачи не переписывается: постановка, переносы, выполнение, отмена — дописываются в [log].

import 'day_snapshot.dart' show isValidDayKey;
import 'life_event.dart';

class TaskStep {
  static const created = 'created';
  static const planned = 'planned'; // назначен (перенесён) день; day == null — «без даты»
  static const done = 'done';
  static const cancelled = 'cancelled';
  static const reopened = 'reopened';
  static const all = {created, planned, done, cancelled, reopened};
}

class TaskChange {
  final DateTime at;
  final String step;
  final String? day; // для planned: новый день (yyyy-MM-dd) или null — без даты
  final String? eventId; // для done: событие выполнения
  const TaskChange({required this.at, required this.step, this.day, this.eventId});

  bool get isValid => TaskStep.all.contains(step) && (day == null || isValidDayKey(day!));

  Map<String, dynamic> toJson() => {
        't': at.millisecondsSinceEpoch,
        's': step,
        if (day != null) 'd': day,
        if (eventId != null) 'e': eventId,
      };

  static TaskChange? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final t = raw['t'], s = raw['s'], d = raw['d'], e = raw['e'];
    if (t is! num || !t.isFinite || s is! String || (d != null && d is! String) || (e != null && e is! String)) return null;
    final c = TaskChange(at: DateTime.fromMillisecondsSinceEpoch(t.toInt()), step: s, day: d as String?, eventId: e as String?);
    return c.isValid ? c : null;
  }
}

enum TaskStatus { open, done, cancelled }

class LifeTask {
  static const maxTitle = 160;
  static const maxNote = 1000;
  static const maxLog = 500;

  final String id;
  String title;
  String note;
  List<String> _dimensions;
  String? processId;
  String? goalId;
  int? minutes; // примерная длительность — оценка, а не факт
  final List<TaskChange> log; // по возрастанию времени, первая запись — created

  LifeTask({
    required this.id,
    required this.title,
    this.note = '',
    required Iterable<String> dimensions,
    this.processId,
    this.goalId,
    this.minutes,
    required List<TaskChange> log,
  })  : _dimensions = LifeEvent.normalizeDimensions(dimensions),
        log = List.of(log);

  List<String> get dimensions => List.unmodifiable(_dimensions);
  set dimensions(Iterable<String> ds) => _dimensions = LifeEvent.normalizeDimensions(ds);

  DateTime get createdAt => log.first.at;

  /// Текущий день задачи (последнее назначение); null — без даты.
  String? get day {
    String? d;
    for (final c in log) {
      if (c.step == TaskStep.created || c.step == TaskStep.planned) d = c.day;
    }
    return d;
  }

  TaskStatus get status {
    for (final c in log.reversed) {
      if (c.step == TaskStep.done) return TaskStatus.done;
      if (c.step == TaskStep.cancelled) return TaskStatus.cancelled;
      if (c.step == TaskStep.reopened || c.step == TaskStep.created) return TaskStatus.open;
    }
    return TaskStatus.open;
  }

  bool get isOpen => status == TaskStatus.open;

  /// Последнее выполнение (запись done), если задача сейчас выполнена.
  TaskChange? get doneChange => status == TaskStatus.done ? log.lastWhere((c) => c.step == TaskStep.done) : null;

  /// Сколько раз день переносили (после постановки) — факт, без оценки.
  int get postponed => log.where((c) => c.step == TaskStep.planned).length;

  bool get isValid =>
      id.trim().isNotEmpty &&
      title.trim().isNotEmpty &&
      title.length <= maxTitle &&
      note.length <= maxNote &&
      _dimensions.isNotEmpty &&
      (minutes == null || (minutes! > 0 && minutes! <= ResourceCost.maxMinutes)) &&
      log.isNotEmpty &&
      log.length <= maxLog &&
      log.first.step == TaskStep.created &&
      log.every((c) => c.isValid) &&
      [for (var i = 1; i < log.length; i++) !log[i].at.isBefore(log[i - 1].at)].every((x) => x);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (note.isNotEmpty) 'note': note,
        'dims': _dimensions,
        if (processId != null) 'proc': processId,
        if (goalId != null) 'goal': goalId,
        if (minutes != null) 'min': minutes,
        'log': log.map((c) => c.toJson()).toList(),
      };

  factory LifeTask.fromJson(Map<String, dynamic> j) => tryFromJson(j) ?? (throw const FormatException('LifeTask'));

  static LifeTask? tryFromJson(Map<String, dynamic> j) {
    final id = j['id'], title = j['title'], note = j['note'] ?? '', dims = j['dims'], proc = j['proc'], goal = j['goal'], min = j['min'], raw = j['log'];
    if (id is! String || title is! String || note is! String || dims is! List || raw is! List) return null;
    if (!dims.every((d) => d is String && LifeDimension.isValid(d))) return null;
    if ((proc != null && proc is! String) || (goal != null && goal is! String)) return null;
    if (min != null && (min is! num || min != min.roundToDouble())) return null;
    final log = <TaskChange>[];
    for (final r in raw) {
      final c = TaskChange.tryFromJson(r);
      if (c == null) return null;
      log.add(c);
    }
    final t = LifeTask(
      id: id,
      title: title,
      note: note,
      dimensions: dims.cast<String>(),
      processId: proc as String?,
      goalId: goal as String?,
      minutes: (min as num?)?.toInt(),
      log: log,
    );
    return t.isValid ? t : null;
  }
}
