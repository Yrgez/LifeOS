// Дневной снимок состояния: как обстояли дела в конкретный день. Чистый Dart, без Flutter.
//
// Заменяет недельные массивы, которые сдвигались и затирались каждый день. Снимок хранится вечно:
// текущий день обновляется по мере изменений, прошлые дни дополняет только источник данных
// (Health Connect прислал шаги за вчера). День без снимка — «нет данных», а не ноль.
// Любое поле null — «неизвестно».

final _dayRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

int? _nonNeg(Object? v) => v is num && v.isFinite && v == v.roundToDouble() && v >= 0 ? v.toInt() : null;
int? _int(Object? v) => v is num && v.isFinite && v == v.roundToDouble() ? v.toInt() : null;

/// Ключ дня `yyyy-MM-dd` с проверкой календаря (2026-02-30 — неверно).
bool isValidDayKey(String s) {
  if (!_dayRe.hasMatch(s)) return false;
  final p = s.split('-').map(int.parse).toList();
  final d = DateTime.utc(p[0], p[1], p[2]);
  return d.year == p[0] && d.month == p[1] && d.day == p[2];
}

DateTime dayFromKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

class DaySnapshot {
  final String day; // yyyy-MM-dd, местное время
  int? steps;
  int? activeCalories;
  int? protein; // г
  int? netWorth; // ₽, может быть отрицательным
  int? graphNodes; // число узлов графа
  int? sleepMinutes; // сон, завершившийся в этот день (Health Connect), минуты

  /// Откуда шаги и калории: 'health' — Health Connect, 'manual' — введено вручную.
  String? activitySource;

  DaySnapshot({
    required this.day,
    this.steps,
    this.activeCalories,
    this.protein,
    this.netWorth,
    this.graphNodes,
    this.sleepMinutes,
    this.activitySource,
  });

  bool get isEmpty => steps == null && activeCalories == null && protein == null && netWorth == null && graphNodes == null && sleepMinutes == null;

  DaySnapshot copy() => DaySnapshot(
        day: day,
        steps: steps,
        activeCalories: activeCalories,
        protein: protein,
        netWorth: netWorth,
        graphNodes: graphNodes,
        sleepMinutes: sleepMinutes,
        activitySource: activitySource,
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        if (steps != null) 'steps': steps,
        if (activeCalories != null) 'kcal': activeCalories,
        if (protein != null) 'protein': protein,
        if (netWorth != null) 'nw': netWorth,
        if (graphNodes != null) 'nodes': graphNodes,
        if (sleepMinutes != null) 'sleep': sleepMinutes,
        if (activitySource != null) 'src': activitySource,
      };

  /// Сравнение по содержимому (контроллер пишет снимок в базу, только если он изменился).
  String get signature => toJson().toString();

  /// null — запись битая: неверный день, отрицательные или нецелые значения, неизвестный источник.
  static DaySnapshot? tryFromJson(Map<String, dynamic> j) {
    final day = j['day'];
    if (day is! String || !isValidDayKey(day)) return null;
    int? field(String k, int? Function(Object?) parse) {
      final v = j[k];
      if (v == null) return null;
      return parse(v) ?? (throw const FormatException('DaySnapshot'));
    }

    try {
      final src = j['src'];
      if (src != null && src != 'health' && src != 'manual') return null;
      return DaySnapshot(
        day: day,
        steps: field('steps', _nonNeg),
        activeCalories: field('kcal', _nonNeg),
        protein: field('protein', _nonNeg),
        netWorth: field('nw', _int),
        graphNodes: field('nodes', _nonNeg),
        sleepMinutes: field('sleep', _nonNeg),
        activitySource: src as String?,
      );
    } on FormatException {
      return null;
    }
  }
}
