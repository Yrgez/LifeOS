import '../models/day_snapshot.dart';
import '../models/life_event.dart';
import '../models/life_process.dart';
import '../models/models.dart';
import 'utils.dart';

/// Хроника (PAST): единая лента того, что было, собранная из журналов. Ничего не хранит сама —
/// только читает события, журналы статусов процессов, достижения и дневные снимки. Чистая логика без Flutter.

class ChronicleKind {
  static const event = 'event';
  static const process = 'process'; // смена статуса процесса (включая начало)
  static const achievement = 'achievement';
}

class ChronicleEntry {
  final String kind;
  final DateTime at;
  final bool monthOnly; // известен только месяц (у достижений дата — «Октябрь 2026»)
  final String title;
  final String detail;
  final List<String> dimensions; // пусто — измерение неизвестно
  final String? refId; // id события или процесса — для перехода

  const ChronicleEntry({
    required this.kind,
    required this.at,
    this.monthOnly = false,
    required this.title,
    this.detail = '',
    this.dimensions = const [],
    this.refId,
  });
}

/// Месяц хроники: записи с известным днём сгруппированы по дням (новые сверху),
/// записи «в течение месяца» — отдельно.
class ChronicleMonth {
  final DateTime month; // первое число
  final List<ChronicleEntry> monthOnly;
  final List<ChronicleDay> days;
  const ChronicleMonth(this.month, this.monthOnly, this.days);
}

class ChronicleDay {
  final String day; // yyyy-MM-dd
  final List<ChronicleEntry> entries; // по убыванию времени
  final DaySnapshot? snapshot;
  const ChronicleDay(this.day, this.entries, this.snapshot);
}

/// «Октябрь 2026» → 1 октября 2026; null — не распознано.
DateTime? parseMonthYear(String s) {
  final parts = s.trim().split(RegExp(r'\s+'));
  if (parts.length != 2) return null;
  final m = monthNames.indexWhere((n) => n.toLowerCase() == parts[0].toLowerCase());
  final y = int.tryParse(parts[1]);
  if (m < 0 || y == null || y < 1900 || y > 3000) return null;
  return DateTime(y, m + 1);
}

/// Все записи хроники. Достижения без распознаваемой даты не попадают в ленту ([undatedAchievements]).
List<ChronicleEntry> chronicleEntries({
  required List<LifeEvent> currentEvents,
  required List<LifeProcess> processes,
  required List<AchievementItem> achievements,
}) {
  final out = <ChronicleEntry>[
    for (final e in currentEvents)
      ChronicleEntry(
        kind: ChronicleKind.event,
        at: e.at,
        title: e.title,
        detail: LifeEventKind.labels[e.kind] ?? '',
        dimensions: e.dimensions,
        refId: e.id,
      ),
  ];
  for (final p in processes) {
    for (var i = 0; i < p.statusLog.length; i++) {
      final c = p.statusLog[i];
      final what = i == 0 ? 'Начат процесс' : 'Процесс ${_statusPhrase(c.status)}';
      out.add(ChronicleEntry(
        kind: ChronicleKind.process,
        at: c.at,
        title: '$what «${p.title}»',
        detail: c.note,
        dimensions: p.dimensions,
        refId: p.id,
      ));
    }
  }
  for (final a in achievements) {
    final m = parseMonthYear(a.date);
    if (m == null) continue;
    out.add(ChronicleEntry(kind: ChronicleKind.achievement, at: m, monthOnly: true, title: a.title, detail: a.category));
  }
  out.sort((a, b) => b.at.compareTo(a.at));
  return out;
}

List<AchievementItem> undatedAchievements(List<AchievementItem> achievements) =>
    [for (final a in achievements) if (parseMonthYear(a.date) == null) a];

String _statusPhrase(String s) => switch (s) {
      ProcessStatus.active => 'возобновлён',
      ProcessStatus.paused => 'на паузе:',
      ProcessStatus.completed => 'завершён:',
      _ => 'прекращён:',
    };

/// Группировка по месяцам (новые сверху). [snapshots] — по ключу дня; день без записей
/// попадает в ленту, только если [includeQuietDays] и за него есть снимок.
List<ChronicleMonth> groupChronicle(
  List<ChronicleEntry> entries, {
  required Map<String, DaySnapshot> snapshots,
  bool includeQuietDays = false,
}) {
  final byMonth = <DateTime, ({List<ChronicleEntry> monthOnly, Map<String, List<ChronicleEntry>> days})>{};
  ({List<ChronicleEntry> monthOnly, Map<String, List<ChronicleEntry>> days}) bucket(DateTime t) =>
      byMonth.putIfAbsent(DateTime(t.year, t.month), () => (monthOnly: <ChronicleEntry>[], days: <String, List<ChronicleEntry>>{}));

  for (final e in entries) {
    final b = bucket(e.at);
    if (e.monthOnly) {
      b.monthOnly.add(e);
    } else {
      (b.days[dayKey(e.at)] ??= []).add(e);
    }
  }
  if (includeQuietDays) {
    for (final key in snapshots.keys) {
      bucket(dayFromKey(key)).days.putIfAbsent(key, () => []);
    }
  }
  final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final m in months)
      ChronicleMonth(
        m,
        byMonth[m]!.monthOnly,
        [
          for (final key in (byMonth[m]!.days.keys.toList()..sort((a, b) => b.compareTo(a))))
            ChronicleDay(key, byMonth[m]!.days[key]!..sort((a, b) => b.at.compareTo(a.at)), snapshots[key]),
        ],
      ),
  ];
}
