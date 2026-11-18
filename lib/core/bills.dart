import '../models/bill.dart';
import 'utils.dart';

/// Сроки счетов. Чистая логика без Flutter. Первый срок счёта — ближайший неоплаченный на момент создания;
/// дальше сроки идут по повтору, оплаченные пропускаются.

/// Ближайший неоплаченный срок; null — разовый счёт оплачен или счёт в архиве.
DateTime? nextDue(Bill b) {
  if (b.archivedAt != null) return null;
  final paid = {for (final p in b.payments) p.due};
  for (var n = 0; n < 5000; n++) {
    final d = b.dueAt(n);
    if (!paid.contains(dayKey(d))) return d;
    if (b.repeat == BillRepeat.none) return null;
  }
  return null;
}

/// Дней до срока: 0 — сегодня, отрицательное — просрочен.
int daysUntil(DateTime due, DateTime now) =>
    DateTime.utc(due.year, due.month, due.day).difference(DateTime.utc(now.year, now.month, now.day)).inDays;

/// «сегодня», «завтра», «через 5 дн.», «просрочен на 2 дн.» — факт, без оценок.
String dueLabel(DateTime due, DateTime now) {
  final d = daysUntil(due, now);
  if (d == 0) return 'сегодня';
  if (d == 1) return 'завтра';
  if (d > 1) return 'через $d дн.';
  return 'просрочен на ${-d} дн.';
}

/// Неоплаченные сроки до [withinDays] дней вперёд, включая просроченные; ближайшие первыми.
List<(Bill, DateTime)> upcomingBills(Iterable<Bill> bills, DateTime now, {int withinDays = 14}) {
  final out = <(Bill, DateTime)>[];
  for (final b in bills) {
    final d = nextDue(b);
    if (d != null && daysUntil(d, now) <= withinDays) out.add((b, d));
  }
  out.sort((a, b) => a.$2.compareTo(b.$2));
  return out;
}
