import '../models/bill.dart';
import '../models/day_checkin.dart';
import '../models/life_event.dart';
import '../models/life_process.dart';
import '../models/life_task.dart';
import '../models/models.dart';
import 'currency.dart';
import 'finance_categories.dart';

/// Поиск по записям человека: события, операции, отметки дня, процессы, цели, достижения, счета.
/// Чистая логика без Flutter. Без «умных» догадок: ищется то, что написано, без учёта регистра и «ё/е»;
/// несколько слов — все должны встретиться. Число ищет ещё и суммы.

class SearchKind {
  static const event = 'event';
  static const transaction = 'tx';
  static const checkIn = 'checkin';
  static const process = 'process';
  static const goal = 'goal';
  static const achievement = 'achievement';
  static const bill = 'bill';
  static const task = 'task';

  static const labels = {
    event: 'Событие',
    transaction: 'Операция',
    checkIn: 'Отметка дня',
    process: 'Процесс',
    goal: 'Цель',
    achievement: 'Достижение',
    bill: 'Счёт',
    task: 'Задача',
  };
}

class SearchHit {
  final String kind;
  final String refId;
  final DateTime? at; // когда — для сортировки и подписи; null — без даты
  final String title;
  final String snippet; // где нашлось: кусок текста вокруг совпадения
  final bool voided; // отменённое событие — в истории, но помечено
  const SearchHit({required this.kind, required this.refId, required this.at, required this.title, this.snippet = '', this.voided = false});
}

String normalizeSearch(String s) => s.toLowerCase().replaceAll('ё', 'е');

/// Слова запроса; пустой запрос — пустой список.
List<String> searchTokens(String query) => [for (final t in normalizeSearch(query).split(RegExp(r'\s+'))) if (t.isNotEmpty) t];

/// Число в запросе (для поиска сумм): «1 500» и «1500» — одно и то же. null — запрос не число.
int? searchAmount(String query) {
  final digits = query.replaceAll(RegExp(r'[\s ]'), '');
  return RegExp(r'^\d{2,}$').hasMatch(digits) ? int.tryParse(digits) : null;
}

/// Кусок [text] вокруг первого из [tokens]: «…кофе с Аней после работы…». Пусто — совпадения в тексте нет.
String searchSnippet(String text, List<String> tokens, {int radius = 40}) {
  final n = normalizeSearch(text);
  var pos = -1;
  for (final t in tokens) {
    final i = n.indexOf(t);
    if (i >= 0 && (pos < 0 || i < pos)) pos = i;
  }
  if (pos < 0) return '';
  final start = pos - radius < 0 ? 0 : pos - radius;
  final end = pos + radius > text.length ? text.length : pos + radius;
  return '${start > 0 ? '…' : ''}${text.substring(start, end).replaceAll('\n', ' ').trim()}${end < text.length ? '…' : ''}';
}

bool _matches(List<String> tokens, Iterable<String> fields) {
  final hay = normalizeSearch(fields.join('\n'));
  return tokens.every(hay.contains);
}

const searchLimit = 200;

/// Все совпадения, новые сверху (без даты — в конце). Не больше [searchLimit].
List<SearchHit> searchRecords(
  String query, {
  List<LifeEvent> events = const [],
  List<MoneyTx> transactions = const [],
  Iterable<DayCheckIn> checkIns = const [],
  List<LifeProcess> processes = const [],
  List<GlobalGoal> goals = const [],
  List<AchievementItem> achievements = const [],
  List<Bill> bills = const [],
  List<LifeTask> tasks = const [],
}) {
  final tokens = searchTokens(query);
  if (tokens.isEmpty) return const [];
  final amount = searchAmount(query);
  final out = <SearchHit>[];

  for (final e in events) {
    final byAmount = amount != null && e.cost.money == amount;
    if (!byAmount && !_matches(tokens, [e.title, e.note, LifeEventKind.labels[e.kind] ?? ''])) continue;
    out.add(SearchHit(kind: SearchKind.event, refId: e.id, at: e.at, title: e.title, snippet: searchSnippet(e.note, tokens), voided: e.isVoided));
  }
  for (final t in transactions) {
    final cat = finCategory(t.categoryId)?.name ?? t.categoryId;
    final byAmount = amount != null && t.amount == amount;
    if (!byAmount && !_matches(tokens, [t.note, cat])) continue;
    out.add(SearchHit(kind: SearchKind.transaction, refId: t.id, at: t.at, title: '$cat · ${t.isIncome ? '+' : '−'}${fmtCur(t.amount)}', snippet: t.note));
  }
  for (final c in checkIns) {
    if (!_matches(tokens, [c.note, ...c.tags])) continue;
    final day = DateTime.parse(c.day);
    out.add(SearchHit(
      kind: SearchKind.checkIn,
      refId: c.day,
      at: DateTime(day.year, day.month, day.day, 21),
      title: [if (c.rating != null) 'день ${c.rating} из ${DayCheckIn.maxRating}', ...c.tags].join(' · '),
      snippet: c.note,
    ));
  }
  for (final p in processes) {
    if (!_matches(tokens, [p.title, p.description])) continue;
    out.add(SearchHit(kind: SearchKind.process, refId: p.id, at: p.startedAt, title: p.title, snippet: searchSnippet(p.description, tokens)));
  }
  for (final g in goals) {
    if (!_matches(tokens, [g.title, g.category])) continue;
    out.add(SearchHit(kind: SearchKind.goal, refId: g.id, at: g.createdAt, title: g.title, snippet: g.category));
  }
  for (final a in achievements) {
    if (!_matches(tokens, [a.title, a.category])) continue;
    out.add(SearchHit(kind: SearchKind.achievement, refId: a.title, at: a.at, title: a.title, snippet: a.date));
  }
  for (final t in tasks) {
    if (!_matches(tokens, [t.title, t.note])) continue;
    final status = switch (t.status) { TaskStatus.done => 'сделано', TaskStatus.cancelled => 'отменена', TaskStatus.open => '' };
    out.add(SearchHit(
      kind: SearchKind.task,
      refId: t.id,
      at: t.doneChange?.at ?? t.createdAt,
      title: status.isEmpty ? t.title : '${t.title} · $status',
      snippet: searchSnippet(t.note, tokens),
    ));
  }
  for (final b in bills) {
    if (!_matches(tokens, [b.title])) continue;
    out.add(SearchHit(kind: SearchKind.bill, refId: b.id, at: null, title: b.title));
  }

  out.sort((a, b) {
    if (a.at == null && b.at == null) return 0;
    if (a.at == null) return 1;
    if (b.at == null) return -1;
    return b.at!.compareTo(a.at!);
  });
  return out.length > searchLimit ? out.sublist(0, searchLimit) : out;
}
