import 'dart:math';

import '../models/models.dart';

/// Чистая статистика журнала: без Flutter и без состояния — легко тестируется.

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Номер календарного дня (устойчив к переходу на летнее время).
int dayIndex(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

/// Понедельник недели, в которую входит [d].
DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

class DayStats {
  final DateTime day;
  final double volume;
  final int sets;
  final double best1RM;
  const DayStats(this.day, this.volume, this.sets, this.best1RM);
}

/// Итоги по дням, по возрастанию даты.
List<DayStats> dailyStats(Iterable<WorkoutSet> sets) {
  final map = <int, List<WorkoutSet>>{};
  for (final s in sets) {
    map.putIfAbsent(dayIndex(s.at), () => []).add(s);
  }
  final keys = map.keys.toList()..sort();
  return [
    for (final k in keys)
      DayStats(
        dateOnly(map[k]!.first.at),
        map[k]!.fold(0.0, (a, s) => a + s.volume),
        map[k]!.length,
        map[k]!.map((s) => s.estimated1RM).reduce(max),
      ),
  ];
}

/// Прогрессия: лучший 1RM за каждый тренировочный день, по возрастанию даты.
List<double> progressionFromSets(Iterable<WorkoutSet> sets) => dailyStats(sets).map((d) => d.best1RM).toList();

/// Объём за каждый из последних [days] дней, последний элемент = сегодня.
List<double> volumeLastDays(Iterable<WorkoutSet> sets, DateTime now, int days) {
  final today = dayIndex(now);
  final out = List<double>.filled(days, 0);
  for (final s in sets) {
    final i = days - 1 - (today - dayIndex(s.at));
    if (i >= 0 && i < days) out[i] += s.volume;
  }
  return out;
}

/// Объём по неделям (с понедельника), последний элемент = текущая неделя.
List<double> volumeLastWeeks(Iterable<WorkoutSet> sets, DateTime now, int weeks) {
  final thisWeek = dayIndex(mondayOf(now));
  final out = List<double>.filled(weeks, 0);
  for (final s in sets) {
    final diffWeeks = (thisWeek - dayIndex(mondayOf(s.at))) ~/ 7;
    final i = weeks - 1 - diffWeeks;
    if (i >= 0 && i < weeks) out[i] += s.volume;
  }
  return out;
}

/// Подписи недель: дата понедельника «дд.мм».
List<String> weekLabels(DateTime now, int weeks) {
  final monday = mondayOf(now);
  return List.generate(weeks, (i) {
    final d = DateTime(monday.year, monday.month, monday.day - 7 * (weeks - 1 - i));
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  });
}

/// Суммарный объём за [days] последних дней, сдвинутых назад на [offsetDays] (для сравнения с прошлой неделей).
double volumeInWindow(Iterable<WorkoutSet> sets, DateTime now, int days, {int offsetDays = 0}) {
  final today = dayIndex(now) - offsetDays;
  double v = 0;
  for (final s in sets) {
    final d = today - dayIndex(s.at);
    if (d >= 0 && d < days) v += s.volume;
  }
  return v;
}

int setsInWindow(Iterable<WorkoutSet> sets, DateTime now, int days) {
  final today = dayIndex(now);
  return sets.where((s) {
    final d = today - dayIndex(s.at);
    return d >= 0 && d < days;
  }).length;
}

int trainingDaysInWindow(Iterable<WorkoutSet> sets, DateTime now, int days) {
  final today = dayIndex(now);
  return sets.map((s) => dayIndex(s.at)).where((d) => today - d >= 0 && today - d < days).toSet().length;
}

/// Объём по мышечным группам за окно, по убыванию.
List<MapEntry<String, double>> volumeByMuscle(Iterable<WorkoutSet> sets, DateTime now, int days) {
  final today = dayIndex(now);
  final m = <String, double>{};
  for (final s in sets) {
    final d = today - dayIndex(s.at);
    if (d >= 0 && d < days) m[s.muscleId] = (m[s.muscleId] ?? 0) + s.volume;
  }
  return m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// Изменение в процентах; null, если сравнивать не с чем.
double? percentChange(double current, double previous) => previous <= 0 ? null : (current - previous) / previous * 100;
