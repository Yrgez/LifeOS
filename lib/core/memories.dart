import '../models/body.dart';
import '../models/day_snapshot.dart';
import '../models/life_event.dart';
import '../models/life_process.dart';
import '../models/models.dart';
import 'utils.dart';

/// «В этот день»: доказательства пройденного пути. Сравнение «тогда → сейчас» только по фактам журналов:
/// замеры веса, рекорды 1RM из подходов, снимки дней, события и начала процессов того дня.
/// Горизонт — год назад, если данных за год нет — месяц. Никаких оценок: только было и стало.

class MemoryLine {
  final String text;
  const MemoryLine(this.text);
}

class Memory {
  final int daysAgo; // 365 или 30
  final DateTime day; // день в прошлом
  final List<MemoryLine> lines;
  const Memory(this.daysAgo, this.day, this.lines);
}

String fmtKgShort(double v) => '${trimNum(round1(v)).replaceAll('.', ',')} кг';

/// Ближайший к [day] замер в пределах [toleranceDays].
WeightEntry? _weightNear(List<WeightEntry> ws, DateTime day, int toleranceDays) {
  WeightEntry? best;
  var bestDiff = toleranceDays + 1;
  for (final w in ws) {
    final d = w.at.difference(day).inDays.abs();
    if (d <= toleranceDays && d < bestDiff) {
      best = w;
      bestDiff = d;
    }
  }
  return best;
}

Memory? memoryFor({
  required DateTime now,
  required List<WeightEntry> weights,
  required List<WorkoutSet> sets,
  required Map<String, MuscleGroup> muscles,
  required Map<String, DaySnapshot> snapshots,
  required List<LifeEvent> currentEvents,
  required List<LifeProcess> processes,
}) {
  for (final days in const [365, 30]) {
    final day = DateTime(now.year, now.month, now.day - days);
    final lines = <MemoryLine>[];

    final wThen = _weightNear(weights, day, 7);
    final wNow = weights.isEmpty ? null : weights.last;
    if (wThen != null && wNow != null && !identical(wThen, wNow)) {
      lines.add(MemoryLine('Вес ${fmtKgShort(wThen.kg)} → сейчас ${fmtKgShort(wNow.kg)}'));
    }

    // рекорды 1RM: лучший до того дня и лучший сейчас — по группам, где они выросли (до двух строк)
    final end = DateTime(day.year, day.month, day.day + 1);
    final thenBest = <String, double>{}, nowBest = <String, double>{};
    for (final s in sets) {
      final v = oneRM(s.weight, s.reps);
      if (s.at.isBefore(end)) thenBest[s.muscleId] = v > (thenBest[s.muscleId] ?? 0) ? v : thenBest[s.muscleId]!;
      nowBest[s.muscleId] = v > (nowBest[s.muscleId] ?? 0) ? v : nowBest[s.muscleId]!;
    }
    final grown = [
      for (final e in thenBest.entries)
        if ((nowBest[e.key] ?? 0) > e.value + 0.5) (id: e.key, then: e.value, now: nowBest[e.key]!),
    ]..sort((a, b) => (b.now - b.then).compareTo(a.now - a.then));
    for (final g in grown.take(2)) {
      lines.add(MemoryLine('1RM, ${muscles[g.id]?.name ?? g.id}: ${g.then.round()} → сейчас ${g.now.round()} кг'));
    }

    final snap = snapshots[dayKey(day)];
    if (snap?.steps != null) lines.add(MemoryLine('Шаги в тот день: ${fmtMoney(snap!.steps!)}'));

    for (final p in processes) {
      if (dayKey(p.startedAt) == dayKey(day)) lines.add(MemoryLine('Начат процесс «${p.title}»'));
    }
    for (final e in currentEvents) {
      if (dayKey(e.at) == dayKey(day) && e.kind != LifeEventKind.review) lines.add(MemoryLine(e.title));
    }

    if (lines.isNotEmpty) return Memory(days, day, lines.take(5).toList());
  }
  return null;
}
