import 'package:flutter/material.dart';

import '../../core/finance_stats.dart';
import '../../core/currency.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../painters/chart_painters.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';
import 'finance_screen.dart';

/// Вкладка «Капитал»: капитал, доход и траты, вход в учёт операций, график зарплаты.
class WealthScreen extends StatefulWidget {
  final AppController controller;
  const WealthScreen({super.key, required this.controller});

  @override
  State<WealthScreen> createState() => _WealthScreenState();
}

class _WealthScreenState extends State<WealthScreen> {
  AppController get c => widget.controller;

  void _openFinance() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FinanceScreen(controller: c)));
  }

  /// Карточка-вход в учёт финансов: факт за текущий месяц.
  Widget _financeEntryCard(MonthTotals fact) {
    return Material(
      color: AppColors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.tile), side: const BorderSide(color: AppColors.border)),
      child: InkWell(
        onTap: _openFinance,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_outlined, color: AppColors.text),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Учёт операций', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      fact.isEmpty
                          ? 'Доходы и расходы по категориям, динамика по месяцам'
                          : '${monthYear(c.now)}: +${fmtMoney(fact.income)} / −${fmtCur(fact.expense)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editWealthDialog() async {
    final r = await showFormDialog(
      context,
      title: 'План и капитал',
      actionLabel: 'Сохранить',
      accent: AppColors.accent,
      fields: [
        // при счетах капитал считается по остаткам — вручную не задаётся
        if (!c.netWorthFromAccounts) FieldSpec('w', 'Чистый капитал, если счетов нет ($cur)', initial: '${c.netWorth}', numeric: true),
        FieldSpec('i', 'Плановый доход в месяц ($cur)', initial: '${c.monthlyIncome}', numeric: true),
        FieldSpec('e', 'Плановые расходы в месяц ($cur)', initial: '${c.monthlyExpense}', numeric: true),
      ],
    );
    if (r == null || !mounted) return;
    c.updateWealth(netWorth: r['w'] == null ? null : parseInt(r['w']!), income: parseInt(r['i']!), expense: parseInt(r['e']!));
  }

  Future<void> _addAccountDialog() async {
    final r = await showFormDialog(
      context,
      title: 'Новый счёт',
      actionLabel: 'Добавить',
      accent: AppColors.accent,
      fields: [
        const FieldSpec('n', 'Название (вклад, брокер, карта, наличные)'),
        FieldSpec('b', 'Остаток сейчас ($cur, долг — со знаком минус)', numeric: true),
      ],
      validate: (v) => v['n']!.trim().isNotEmpty && parseInt(v['b']!.replaceAll('−', '-')) != null,
    );
    if (r == null || !mounted) return;
    c.addAccount(r['n']!, parseInt(r['b']!.replaceAll('−', '-'))!);
  }

  Future<void> _balanceDialog(Account a) async {
    final r = await showFormDialog(
      context,
      title: a.name,
      actionLabel: 'Записать остаток',
      accent: AppColors.accent,
      fields: [
        FieldSpec('b', 'Остаток сейчас ($cur)', numeric: true, initial: '${a.latest.amount}'),
        FieldSpec('n', 'Название', initial: a.name),
      ],
      validate: (v) => v['n']!.trim().isNotEmpty && parseInt(v['b']!.replaceAll('−', '-')) != null,
    );
    if (r == null || !mounted) return;
    final b = parseInt(r['b']!.replaceAll('−', '-'))!;
    if (b != a.latest.amount) c.setAccountBalance(a.id, b); // новый снимок, прежние остаются в истории
    if (r['n']!.trim() != a.name) c.renameAccount(a.id, r['n']!);
  }

  Future<void> _removeAccount(Account a) async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить счёт?',
      message: 'Счёт «${a.name}» и история его остатков (${a.history.length}) будут удалены навсегда.',
      confirmLabel: 'Удалить',
      danger: true,
    );
    if (ok && mounted) c.removeAccount(a.id);
  }

  /// Капитал: по счетам (у каждой цифры — дата снимка) или указанный вручную.
  Widget _capitalTile(bool isFact, int savingsRate) {
    final accounts = c.accounts;
    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      decoration: tileDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(accounts.isEmpty ? 'Чистый капитал · указан вручную' : 'Чистый капитал · по счетам', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Text(fmtCur(c.netWorth), key: const ValueKey('net_worth'), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -0.8)),
          const SizedBox(height: 4),
          Text(
            'Норма сбережений ${isFact ? 'за месяц (по операциям)' : '(по плану)'}: $savingsRate%',
            style: TextStyle(color: savingsRate >= 0 ? AppColors.green : AppColors.red, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          for (final a in accounts)
            InkWell(
              onTap: () => _balanceDialog(a),
              onLongPress: () => _removeAccount(a),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: Text(a.name, style: const TextStyle(fontSize: 14))),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(fmtCur(a.latest.amount), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text('снимок ${fmtDate(a.latest.at)}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (accounts.isEmpty)
            const Text('Добавьте счета — капитал будет считаться по их остаткам, с датой каждого.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('add_account'),
              onPressed: _addAccountDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Счёт'),
            ),
          ),
        ],
      ),
    );
  }

  /// Добавить точку графика зарплаты или изменить существующую ([index]).
  Future<void> _addSalaryStepDialog([int? index]) async {
    final old = (index != null && index >= 0 && index < c.salaryHistory.length) ? c.salaryHistory[index] : null;
    final r = await showFormDialog(
      context,
      title: old == null ? 'Новая точка на графике ЗП' : 'Изменить точку графика ЗП',
      actionLabel: old == null ? 'Добавить' : 'Сохранить',
      fields: [
        FieldSpec('y', 'Год / Период', initial: old?.year ?? ''),
        FieldSpec('r', 'Должность', initial: old?.role ?? ''),
        FieldSpec('s', 'Зарплата ($cur)', numeric: true, initial: old == null ? '' : '${old.salary}'),
      ],
      validate: (v) => v['y']!.isNotEmpty && (parseInt(v['s']!) ?? 0) > 0,
    );
    if (r == null || !mounted) return;
    if (old == null) {
      c.addSalaryStep(r['y']!, r['r']!, parseInt(r['s']!)!);
    } else {
      c.updateSalaryStep(index!, r['y']!, r['r']!, parseInt(r['s']!)!);
    }
  }

  Widget _salaryRow(int i) {
    final st = c.salaryHistory[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
      decoration: tileDecoration(radius: 20),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(st.year, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(child: Text(st.role.isEmpty ? '—' : st.role, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12))),
          Text('${fmtCur(st.salary)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          IconButton(icon: const Icon(Icons.edit, size: 16, color: AppColors.muted), tooltip: 'Изменить', onPressed: () => _addSalaryStepDialog(i)),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.white24),
            tooltip: 'Удалить точку',
            onPressed: () {
              final removed = c.removeSalaryStep(i);
              if (removed == null) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: const Text('Точка удалена'),
                  action: SnackBarAction(label: 'Отменить', onPressed: () => c.insertSalaryStep(i, removed)),
                ));
            },
          ),
        ],
      ),
    );
  }

  /// Поток месяца: факт по журналу операций; план — подписью ниже. Операций нет — так и сказано.
  Widget _flowTile(String title, int fact, int plan, bool noTx, Color color) => Container(
        padding: const EdgeInsets.all(16),
        decoration: tileDecoration(radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$title · ${monthNames[c.now.month - 1].toLowerCase()}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 6),
            Text(noTx ? 'нет операций' : fmtCur(fact), style: TextStyle(fontSize: noTx ? 15 : 18, fontWeight: FontWeight.w600, color: noTx ? AppColors.muted : color)),
            if (plan > 0) Text('план ${fmtCur(plan)}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final fact = monthTotals(c.transactions, c.now.year, c.now.month);
    final factRate = fact.savingsRate;
    final isFact = factRate != null;
    final savingsRate = (factRate ?? (c.monthlyIncome > 0 ? ((c.monthlyIncome - c.monthlyExpense) / c.monthlyIncome) * 100 : 0)).round();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Материальное', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -0.8)),
                    SizedBox(height: 2),
                    Text('Капитал, доход, финансы', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  ],
                ),
              ),
              IconButton(tooltip: 'Изменить капитал и доход', onPressed: _editWealthDialog, icon: const Icon(Icons.edit_outlined, color: AppColors.text, size: 22)),
            ],
          ),
          const SizedBox(height: 12),
          _capitalTile(isFact, savingsRate),
          const SizedBox(height: 16),
          // факт — из журнала операций; ручные цифры — план и подписаны так
          Row(
            children: [
              Expanded(child: _flowTile('Доход', fact.income, c.monthlyIncome, fact.isEmpty, AppColors.text)),
              const SizedBox(width: 12),
              Expanded(child: _flowTile('Траты', fact.expense, c.monthlyExpense, fact.isEmpty, AppColors.red)),
            ],
          ),
          const SizedBox(height: 12),
          _financeEntryCard(fact),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(child: Text('Рост зарплаты', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              IconButton(tooltip: 'Добавить точку зарплаты', onPressed: _addSalaryStepDialog, icon: const Icon(Icons.add_circle_outline, color: AppColors.text, size: 24)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            height: 200,
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
            child: CustomPaint(size: Size.infinite, painter: SalaryLineChartPainter(steps: c.salaryHistory)),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < c.salaryHistory.length; i++) _salaryRow(i),
        ],
      ),
    );
  }
}
