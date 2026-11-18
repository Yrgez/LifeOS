part of '../app_controller.dart';

/// Вечерняя отметка дня: оценка 1–5, метки, строка дневника.
/// Расширение того же library: работает с состоянием контроллера напрямую, мутации — только через `_commit`.
extension CheckInOps on AppController {
  /// С какого часа на «Сегодня» появляется вопрос «Как прошёл день?».
  static const promptHour = 18;

  /// До какого часа утром можно отметить вчерашний день из подсказки на «Сегодня».
  static const yesterdayUntilHour = 12;

  /// Насколько назад можно отметить день: память о дне быстро тускнеет.
  static const maxDaysBack = 7;

  /// Текущие отметки по дням (без заменённых версий).
  Map<String, DayCheckIn> get checkInsByDay => currentCheckIns(_d.checkIns);

  DayCheckIn? checkInFor(DateTime day) => checkInsByDay[dayKey(day)];

  /// Все версии отметки дня, от первой к последней.
  List<DayCheckIn> checkInVersions(DateTime day) {
    final k = dayKey(day);
    return [for (final c in _d.checkIns) if (c.day == k) c];
  }

  /// День, о котором стоит спросить сейчас: сегодня вечером — сегодня; утром — вчера, если человек уже
  /// отмечает дни и вчерашний пропущен. null — спрашивать не о чем.
  DateTime? get checkInPromptDay {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final byDay = checkInsByDay;
    if (now.hour >= promptHour) return byDay.containsKey(dayKey(today)) ? null : today;
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    if (now.hour < yesterdayUntilHour && byDay.isNotEmpty && !byDay.containsKey(dayKey(yesterday))) return yesterday;
    return null;
  }

  /// Метки, которые человек уже использовал, — частые сверху (за последние 90 дней).
  List<String> get checkInTagSuggestions {
    final now = _clock();
    final from = dayKey(DateTime(now.year, now.month, now.day - 90));
    final counts = <String, int>{};
    for (final c in checkInsByDay.values) {
      if (c.day.compareTo(from) < 0) continue;
      for (final t in c.tags) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    final list = counts.keys.toList()..sort((a, b) => counts[b] != counts[a] ? counts[b]!.compareTo(counts[a]!) : a.compareTo(b));
    return list;
  }

  /// Записывает отметку дня. Если отметка уже есть — новая версия со ссылкой на прежнюю (история не теряется).
  /// День — не в будущем и не раньше [maxDaysBack] дней назад. Возвращает id версии или null.
  String? setCheckIn(DateTime day, {int? rating, Iterable<String> tags = const [], String note = ''}) {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    if (d.isAfter(today) || d.isBefore(DateTime(today.year, today.month, today.day - maxDaysBack))) return null;
    final clean = <String>[];
    for (final t in tags) {
      final n = DayCheckIn.normalizeTag(t);
      if (n.isNotEmpty && !clean.contains(n)) clean.add(n);
    }
    final prev = checkInFor(d);
    final c = DayCheckIn(
      id: 'chk_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
      day: dayKey(d),
      rating: rating,
      tags: clean,
      note: note.trim(),
      recordedAt: now,
      supersedesId: prev?.id,
    );
    if (!c.isValid || _d.checkIns.length >= kMaxCheckIns) return null;
    // та же отметка повторно — новая версия не нужна
    if (prev != null && prev.rating == c.rating && prev.note == c.note && prev.tags.join('\u0000') == c.tags.join('\u0000')) return prev.id;
    _commit(() => _d.checkIns.add(c));
    return c.id;
  }

  /// Сводка отметок за [days] дней, заканчивающихся сегодня.
  CheckInSummary checkInSummary(int days) {
    final now = _clock();
    return summarizeCheckIns(checkInsByDay, [for (var i = days - 1; i >= 0; i--) dayKey(DateTime(now.year, now.month, now.day - i))]);
  }
}
