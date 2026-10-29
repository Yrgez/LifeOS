import 'package:flutter/material.dart';

import '../../core/finance_stats.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_controller.dart';
import '../painters/chart_painters.dart';
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.gold.withValues(alpha: 0.3))),
      child: InkWell(
        onTap: _openFinance,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.receipt_long, color: AppColors.gold),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('УЧЁТ ОПЕРАЦИЙ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.6)),
                    const SizedBox(height: 2),
                    Text(
                      fact.isEmpty
                          ? 'Доходы и расходы по категориям, динамика по месяцам'
                          : '${monthYear(c.now)}: +${fmtMoney(fact.income)} / −${fmtMoney(fact.expense)} ₽',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editWealthDialog() async {
    final r = await showFormDialog(
      context,
      title: 'Параметры капитала',
      actionLabel: 'Сохранить',
      accent: AppColors.gold,
      fields: [
        FieldSpec('w', 'Чистый капитал (₽)', initial: '${c.netWorth}', numeric: true),
        FieldSpec('i', 'Доход в месяц (₽)', initial: '${c.monthlyIncome}', numeric: true),
        FieldSpec('e', 'Расходы в месяц (₽)', initial: '${c.monthlyExpense}', numeric: true),
      ],
    );
    if (r == null || !mounted) return;
    c.updateWealth(netWorth: parseInt(r['w']!), income: parseInt(r['i']!), expense: parseInt(r['e']!));
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
        FieldSpec('s', 'Зарплата (₽)', numeric: true, initial: old == null ? '' : '${old.salary}'),
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
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(st.year, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          Expanded(child: Text(st.role.isEmpty ? '—' : st.role, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12))),
          Text('${fmtMoney(st.salary)} ₽', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          IconButton(icon: const Icon(Icons.edit, size: 16, color: Colors.white38), tooltip: 'Изменить', onPressed: () => _addSalaryStepDialog(i)),
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

  Widget _moneyTile(String title, int value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${fmtMoney(value)} ₽', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fact = monthTotals(c.transactions, c.now.year, c.now.month);
    final factRate = fact.savingsRate;
    final isFact = factRate != null;
    final savingsRate = (factRate ?? (c.monthlyIncome > 0 ? ((c.monthlyIncome - c.monthlyExpense) / c.monthlyIncome) * 100 : 0)).round();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('КАПИТАЛ И КАРЬЕРА', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(onPressed: _editWealthDialog, icon: const Icon(Icons.edit, color: AppColors.gold, size: 22)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1F242F), AppColors.card], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ЧИСТЫЙ КАПИТАЛ (NET WORTH)', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('${fmtMoney(c.netWorth)} ₽', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.gold)),
                const SizedBox(height: 4),
                Text(
                  'Норма сбережений ${isFact ? 'за месяц (факт)' : '(план)'}: $savingsRate%',
                  style: TextStyle(color: savingsRate >= 0 ? AppColors.green : AppColors.red, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _moneyTile('ДОХОД / МЕС', c.monthlyIncome, Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: _moneyTile('ТРАТЫ / МЕС', c.monthlyExpense, AppColors.red)),
            ],
          ),
          const SizedBox(height: 12),
          _financeEntryCard(fact),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ГРАФИК РОСТА ЗАРПЛАТЫ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(onPressed: _addSalaryStepDialog, icon: const Icon(Icons.add_circle, color: AppColors.green, size: 24)),
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
