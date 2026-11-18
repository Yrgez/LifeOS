import '../models/body.dart';
import '../models/day_checkin.dart';
import '../models/day_snapshot.dart';
import '../models/experiment.dart';
import '../models/life_event.dart';
import 'life_events.dart';
import 'utils.dart';

/// Сравнение периодов эксперимента. Чистая логика без Flutter.
/// Только наблюдения: значения по дням, сколько дней с данными, медиана и размах. Никаких p-значений,
/// «эффектов» и вердиктов — на показатель влияет многое, и решать, что это значит, человеку.

class ExperimentSide {
  final DateTime from; // начало периода
  final DateTime to; // конец периода (не включительно), обрезан сегодняшним днём
  final List<({String day, num value})> daily; // дни с данными — для дневных показателей
  final ResourceSummary? events; // для энергии и процесса
  final int daysWithEvents; // для процесса: в скольких днях были события
  final Map<int, int>? ratings; // для оценки дня: оценка → число дней (распределение, без среднего)

  const ExperimentSide({required this.from, required this.to, this.daily = const [], this.events, this.daysWithEvents = 0, this.ratings});

  int get ratedDays => ratings?.values.fold<int>(0, (a, b) => a + b) ?? 0;

  /// Календарных дней в периоде (переход на летнее время не сбивает счёт).
  int get days {
    var n = 0;
    for (var d = from; d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
      n++;
    }
    return n;
  }
  List<num> get values => [for (final d in daily) d.value];
  num? get median => medianOf(values);
  num? get min => values.isEmpty ? null : values.reduce((a, b) => a < b ? a : b);
  num? get max => values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
}

/// Меньше этого числа дней с данными сравнение ничего не говорит — показываем предупреждение.
const kExperimentMinDays = 5;

num? medianOf(List<num> values) {
  if (values.isEmpty) return null;
  final s = [...values]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

class ExperimentResult {
  final ExperimentSide before; // A
  final ExperimentSide? after; // B; null — эксперимент ещё не начался
  const ExperimentResult(this.before, this.after);
}

ExperimentResult experimentResult(
  Experiment x, {
  required Map<String, DaySnapshot> snapshots,
  required List<WeightEntry> weights,
  required List<LifeEvent> currentEvents,
  required DateTime now,
  Map<String, DayCheckIn> checkIns = const {},
}) {
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  DateTime cap(DateTime t) => t.isAfter(tomorrow) ? tomorrow : t;
  ExperimentSide side(DateTime from, DateTime to) {
    to = cap(to);
    bool inside(DateTime t) => !t.isBefore(from) && t.isBefore(to);
    if (x.metric == ExperimentMetric.dayRating) {
      final r = <int, int>{};
      for (var d = from; d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
        final v = checkIns[dayKey(d)]?.rating;
        if (v != null) r[v] = (r[v] ?? 0) + 1;
      }
      return ExperimentSide(from: from, to: to, ratings: r);
    }
    if (x.metric == ExperimentMetric.weight) {
      final last = <String, double>{}; // последний замер дня
      for (final w in weights) {
        if (inside(w.at)) last[dayKey(w.at)] = w.kg;
      }
      return ExperimentSide(from: from, to: to, daily: [for (final k in last.keys.toList()..sort()) (day: k, value: last[k]!)]);
    }
    if (ExperimentMetric.isDaily(x.metric)) {
      final out = <({String day, num value})>[];
      for (var d = from; d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
        final s = snapshots[dayKey(d)];
        final v = switch (x.metric) {
          ExperimentMetric.steps => s?.steps,
          ExperimentMetric.sleep => s?.sleepMinutes,
          ExperimentMetric.protein => s?.protein,
          _ => s?.activeCalories,
        };
        if (v != null) out.add((day: dayKey(d), value: v));
      }
      return ExperimentSide(from: from, to: to, daily: out);
    }
    final evs = [
      for (final e in currentEvents)
        if (inside(e.at) && (x.metric == ExperimentMetric.energy || e.processIds.contains(x.processId))) e
    ];
    return ExperimentSide(from: from, to: to, events: summarizeEvents(evs), daysWithEvents: {for (final e in evs) dayKey(e.at)}.length);
  }

  final before = side(x.baselineStart, x.startedAt);
  final after = now.isBefore(x.startedAt) ? null : side(x.startedAt, x.end);
  return ExperimentResult(before, after);
}
