import '../models/life_event.dart';
import '../models/models.dart';
import 'life_events.dart';

/// Распределение ресурсов за период: куда ушли время, деньги и энергия — по измерениям и процессам.
/// Чистая логика без Flutter. Только суммы известных значений и счёт неуказанного: без индексов,
/// без процентов изменения и без средних по субъективной шкале.

/// Период отсчитывается назад от конца сегодняшнего дня.
class ResourcePeriod {
  final int days;
  final String label;
  const ResourcePeriod(this.days, this.label);
}

const resourcePeriods = [
  ResourcePeriod(7, '7 дней'),
  ResourcePeriod(30, '30 дней'),
  ResourcePeriod(90, '90 дней'),
  ResourcePeriod(365, 'Год'),
];

/// Ресурсы одного процесса за период.
class ProcessShare {
  final String processId;
  final ResourceSummary summary;
  const ProcessShare(this.processId, this.summary);
}

class ResourceBreakdown {
  final DateTime from; // начало периода (полночь)
  final DateTime to; // конец периода — начало завтрашнего дня
  final DateTime now;
  final ResourceSummary total; // каждое событие один раз
  final Map<String, ResourceSummary> byDimension; // все три измерения, в порядке LifeDimension.all
  final List<ProcessShare> byProcess; // только процессы с событиями в периоде; по убыванию времени, затем событий
  final ResourceSummary withoutProcess; // события, не отнесённые ни к одному процессу
  final ResourceSummary previous; // предыдущий период той же длины — для сравнения «было / стало»
  final int financeExpense; // расходы по журналу операций за период, ₽ (отдельный источник)
  final int financeExpenseCount;

  const ResourceBreakdown({
    required this.from,
    required this.to,
    required this.now,
    required this.total,
    required this.byDimension,
    required this.byProcess,
    required this.withoutProcess,
    required this.previous,
    required this.financeExpense,
    required this.financeExpenseCount,
  });

  /// Сколько минут периода уже прошло (до текущего момента) — фон для «учтено N часов».
  int get elapsedMinutes => now.difference(from).inMinutes;
}

/// Границы периода из [days] дней, заканчивающегося сегодняшним днём (по местному времени).
({DateTime from, DateTime to}) periodBounds(DateTime now, int days) {
  final to = DateTime(now.year, now.month, now.day + 1);
  return (from: DateTime(now.year, now.month, now.day + 1 - days), to: to);
}

ResourceBreakdown resourceBreakdown({
  required List<LifeEvent> current,
  required Iterable<MoneyTx> transactions,
  required DateTime now,
  required int days,
}) {
  final b = periodBounds(now, days);
  final prevFrom = DateTime(b.from.year, b.from.month, b.from.day - days);
  bool inPeriod(DateTime t) => !t.isBefore(b.from) && t.isBefore(b.to);
  final events = [for (final e in current) if (inPeriod(e.at)) e];

  final byProcessEvents = <String, List<LifeEvent>>{};
  for (final e in events) {
    for (final p in e.processIds) {
      (byProcessEvents[p] ??= []).add(e);
    }
  }
  final shares = [for (final en in byProcessEvents.entries) ProcessShare(en.key, summarizeEvents(en.value))]
    ..sort((a, b) {
      final m = b.summary.minutes.compareTo(a.summary.minutes);
      if (m != 0) return m;
      final n = b.summary.events.compareTo(a.summary.events);
      return n != 0 ? n : a.processId.compareTo(b.processId);
    });

  var expense = 0, expenseCount = 0;
  for (final t in transactions) {
    if (!t.isIncome && inPeriod(t.at)) {
      expense += t.amount;
      expenseCount++;
    }
  }

  return ResourceBreakdown(
    from: b.from,
    to: b.to,
    now: now,
    total: summarizeEvents(events),
    byDimension: {for (final d in LifeDimension.all) d: summarizeEvents(events.where((e) => e.touches(d)))},
    byProcess: shares,
    withoutProcess: summarizeEvents(events.where((e) => e.processIds.isEmpty)),
    previous: summarizeResources(current, from: prevFrom, to: b.from),
    financeExpense: expense,
    financeExpenseCount: expenseCount,
  );
}
