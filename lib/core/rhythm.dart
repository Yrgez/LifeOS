import '../models/life_event.dart';
import '../models/life_process.dart';
import 'utils.dart';

/// Ритм процесса: сколько раз за неделю (месяц) он задуман и сколько было на деле. Чистая логика без Flutter.
/// «Раз» — день, в котором есть событие процесса: две записи за день — один раз.
/// Без серий подряд и без «сгорания» за пропуск: только факт по каждому периоду.

class RhythmSpan {
  final DateTime from; // начало периода (понедельник или 1-е число)
  final DateTime to; // конец периода, не включительно
  final int? target; // сколько раз задумано; null — ритм в этот период не был задан
  final int done; // дней с событиями процесса
  final bool active; // процесс шёл хоть часть периода (не на паузе, не закрыт, уже начат)
  final bool current; // период ещё идёт

  const RhythmSpan({required this.from, required this.to, required this.target, required this.done, required this.active, required this.current});

  bool get reached => target != null && done >= target!;
}

/// Начало периода, в который попадает [t]: понедельник недели или первое число месяца.
DateTime rhythmPeriodStart(DateTime t, String period) =>
    period == RhythmPeriod.month ? DateTime(t.year, t.month) : DateTime(t.year, t.month, t.day - (t.weekday - 1));

DateTime _next(DateTime start, String period) =>
    period == RhythmPeriod.month ? DateTime(start.year, start.month + 1) : DateTime(start.year, start.month, start.day + 7);

DateTime _prev(DateTime start, String period) =>
    period == RhythmPeriod.month ? DateTime(start.year, start.month - 1) : DateTime(start.year, start.month, start.day - 7);

/// Последние [count] периодов (текущий первым) по текущему ритму процесса. Цель каждого периода — ритм,
/// действовавший на его конец (для текущего — сейчас). Периоды до начала процесса не показываются.
List<RhythmSpan> rhythmHistory(LifeProcess p, List<LifeEvent> current, DateTime now, {int count = 8}) {
  final period = p.rhythm?.period ?? RhythmPeriod.week;
  final days = <String>{
    for (final e in current)
      if (e.kind != LifeEventKind.review && e.processIds.contains(p.id)) dayKey(e.at)
  };
  final startDay = DateTime(p.startedAt.year, p.startedAt.month, p.startedAt.day);
  final out = <RhythmSpan>[];
  var from = rhythmPeriodStart(now, period);
  while (out.length < count) {
    final to = _next(from, period);
    if (!to.isAfter(startDay)) break; // период целиком до начала процесса
    final isCurrent = !now.isBefore(from) && now.isBefore(to);
    final edge = isCurrent ? now : to.subtract(const Duration(milliseconds: 1));
    var done = 0;
    for (var d = from; d.isBefore(to) && !d.isAfter(now); d = DateTime(d.year, d.month, d.day + 1)) {
      if (days.contains(dayKey(d))) done++;
    }
    out.add(RhythmSpan(
      from: from,
      to: to,
      target: p.rhythmAt(edge)?.times,
      done: done,
      active: p.activeDuring(from, isCurrent ? now : to),
      current: isCurrent,
    ));
    from = _prev(from, period);
  }
  return out;
}

/// «1 раз», «3 раза», «5 раз».
String timesLabel(int n) {
  final m10 = n % 10, m100 = n % 100;
  final word = m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? 'раза' : 'раз';
  return '$n $word';
}

/// «3 раза в неделю».
String rhythmLabel(ProcessRhythm r) => '${timesLabel(r.times)} ${RhythmPeriod.labels[r.period]}';

/// «на этой неделе 2 из 3» — факт текущего периода.
String rhythmNowLabel(ProcessRhythm r, RhythmSpan s) =>
    '${r.period == RhythmPeriod.month ? 'в этом месяце' : 'на этой неделе'} ${s.done} из ${r.times}';
