import '../models/life_event.dart';
import '../models/life_process.dart';
import 'life_events.dart';

/// Факт по цели (FUTURE ↔ PAST): что уже вложено в цель — по событиям, связанным с ней напрямую
/// или через процессы, которые ей служат. Каждое событие учитывается один раз. Чистая логика без Flutter.
class GoalFact {
  final ResourceSummary resources;
  final int direct; // событий, связанных с целью напрямую
  final int viaProcess; // событий, попавших только через процесс
  final List<String> processIds; // процессы, служащие цели (в порядке списка процессов)
  final List<String> dimensions; // измерения, которых касаются события цели (выводятся, а не вводятся)
  final DateTime? firstAt;
  final DateTime? lastAt;

  const GoalFact({
    required this.resources,
    required this.direct,
    required this.viaProcess,
    required this.processIds,
    required this.dimensions,
    this.firstAt,
    this.lastAt,
  });
}

/// События цели: напрямую (goalIds) или через процесс, служащий цели (process.goalIds).
List<LifeEvent> goalEvents(String goalId, List<LifeEvent> current, List<LifeProcess> processes) {
  final serving = {for (final p in processes) if (p.goalIds.contains(goalId)) p.id};
  return [
    for (final e in current)
      if (e.goalIds.contains(goalId) || e.processIds.any(serving.contains)) e,
  ];
}

GoalFact goalFact(String goalId, List<LifeEvent> current, List<LifeProcess> processes) {
  final events = goalEvents(goalId, current, processes);
  var direct = 0;
  final dims = <String>{};
  DateTime? first, last;
  for (final e in events) {
    if (e.goalIds.contains(goalId)) direct++;
    dims.addAll(e.dimensions);
    if (first == null || e.at.isBefore(first)) first = e.at;
    if (last == null || e.at.isAfter(last)) last = e.at;
  }
  return GoalFact(
    resources: summarizeEvents(events),
    direct: direct,
    viaProcess: events.length - direct,
    processIds: [for (final p in processes) if (p.goalIds.contains(goalId)) p.id],
    dimensions: LifeEvent.normalizeDimensions(dims),
    firstAt: first,
    lastAt: last,
  );
}
