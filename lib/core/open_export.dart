import '../models/body.dart';
import '../models/day_checkin.dart';
import '../models/day_snapshot.dart';
import '../models/life_event.dart';
import '../models/life_process.dart';
import '../models/models.dart';
import 'chronicle.dart';
import 'finance_categories.dart';
import 'utils.dart';

/// Открытый экспорт: данные в форматах, которые читаются без LIFE OS — таблицы CSV (Excel, LibreOffice, Python)
/// и хроника в Markdown (обычный текст). Это не резервная копия: восстановить из него приложение нельзя,
/// зато через 20 лет его можно прочитать чем угодно. Принцип владения данными.

/// Поле CSV: кавычки, если в значении есть разделитель, кавычка или перенос строки.
String csvField(Object? v) {
  final s = v == null ? '' : '$v';
  if (s.contains(RegExp(r'[",\n\r;]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String _csv(List<String> header, Iterable<List<Object?>> rows) {
  final b = StringBuffer()..writeln(header.map(csvField).join(','));
  for (final r in rows) {
    b.writeln(r.map(csvField).join(','));
  }
  return b.toString();
}

String _dt(DateTime d) => '${dayKey(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Все события, включая версии и отменённые, — с колонками, по которым это видно.
String eventsCsv(List<LifeEvent> all, {Map<String, String> goalTitles = const {}, Map<String, String> processTitles = const {}}) => _csv(
      ['id', 'когда', 'записано', 'вид', 'измерения', 'название', 'минуты', 'внимание', 'деньги', 'энергия', 'цели', 'процессы', 'источник', 'заменяет', 'отменено', 'заметка'],
      [
        for (final e in all)
          [
            e.id,
            _dt(e.at),
            _dt(e.recordedAt),
            LifeEventKind.labels[e.kind],
            e.dimensions.map((d) => LifeDimension.labels[d]).join(' + '),
            e.title,
            e.cost.minutes,
            Attention.labels[e.cost.attention],
            e.cost.money,
            e.cost.energy,
            e.goalIds.map((g) => goalTitles[g] ?? g).join('; '),
            e.processIds.map((p) => processTitles[p] ?? p).join('; '),
            e.source,
            e.supersedesId,
            e.voidedAt == null ? null : _dt(e.voidedAt!),
            e.note,
          ],
      ],
    );

String transactionsCsv(List<MoneyTx> txs) => _csv(
      ['id', 'когда', 'тип', 'категория', 'сумма', 'в капитале', 'заметка', 'повтор'],
      [
        for (final t in txs)
          [t.id, _dt(t.at), t.isIncome ? 'доход' : 'расход', finCategory(t.categoryId)?.name ?? t.categoryId, t.amount, t.affectsNetWorth ? 'да' : 'нет', t.note, t.recurringId == null ? '' : 'да'],
      ],
    );

String snapshotsCsv(Iterable<DaySnapshot> snaps) => _csv(
      ['день', 'шаги', 'активные ккал', 'белок г', 'сон мин', 'капитал', 'узлы графа', 'источник активности'],
      [for (final s in snaps) [s.day, s.steps, s.activeCalories, s.protein, s.sleepMinutes, s.netWorth, s.graphNodes, s.activitySource]],
    );

String weightsCsv(List<WeightEntry> ws) => _csv(
      ['когда', 'вес кг', 'источник'],
      [for (final w in ws) [_dt(w.at), w.kg, w.source == 'health' ? 'Health Connect' : 'вручную']],
    );

String setsCsv(List<WorkoutSet> sets, Map<String, MuscleGroup> muscles) => _csv(
      ['когда', 'группа мышц', 'вес кг', 'повторы', 'расчётный 1RM'],
      [for (final s in sets) [_dt(s.at), muscles[s.muscleId]?.name ?? s.muscleId, s.weight, s.reps, round1(oneRM(s.weight, s.reps))]],
    );

/// Отметки дня — все версии: правка видна как новая строка, заменяющая прежнюю.
String checkInsCsv(List<DayCheckIn> all) => _csv(
      ['id', 'день', 'оценка', 'метки', 'заметка', 'записано', 'заменяет'],
      [for (final c in all) [c.id, c.day, c.rating, c.tags.join('; '), c.note, _dt(c.recordedAt), c.supersedesId]],
    );

/// Хроника в Markdown: месяцы → дни → записи; заметки событий — цитатой. Новые сверху, как в приложении.
String chronicleMarkdown({
  required String userName,
  required DateTime now,
  required List<ChronicleEntry> entries,
  required Map<String, DaySnapshot> snapshots,
  required List<LifeEvent> currentEvents,
  required List<LifeProcess> processes,
  Map<String, DayCheckIn> checkIns = const {},
}) {
  final notes = {for (final e in currentEvents) e.id: e.note};
  final b = StringBuffer()
    ..writeln('# Хроника${userName.isEmpty ? '' : ' — $userName'}')
    ..writeln()
    ..writeln('Выгружено из LIFE OS ${fmtDate(now)}. Только записанные факты; «нет данных» не означает ноль.')
    ..writeln();
  for (final m in groupChronicle(entries, snapshots: snapshots, checkIns: checkIns)) {
    b.writeln('## ${monthYear(m.month)}');
    b.writeln();
    for (final e in m.monthOnly) {
      b.writeln('- ${e.title} _(в течение месяца${e.detail.isEmpty ? '' : ' · ${e.detail}'})_');
    }
    if (m.monthOnly.isNotEmpty) b.writeln();
    for (final d in m.days) {
      final day = dayFromKey(d.day);
      b.writeln('### ${fmtDate(day)}, ${dayNames[day.weekday - 1]}');
      final s = d.snapshot;
      if (s != null) {
        final parts = [
          if (s.steps != null) 'шаги ${s.steps}',
          if (s.sleepMinutes != null) 'сон ${s.sleepMinutes} мин',
          if (s.netWorth != null) 'капитал ${s.netWorth}',
        ];
        if (parts.isNotEmpty) b.writeln('_${parts.join(' · ')}_');
      }
      final ch = d.checkIn;
      if (ch != null) {
        final head = [if (ch.rating != null) 'день ${ch.rating} из ${DayCheckIn.maxRating}', ...ch.tags];
        if (head.isNotEmpty) b.writeln('**${head.join(' · ')}**');
        if (ch.note.isNotEmpty) b.writeln('> ${ch.note.replaceAll('\n', '\n> ')}');
      }
      b.writeln();
      for (final e in d.entries) {
        final time = '${e.at.hour.toString().padLeft(2, '0')}:${e.at.minute.toString().padLeft(2, '0')}';
        b.writeln('- $time — ${e.title}${e.detail.isEmpty ? '' : ' _(${e.detail})_'}');
        final note = e.kind == ChronicleKind.event ? notes[e.refId] ?? '' : '';
        if (note.isNotEmpty) {
          for (final line in note.split('\n')) {
            b.writeln('  > $line');
          }
        }
      }
      b.writeln();
    }
  }
  final open = [for (final p in processes) if (p.isOpen) p.title];
  if (open.isNotEmpty) b.writeln('---\nИдут процессы: ${open.join(', ')}.');
  return b.toString();
}
