import '../models/life_event.dart';

/// Чтение журнала событий: актуальные версии, история версий, сводка ресурсов. Чистая логика без Flutter.

/// Актуальные события: не отменены и не заменены более новой версией. Порядок — по времени события.
List<LifeEvent> currentEvents(List<LifeEvent> events) {
  final replaced = {for (final e in events) if (e.supersedesId != null) e.supersedesId!};
  return [for (final e in events) if (!e.isVoided && !replaced.contains(e.id)) e];
}

/// Все версии события, от первой к последней (по любой версии цепочки).
List<LifeEvent> revisionChain(List<LifeEvent> events, String id) {
  final byId = {for (final e in events) e.id: e};
  final nextOf = {for (final e in events) if (e.supersedesId != null) e.supersedesId!: e.id};
  var first = byId[id];
  if (first == null) return const [];
  final guard = <String>{};
  while (first!.supersedesId != null && byId.containsKey(first.supersedesId) && guard.add(first.id)) {
    first = byId[first.supersedesId]!;
  }
  final out = <LifeEvent>[first];
  final seen = {first.id};
  var next = nextOf[first.id];
  while (next != null && seen.add(next)) {
    out.add(byId[next]!);
    next = nextOf[next];
  }
  return out;
}

/// Последняя версия цепочки, к которой относится [id] (null — нет такого события).
LifeEvent? latestRevision(List<LifeEvent> events, String id) {
  final chain = revisionChain(events, id);
  return chain.isEmpty ? null : chain.last;
}

/// Сводка ресурсов по измерению за период. Никаких индексов и средних по субъективной шкале:
/// только суммы известных значений и честный счёт того, где значение не указано.
class ResourceSummary {
  final int events;
  final int minutes;
  final int minutesKnown; // в скольких событиях время указано
  final int money;
  final int moneyKnown;
  final Map<int, int> energy; // оценка 1–5 → число событий
  const ResourceSummary({
    required this.events,
    required this.minutes,
    required this.minutesKnown,
    required this.money,
    required this.moneyKnown,
    required this.energy,
  });

  int get energyKnown => energy.values.fold(0, (a, b) => a + b);
}

/// [dimension] == null — все события (каждое один раз). Для конкретного измерения событие,
/// затрагивающее несколько измерений, учитывается в каждом — поэтому суммы по измерениям не складываются.
/// Период — полуинтервал [from, to).
/// [processId] — только события этого процесса.
ResourceSummary summarizeResources(
  List<LifeEvent> current, {
  required DateTime from,
  required DateTime to,
  String? dimension,
  String? processId,
}) {
  var n = 0, min = 0, minK = 0, rub = 0, rubK = 0;
  final energy = <int, int>{};
  for (final e in current) {
    if (e.at.isBefore(from) || !e.at.isBefore(to)) continue;
    if (dimension != null && !e.touches(dimension)) continue;
    if (processId != null && !e.processIds.contains(processId)) continue;
    n++;
    if (e.cost.minutes != null) {
      min += e.cost.minutes!;
      minK++;
    }
    if (e.cost.money != null) {
      rub += e.cost.money!;
      rubK++;
    }
    if (e.cost.energy != null) energy[e.cost.energy!] = (energy[e.cost.energy!] ?? 0) + 1;
  }
  return ResourceSummary(events: n, minutes: min, minutesKnown: minK, money: rub, moneyKnown: rubK, energy: energy);
}

/// Что вложено в процесс за всё время: ресурсы, первое и последнее событие.
class ProcessActivity {
  final ResourceSummary resources;
  final DateTime? firstAt;
  final DateTime? lastAt;
  const ProcessActivity({required this.resources, this.firstAt, this.lastAt});
}

ProcessActivity processActivity(List<LifeEvent> current, String processId) {
  DateTime? first, last;
  for (final e in current) {
    if (!e.processIds.contains(processId)) continue;
    if (first == null || e.at.isBefore(first)) first = e.at;
    if (last == null || e.at.isAfter(last)) last = e.at;
  }
  // за всё время: весь допустимый диапазон дат
  final resources = summarizeResources(
    current,
    from: DateTime.fromMillisecondsSinceEpoch(-8640000000000000),
    to: DateTime.fromMillisecondsSinceEpoch(8640000000000000),
    processId: processId,
  );
  return ProcessActivity(resources: resources, firstAt: first, lastAt: last);
}
