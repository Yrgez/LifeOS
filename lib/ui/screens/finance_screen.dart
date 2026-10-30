import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/finance_categories.dart';
import '../../core/finance_stats.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/workout_stats.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../painters/chart_painters.dart';
import '../widgets/form_dialog.dart';

Map<String, String> _allCategoryOptions() => {for (final k in kFinCategories) k.id: '${k.isIncome ? 'Доход' : 'Расход'} • ${k.name}'};

const _capitalOptions = {'1': 'Да — изменит чистый капитал', '0': 'Нет — только учёт'};

void _toast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Диалог добавления (или правки, если задан [existing]) операции. Тип определяется категорией.
Future<void> showTransactionDialog(BuildContext context, AppController c, {MoneyTx? existing}) async {
  final r = await showFormDialog(
    context,
    title: existing == null ? 'Новая операция' : 'Изменить операцию',
    actionLabel: 'Сохранить',
    accent: AppColors.gold,
    fields: [
      FieldSpec('c', 'Категория', initial: existing?.categoryId ?? 'food', options: _allCategoryOptions()),
      FieldSpec('a', 'Сумма (₽)', numeric: true, initial: existing == null ? '' : '${existing.amount}'),
      FieldSpec('d', 'Дата (дд.мм.гггг)', initial: fmtDate(existing?.at ?? c.now)),
      FieldSpec('n', 'Заметка (необязательно)', initial: existing?.note ?? ''),
      FieldSpec('w', 'Учитывать в капитале', initial: (existing?.affectsNetWorth ?? true) ? '1' : '0', options: _capitalOptions),
    ],
    validate: (v) => (parseNum(v['a']!) ?? 0) > 0 && parseDate(v['d']!) != null,
  );
  if (r == null || !context.mounted) return;

  final date = parseDate(r['d']!)!;
  final now = c.now;
  final DateTime at;
  if (existing != null && dateOnly(date) == dateOnly(existing.at)) {
    at = existing.at; // дата не менялась — время суток сохраняем
  } else if (dateOnly(date) == dateOnly(now)) {
    at = now;
  } else {
    at = DateTime(date.year, date.month, date.day, 12);
  }

  final amount = parseNum(r['a']!)!.round();
  final ok = existing == null
      ? c.addTransaction(categoryId: r['c']!, amount: amount, at: at, note: r['n']!, affectsNetWorth: r['w'] == '1')
      : c.updateTransaction(existing.id, categoryId: r['c']!, amount: amount, at: at, note: r['n']!, affectsNetWorth: r['w'] == '1');
  if (ok) _toast(context, existing == null ? 'Операция добавлена' : 'Операция изменена');
}

Future<void> showAddTransactionDialog(BuildContext context, AppController c) => showTransactionDialog(context, c);

/// Лимит расходов на месяц по категории. Пустое значение или 0 снимает лимит.
Future<void> showBudgetDialog(BuildContext context, AppController c, {String? categoryId}) async {
  final expenseOptions = {for (final k in kFinCategories) if (!k.isIncome) k.id: k.name};
  final cat = categoryId != null && expenseOptions.containsKey(categoryId) ? categoryId : expenseOptions.keys.first;
  final current = c.budgets[cat];
  final r = await showFormDialog(
    context,
    title: 'Лимит на месяц',
    actionLabel: 'Сохранить',
    accent: AppColors.gold,
    fields: [
      FieldSpec('c', 'Категория расходов', initial: cat, options: expenseOptions),
      FieldSpec('l', 'Лимит (₽ в месяц, пусто — без лимита)', numeric: true, initial: current == null ? '' : '$current'),
    ],
    validate: (v) => v['l']!.isEmpty || (parseNum(v['l']!) ?? -1) >= 0,
  );
  if (r == null || !context.mounted) return;
  c.setBudget(r['c']!, (parseNum(r['l']!) ?? 0).round());
}

/// Диалог правила повторяющейся операции: создание или правка ([existing]).
Future<void> showRecurringDialog(BuildContext context, AppController c, {RecurringTx? existing}) async {
  final r = await showFormDialog(
    context,
    title: existing == null ? 'Повторяющаяся операция' : 'Изменить правило',
    actionLabel: existing == null ? 'Создать' : 'Сохранить',
    accent: AppColors.gold,
    fields: [
      FieldSpec('c', 'Категория', initial: existing?.categoryId ?? 'housing', options: _allCategoryOptions()),
      FieldSpec('a', 'Сумма (₽)', numeric: true, initial: existing == null ? '' : '${existing.amount}'),
      FieldSpec('d', 'Число месяца (1–31)', numeric: true, initial: '${existing?.dayOfMonth ?? c.now.day}'),
      FieldSpec('n', 'Заметка (необязательно)', initial: existing?.note ?? ''),
      FieldSpec('w', 'Учитывать в капитале', initial: (existing?.affectsNetWorth ?? true) ? '1' : '0', options: _capitalOptions),
    ],
    validate: (v) => (parseNum(v['a']!) ?? 0) > 0 && (parseInt(v['d']!) ?? 0) >= 1 && (parseInt(v['d']!) ?? 0) <= 31,
  );
  if (r == null) return;
  final amount = parseNum(r['a']!)!.round();
  final day = parseInt(r['d']!)!;
  if (existing == null) {
    c.addRecurring(categoryId: r['c']!, amount: amount, dayOfMonth: day, note: r['n']!, affectsNetWorth: r['w'] == '1');
  } else {
    c.updateRecurring(existing.id, categoryId: r['c']!, amount: amount, dayOfMonth: day, note: r['n']!, affectsNetWorth: r['w'] == '1');
  }
}

