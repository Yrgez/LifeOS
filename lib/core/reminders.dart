import '../models/bill.dart';
import 'bills.dart';
import 'currency.dart';

/// Расписание локальных напоминаний. Чистая логика без Flutter.
///
/// Приложение пересчитывает его при каждом входе и выходе: так напоминание об уже сделанном не приходит
/// (день отмечен — вечером не спросим). Напоминания — приглашение, а не оценка: без «вы не сделали»,
/// без серий и без давления.

class ReminderTime {
  final int hour;
  final int minute;
  const ReminderTime(this.hour, this.minute);

  bool get isValid => hour >= 0 && hour < 24 && minute >= 0 && minute < 60;
  int get encoded => hour * 60 + minute;
  static ReminderTime decode(int v) => ReminderTime(v ~/ 60 % 24, v % 60);
  String get label => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  DateTime on(DateTime day) => DateTime(day.year, day.month, day.day, hour, minute);
}

/// Что напоминать. Всё выключено, пока человек не включит сам.
class ReminderPrefs {
  final bool checkIn;
  final ReminderTime checkInTime;
  final bool bills;
  final ReminderTime billsTime;
  final bool review;
  final ReminderTime reviewTime;
  const ReminderPrefs({
    this.checkIn = false,
    this.checkInTime = const ReminderTime(21, 0),
    this.bills = false,
    this.billsTime = const ReminderTime(10, 0),
    this.review = false,
    this.reviewTime = const ReminderTime(19, 0),
  });

  bool get any => checkIn || bills || review;
}

class ReminderPlan {
  final DateTime at;
  final String title;
  final String body;
  final String kind; // checkin / bill / review
  const ReminderPlan(this.at, this.title, this.body, this.kind);

  @override
  String toString() => '$kind $at $title — $body';
}

/// На сколько дней вперёд ставить напоминания (пересчёт при каждом открытии продлевает окно).
const reminderHorizonDays = 7;

/// Не больше стольких напоминаний сразу — защита от лавины при множестве счетов.
const reminderMaxCount = 40;

/// Напоминания на [reminderHorizonDays] дней вперёд, только в будущем, по времени.
/// [checkedDays] — дни (yyyy-MM-dd) с отметкой; [reviewDueAt] — с какого момента пора делать обзор (null — обзоры не нужны).
List<ReminderPlan> planReminders({
  required DateTime now,
  required ReminderPrefs prefs,
  required Set<String> checkedDays,
  required Iterable<Bill> bills,
  DateTime? reviewDueAt,
}) {
  final out = <ReminderPlan>[];
  final today = DateTime(now.year, now.month, now.day);
  DateTime day(int i) => DateTime(today.year, today.month, today.day + i);
  String key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  if (prefs.checkIn) {
    for (var i = 0; i < reminderHorizonDays; i++) {
      final d = day(i);
      if (checkedDays.contains(key(d))) continue;
      out.add(ReminderPlan(prefs.checkInTime.on(d), 'Как прошёл день?', 'Оценка дня — одно нажатие, метки и строка — по желанию', 'checkin'));
    }
  }

  if (prefs.bills) {
    for (final (b, due) in upcomingBills(bills, now, withinDays: reminderHorizonDays + 1)) {
      final amount = b.amount == null ? '' : ' · ${fmtCur(b.amount!)}';
      final dueDay = DateTime(due.year, due.month, due.day);
      if (dueDay.isBefore(today)) {
        // просрочен: одно напоминание — сегодня в обычное время (если оно ещё впереди)
        out.add(ReminderPlan(prefs.billsTime.on(today), b.title, 'Срок оплаты прошёл$amount', 'bill'));
        continue;
      }
      final before = DateTime(dueDay.year, dueDay.month, dueDay.day - 1);
      out.add(ReminderPlan(prefs.billsTime.on(before), b.title, 'Завтра срок оплаты$amount', 'bill'));
      out.add(ReminderPlan(prefs.billsTime.on(dueDay), b.title, 'Сегодня срок оплаты$amount', 'bill'));
    }
  }

  if (prefs.review && reviewDueAt != null) {
    final first = DateTime(reviewDueAt.year, reviewDueAt.month, reviewDueAt.day);
    final start = first.isBefore(today) ? today : first;
    for (var d = start; d.isBefore(day(reminderHorizonDays)); d = DateTime(d.year, d.month, d.day + 1)) {
      final at = prefs.reviewTime.on(d);
      if (at.isAfter(now)) {
        out.add(ReminderPlan(at, 'Обзор недели', 'Факты за 7 дней и три вопроса — пара минут', 'review'));
        break; // одно напоминание: дальше — когда обзор так и не сделан, следующий пересчёт поставит новое
      }
    }
  }

  final future = [for (final p in out) if (p.at.isAfter(now)) p]..sort((a, b) => a.at.compareTo(b.at));
  return future.length > reminderMaxCount ? future.sublist(0, reminderMaxCount) : future;
}
