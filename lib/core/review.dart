import '../models/life_event.dart';
import '../models/life_process.dart';
import 'life_events.dart';
import 'resource_stats.dart';

/// Еженедельный обзор (стадия «осмысление» личной информатики): факты за 7 дней и три вопроса.
/// Обзор сохраняется как событие вида [LifeEventKind.review]: ответы — в заметке под постоянными заголовками,
/// поэтому их можно прочитать и через год, и без приложения. Приложение ничего не оценивает.

const reviewQuestions = ['Что получилось?', 'Что мешало?', 'Что меняю на следующей неделе?'];

/// Через сколько дней после прошлого обзора предлагать новый.
const reviewEveryDays = 7;

/// Процесс в обзоре: что в него вложено за неделю (может быть «событий нет» — это тоже факт).
class ReviewProcessLine {
  final LifeProcess process;
  final ResourceSummary week;
  const ReviewProcessLine(this.process, this.week);
}

class ReviewFacts {
  final ResourceBreakdown breakdown; // 7 дней: итог, измерения, прошлая неделя
  final List<ReviewProcessLine> processes; // открытые процессы: идущие и на паузе
  final LifeEvent? previous; // прошлый обзор
  const ReviewFacts(this.breakdown, this.processes, this.previous);
}

ReviewFacts reviewFacts({
  required ResourceBreakdown breakdown,
  required List<LifeEvent> current,
  required List<LifeProcess> processes,
}) {
  final open = [for (final p in processes) if (p.isOpen) p];
  return ReviewFacts(
    breakdown,
    [
      for (final p in open)
        ReviewProcessLine(p, summarizeResources(current, from: breakdown.from, to: breakdown.to, processId: p.id)),
    ],
    lastReview(current),
  );
}

/// Последний актуальный обзор или null.
LifeEvent? lastReview(List<LifeEvent> current) {
  LifeEvent? last;
  for (final e in current) {
    if (e.kind == LifeEventKind.review && (last == null || !e.at.isBefore(last.at))) last = e;
  }
  return last;
}

/// Пора ли предложить обзор: прошлого нет (и есть что обозревать) или он был [reviewEveryDays]+ дней назад.
bool reviewDue(List<LifeEvent> current, DateTime now) {
  final last = lastReview(current);
  if (last == null) return current.any((e) => e.kind != LifeEventKind.review);
  return now.difference(last.at).inDays >= reviewEveryDays;
}

/// Заметка обзора: вопрос — заголовок, под ним ответ. Пустые ответы не пишутся.
String composeReviewNote(List<String> answers) {
  final b = StringBuffer();
  for (var i = 0; i < reviewQuestions.length && i < answers.length; i++) {
    final a = answers[i].trim();
    if (a.isEmpty) continue;
    if (b.isNotEmpty) b.write('\n\n');
    b.write('${reviewQuestions[i]}\n$a');
  }
  return b.toString();
}

/// Ответы из заметки обзора (по тем же заголовкам); отсутствующий ответ — пустая строка.
List<String> parseReviewNote(String note) {
  final out = List.filled(reviewQuestions.length, '');
  final lines = note.split('\n');
  var current = -1;
  final buf = <String>[];
  void flush() {
    if (current >= 0) out[current] = buf.join('\n').trim();
    buf.clear();
  }

  for (final l in lines) {
    final q = reviewQuestions.indexOf(l.trim());
    if (q >= 0) {
      flush();
      current = q;
    } else if (current >= 0) {
      buf.add(l);
    }
  }
  flush();
  return out;
}
