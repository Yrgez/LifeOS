// Вечерняя отметка дня: оценка 1–5, метки и строка дневника. Чистый Dart, без Flutter.
//
// Оценка — субъективная шкала: её не усредняют, а показывают распределением («4 — 3 дня, 3 — 1 день»).
// Правка не перезаписывает отметку: появляется новая версия со ссылкой на прежнюю (`supersedesId`).

import 'day_snapshot.dart' show isValidDayKey;

class DayCheckIn {
  static const minRating = 1;
  static const maxRating = 5;
  static const maxTags = 10;
  static const maxTagLength = 30;
  static const maxNote = 500;

  /// Подписи краёв шкалы — чтобы оценка значила одно и то же изо дня в день.
  static const ratingHint = '1 — тяжёлый, 3 — обычный, 5 — отличный';

  final String id;
  final String day; // yyyy-MM-dd — день, о котором отметка (может быть вчерашним)
  final int? rating; // null — оценку не ставили (только метки или заметка)
  final List<String> tags;
  final String note;
  final DateTime recordedAt; // когда записано
  final String? supersedesId; // прежняя версия этой отметки

  DayCheckIn({
    required this.id,
    required this.day,
    this.rating,
    Iterable<String> tags = const [],
    this.note = '',
    required this.recordedAt,
    this.supersedesId,
  }) : tags = List.unmodifiable(tags);

  /// Метка: обрезанная, в нижнем регистре — «Кофе» и «кофе » — одна метка.
  static String normalizeTag(String t) => t.trim().toLowerCase();

  bool get isValid =>
      id.trim().isNotEmpty &&
      isValidDayKey(day) &&
      (rating == null || (rating! >= minRating && rating! <= maxRating)) &&
      tags.length <= maxTags &&
      tags.toSet().length == tags.length &&
      tags.every((t) => t.isNotEmpty && t.length <= maxTagLength && t == normalizeTag(t)) &&
      note.length <= maxNote &&
      (rating != null || tags.isNotEmpty || note.trim().isNotEmpty);

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': day,
        if (rating != null) 'r': rating,
        if (tags.isNotEmpty) 'tags': tags,
        if (note.isNotEmpty) 'note': note,
        'at': recordedAt.millisecondsSinceEpoch,
        if (supersedesId != null) 'sup': supersedesId,
      };

  factory DayCheckIn.fromJson(Map<String, dynamic> j) => tryFromJson(j) ?? (throw const FormatException('DayCheckIn'));

  /// null — запись битая.
  static DayCheckIn? tryFromJson(Map<String, dynamic> j) {
    final id = j['id'], day = j['day'], r = j['r'], tags = j['tags'] ?? const [], note = j['note'] ?? '', at = j['at'], sup = j['sup'];
    if (id is! String || day is! String || tags is! List || note is! String || at is! num || !at.isFinite) return null;
    if (r != null && (r is! num || r != r.roundToDouble())) return null;
    if (sup != null && sup is! String) return null;
    if (tags.any((t) => t is! String)) return null;
    final c = DayCheckIn(
      id: id,
      day: day,
      rating: (r as num?)?.toInt(),
      tags: tags.cast<String>(),
      note: note,
      recordedAt: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      supersedesId: sup as String?,
    );
    return c.isValid ? c : null;
  }
}

/// Текущие отметки по дням: из версий выбирается та, которую никто не заменил (при сбое — самая поздняя).
Map<String, DayCheckIn> currentCheckIns(Iterable<DayCheckIn> all) {
  final replaced = {for (final c in all) if (c.supersedesId != null) c.supersedesId!};
  final out = <String, DayCheckIn>{};
  for (final c in all) {
    if (replaced.contains(c.id)) continue;
    final prev = out[c.day];
    if (prev == null || c.recordedAt.isAfter(prev.recordedAt)) out[c.day] = c;
  }
  return out;
}

/// Сводка отметок за период: сколько дней отмечено, распределение оценок и частые метки. Без средних.
class CheckInSummary {
  final int days; // дней в периоде
  final int checked; // дней с отметкой
  final Map<int, int> ratings; // оценка → число дней
  final List<(String, int)> tags; // метка → число дней, по убыванию
  const CheckInSummary(this.days, this.checked, this.ratings, this.tags);

  int get rated => ratings.values.fold(0, (a, b) => a + b);
}

CheckInSummary summarizeCheckIns(Map<String, DayCheckIn> byDay, List<String> dayKeys) {
  final ratings = <int, int>{};
  final tags = <String, int>{};
  var checked = 0;
  for (final k in dayKeys) {
    final c = byDay[k];
    if (c == null) continue;
    checked++;
    if (c.rating != null) ratings[c.rating!] = (ratings[c.rating!] ?? 0) + 1;
    for (final t in c.tags) {
      tags[t] = (tags[t] ?? 0) + 1;
    }
  }
  final sorted = tags.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
  return CheckInSummary(dayKeys.length, checked, ratings, [for (final e in sorted) (e.key, e.value)]);
}

/// «4 — 3 дн., 3 — 1 дн.» — распределение оценок, от высокой к низкой.
String ratingDistribution(Map<int, int> ratings) => [
      for (var r = DayCheckIn.maxRating; r >= DayCheckIn.minRating; r--)
        if (ratings[r] != null) '$r — ${ratings[r]} дн.',
    ].join(', ');