/// Список правил повторяющихся операций.
Future<void> showRecurringSheet(BuildContext context, AppController c) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.card,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) => ListenableBuilder(
      listenable: c,
      builder: (_, __) {
        final rules = c.recurring;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('ПОВТОРЯЮЩИЕСЯ ОПЕРАЦИИ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.6)),
                    TextButton.icon(
                      onPressed: () => showRecurringDialog(sheetContext, c),
                      icon: const Icon(Icons.add, size: 16, color: AppColors.gold),
                      label: const Text('Добавить', style: TextStyle(color: AppColors.gold, fontSize: 12)),
                    ),
                  ],
                ),
                const Text('Нажмите на правило, чтобы изменить. Изменения касаются будущих операций — созданные не меняются.', style: TextStyle(color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 4),
                if (rules.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('Правил нет. Создайте правило (аренда, подписка, зарплата) — операция будет появляться сама каждый месяц.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in rules)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            onTap: () => showRecurringDialog(sheetContext, c, existing: r),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: (finCategory(r.categoryId)?.color ?? Colors.white24).withValues(alpha: 0.18),
                              child: Icon(finCategory(r.categoryId)?.icon ?? Icons.help_outline, size: 16, color: finCategory(r.categoryId)?.color ?? Colors.white38),
                            ),
                            title: Text('${finCategory(r.categoryId)?.name ?? r.categoryId}${r.note.isEmpty ? '' : ' • ${r.note}'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              'каждое ${r.dayOfMonth}-е • ${finCategory(r.categoryId)?.isIncome == true ? '+' : '−'}${fmtMoney(r.amount)} ₽${r.affectsNetWorth ? '' : ' • вне капитала'}',
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 18),
                              tooltip: 'Удалить правило (созданные операции останутся)',
                              onPressed: () => c.removeRecurring(r.id),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Учёт финансов: месяц, итоги, динамика, расходы по категориям, список операций.
class FinanceScreen extends StatefulWidget {
  final AppController controller;
  const FinanceScreen({super.key, required this.controller});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  AppController get c => widget.controller;
  late DateTime _month = addMonths(c.now, 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('УЧЁТ ФИНАНСОВ', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: AppColors.panel,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.autorenew),
            tooltip: 'Повторяющиеся операции',
            onPressed: () => showRecurringSheet(context, c),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.gold,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Операция', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => showTransactionDialog(context, c),
      ),
      body: ListenableBuilder(listenable: c, builder: (context, _) => _content()),
    );
  }

  bool get _isCurrentMonth => _month.year == c.now.year && _month.month == c.now.month;

  Widget _content() {
    final all = c.transactions;
    final totals = monthTotals(all, _month.year, _month.month);
    final monthTxs = txsOfMonth(all, _month.year, _month.month);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _monthSelector(),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _tile('ДОХОД', '+${fmtMoney(totals.income)} ₽', AppColors.green, '')),
            const SizedBox(width: 8),
            Expanded(child: _tile('РАСХОД', '−${fmtMoney(totals.expense)} ₽', AppColors.red, '')),
            const SizedBox(width: 8),
            Expanded(
              child: _tile(
                'БАЛАНС',
                '${totals.saldo >= 0 ? '+' : '−'}${fmtMoney(totals.saldo.abs())} ₽',
                totals.saldo >= 0 ? AppColors.gold : AppColors.red,
                totals.savingsRate == null ? 'нет дохода' : 'сбережения ${totals.savingsRate!.round()}%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _trendCard(),
        const SizedBox(height: 12),
        _categoriesCard(totals),
        const SizedBox(height: 16),
        const Text('ОПЕРАЦИИ', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._list(monthTxs),
      ],
    );
  }

  Widget _monthSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _month = addMonths(_month, -1))),
        SizedBox(width: 170, child: Text(monthYear(_month), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _isCurrentMonth ? null : () => setState(() => _month = addMonths(_month, 1)),
        ),
      ],
    );
  }

  Widget _tile(String title, String value, Color color, String sub) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color))),
          const SizedBox(height: 2),
          Text(sub.isEmpty ? ' ' : sub, style: const TextStyle(color: Colors.white38, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _trendCard() {
    final months = lastMonthsTotals(c.transactions, _month, 6);
    final labels = List.generate(6, (i) => monthShortName(addMonths(_month, i - 5).month));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ДИНАМИКА ЗА 6 МЕСЯЦЕВ', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
              Row(children: [
                const CircleAvatar(radius: 4, backgroundColor: AppColors.green),
                const SizedBox(width: 4),
                const Text('доход', style: TextStyle(color: Colors.white38, fontSize: 10)),
                const SizedBox(width: 8),
                const CircleAvatar(radius: 4, backgroundColor: AppColors.red),
                const SizedBox(width: 4),
                const Text('расход', style: TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 110,
            width: double.infinity,
            child: CustomPaint(
              painter: DualBarsPainter(
                a: months.map((m) => m.income.toDouble()).toList(),
                b: months.map((m) => m.expense.toDouble()).toList(),
                labels: labels,
                colorA: AppColors.green,
                colorB: AppColors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoriesCard(MonthTotals totals) {
    final statuses = budgetStatuses(c.transactions, c.budgets, _month.year, _month.month);
    final maxSpent = statuses.isEmpty ? 0 : statuses.map((e) => e.spent).reduce(max);
    final exceeded = statuses.where((s) => s.exceeded).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('РАСХОДЫ ПО КАТЕГОРИЯМ', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () => showBudgetDialog(context, c),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 24)),
                icon: const Icon(Icons.speed, size: 14, color: AppColors.gold),
                label: const Text('Лимиты', style: TextStyle(color: AppColors.gold, fontSize: 11)),
              ),
            ],
          ),
          if (exceeded > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text('Превышено лимитов: $exceeded', style: const TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 8),
          if (statuses.isEmpty)
            const Text('В этом месяце расходов и лимитов нет', style: TextStyle(color: Colors.white38, fontSize: 12))
          else
            for (final st in statuses)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _categoryRow(st, totals.expense, maxSpent),
              ),
        ],
      ),
    );
  }

  Widget _categoryRow(BudgetStatus st, int total, int maxSum) {
    final cat = finCategory(st.categoryId);
    final color = st.exceeded ? AppColors.red : (cat?.color ?? Colors.white38);
    final pct = total <= 0 ? 0 : (st.spent / total * 100).round();
    final double value = st.hasLimit ? min(1.0, st.ratio) : (maxSum <= 0 ? 0.0 : st.spent / maxSum);
    final label = st.hasLimit
        ? '${fmtMoney(st.spent)} / ${fmtMoney(st.limit)} ₽'
        : '${fmtMoney(st.spent)} ₽ · $pct%';
    return InkWell(
      onTap: () => showBudgetDialog(context, c, categoryId: st.categoryId),
      child: Row(
        children: [
          Icon(cat?.icon ?? Icons.help_outline, size: 16, color: cat?.color ?? Colors.white38),
          const SizedBox(width: 8),
          SizedBox(width: 92, child: Text(cat?.name ?? st.categoryId, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
          Expanded(
            child: LinearProgressIndicator(
              value: value,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              backgroundColor: const Color(0xFF222834),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: Text(
              st.exceeded ? '$label ⚠' : label,
              textAlign: TextAlign.right,
              style: TextStyle(color: st.exceeded ? AppColors.red : Colors.white54, fontSize: 10, fontWeight: st.exceeded ? FontWeight.bold : FontWeight.normal),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _list(List<MoneyTx> txs) {
    if (txs.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('В этом месяце операций нет.\nНажмите «+ Операция», чтобы добавить.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 12))),
        ),
      ];
    }
    final out = <Widget>[];
    int? currentDay;
    for (final t in txs) {
      final di = dayIndex(t.at);
      if (di != currentDay) {
        currentDay = di;
        final dayTotal = txs.where((x) => dayIndex(x.at) == di).fold(0, (a, x) => a + x.signed);
        out.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(shortDate(t.at), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              Text('${dayTotal >= 0 ? '+' : '−'}${fmtMoney(dayTotal.abs())} ₽', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ));
      }
      out.add(_txTile(t));
    }
    return out;
  }

  Widget _txTile(MoneyTx t) {
    final cat = finCategory(t.categoryId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showTransactionDialog(context, c, existing: t),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Row(
        children: [
          CircleAvatar(radius: 15, backgroundColor: (cat?.color ?? Colors.white24).withValues(alpha: 0.18), child: Icon(cat?.icon ?? Icons.help_outline, size: 15, color: cat?.color ?? Colors.white38)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cat?.name ?? t.categoryId, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                if (t.note.isNotEmpty || !t.affectsNetWorth || t.recurringId != null)
                  Text(
                    [if (t.recurringId != null) '↻ повтор', if (t.note.isNotEmpty) t.note, if (!t.affectsNetWorth) 'вне капитала'].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ),
          Text(
            '${t.isIncome ? '+' : '−'}${fmtMoney(t.amount)} ₽',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: t.isIncome ? AppColors.green : Colors.white),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 18),
            tooltip: 'Удалить операцию',
            onPressed: () {
              final removed = c.deleteTransaction(t.id);
              if (removed == null) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: const Text('Операция удалена'),
                  action: SnackBarAction(label: 'Отменить', onPressed: () => c.restoreTransaction(removed)),
                ));
            },
          ),
        ],
            ),
          ),
        ),
      ),
    );
  }
}
