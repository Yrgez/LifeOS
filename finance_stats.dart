import '../models/models.dart';

/// Чистая статистика по операциям: без Flutter и состояния.

class MonthTotals {
  final int income;
  final int expense;
  const MonthTotals(this.income, this.expense);

  int get saldo => income - expense;

  /// Норма сбережений в процентах; null — дохода не было, считать нечего.
  double? get savingsRate => income <= 0 ? null : (income - expense) / income * 100;

  bool get isEmpty => income == 0 && expense == 0;
}

MonthTotals monthTotals(Iterable<MoneyTx> txs, int year, int month) {
  int inc = 0, exp = 0;
  for (final t in txs) {
    if (t.at.year != year || t.at.month != month) continue;
    if (t.isIncome) {
      inc += t.amount;
    } else {
      exp += t.amount;
    }
  }
  return MonthTotals(inc, exp);
}

/// Расходы месяца по категориям, по убыванию суммы.
List<MapEntry<String, int>> expenseByCategory(Iterable<MoneyTx> txs, int year, int month) {
  final m = <String, int>{};
  for (final t in txs) {
    if (t.isIncome || t.at.year != year || t.at.month != month) continue;
    m[t.categoryId] = (m[t.categoryId] ?? 0) + t.amount;
  }
  return m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// Итоги за последние [n] месяцев; последний элемент — месяц [now].
List<MonthTotals> lastMonthsTotals(Iterable<MoneyTx> txs, DateTime now, int n) {
  final list = txs.toList();
  return List.generate(n, (i) {
    final d = addMonths(now, i - (n - 1));
    return monthTotals(list, d.year, d.month);
  });
}

/// Первое число месяца, сдвинутого на [delta] (корректно переходит через год).
DateTime addMonths(DateTime d, int delta) => DateTime(d.year, d.month + delta, 1);

/// Операции месяца по убыванию времени.
List<MoneyTx> txsOfMonth(Iterable<MoneyTx> txs, int year, int month) =>
    txs.where((t) => t.at.year == year && t.at.month == month).toList()..sort((a, b) => b.at.compareTo(a.at));

/// «2026-10»
String ymKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

/// Первое число месяца из «гггг-мм»; null — строка некорректна.
DateTime? parseYm(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final mo = int.parse(m.group(2)!);
  if (mo < 1 || mo > 12) return null;
  return DateTime(int.parse(m.group(1)!), mo, 1);
}

int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// Состояние лимита категории за месяц.
class BudgetStatus {
  final String categoryId;
  final int spent;
  final int limit; // 0 — лимит не задан
  const BudgetStatus(this.categoryId, this.spent, this.limit);

  bool get hasLimit => limit > 0;
  bool get exceeded => hasLimit && spent > limit;
  int get left => limit - spent;
  double get ratio => hasLimit ? spent / limit : 0;
}

/// Категории расходов месяца: потраченное и лимит; сначала с наибольшими тратами.
/// Включает категории, где есть лимит, даже если трат не было.
List<BudgetStatus> budgetStatuses(Iterable<MoneyTx> txs, Map<String, int> budgets, int year, int month) {
  final spent = {for (final e in expenseByCategory(txs, year, month)) e.key: e.value};
  final ids = {...spent.keys, ...budgets.keys};
  final list = [for (final id in ids) BudgetStatus(id, spent[id] ?? 0, budgets[id] ?? 0)];
  list.sort((a, b) => b.spent.compareTo(a.spent));
  return list;
}
