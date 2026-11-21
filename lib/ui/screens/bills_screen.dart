import 'package:flutter/material.dart';

import '../../core/bills.dart';
import '../../core/currency.dart';
import '../../core/finance_categories.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/bill.dart';
import '../../state/app_controller.dart';
import '../widgets/adaptive_pair.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';
import '../widgets/toast.dart';

/// Строка срока: «Интернет · 650 ₽ · завтра». Просрочка — словами и белым текстом вместо серого.
Widget billDueLine(Bill b, DateTime due, DateTime now, {TextStyle? style}) {
  final overdue = daysUntil(due, now) < 0;
  return Text(
    [if (b.amount != null) fmtCur(b.amount!), '${fmtDate(due)} · ${dueLabel(due, now)}'].join(' · '),
    style: (style ?? const TextStyle(fontSize: 13)).copyWith(color: overdue ? AppColors.text : AppColors.muted),
  );
}

/// Счета к оплате: ближайшие сроки, оплата в одно нажатие, история оплат, архив.
class BillsScreen extends StatelessWidget {
  final AppController controller;
  const BillsScreen({super.key, required this.controller});

  AppController get c => controller;

  static Map<String, String> _expenseCats({String? keep}) => {for (final x in pickableFinCategories(income: false, keep: keep)) x.id: x.name};

  Future<void> _edit(BuildContext context, [Bill? b]) async {
    final paid = b != null && b.payments.isNotEmpty;
    final r = await showFormDialog(
      context,
      title: b == null ? 'Новый счёт' : 'Счёт',
      actionLabel: 'Сохранить',
      accent: AppColors.accent,
      fields: [
        FieldSpec('t', 'Название: интернет, аренда, страховка', initial: b?.title ?? ''),
        FieldSpec('a', 'Сумма, $cur (пусто — меняется)', numeric: true, initial: b?.amount?.toString() ?? ''),
        FieldSpec('c', 'Категория расхода', initial: b?.categoryId ?? 'other_exp', options: _expenseCats(keep: b?.categoryId)),
        if (!paid) ...[
          FieldSpec('d', 'Ближайший срок (дд.мм.гггг)', initial: fmtDate(b == null ? c.now : DateTime.parse(b.firstDue))),
          FieldSpec('r', 'Повтор', initial: b?.repeat ?? BillRepeat.month, options: BillRepeat.labels),
        ],
      ],
      validate: (v) {
        final amountOk = v['a']!.trim().isEmpty || ((parseInt(v['a']!) ?? 0) > 0);
        return v['t']!.trim().isNotEmpty && amountOk && (paid || parseDate(v['d']!) != null);
      },
    );
    if (r == null || !context.mounted) return;
    final amount = r['a']!.trim().isEmpty ? null : parseInt(r['a']!);
    final ok = b == null
        ? c.addBill(title: r['t']!, amount: amount, categoryId: r['c']!, firstDue: parseDate(r['d']!)!, repeat: r['r']!) != null
        : c.updateBill(b.id, title: r['t']!, amount: amount, categoryId: r['c']!, firstDue: paid ? null : parseDate(r['d']!), repeat: paid ? null : r['r']);
    if (!ok) showToast(context, 'Счёт не сохранён: проверьте данные');
  }

  Future<void> _pay(BuildContext context, Bill b) async {
    var amount = b.amount;
    if (amount == null) {
      final r = await showFormDialog(
        context,
        title: 'Оплата: ${b.title}',
        actionLabel: 'Оплачено',
        accent: AppColors.accent,
        fields: [FieldSpec('a', 'Сумма, $cur (пусто — без операции)', numeric: true)],
        validate: (v) => v['a']!.trim().isEmpty || (parseInt(v['a']!) ?? 0) > 0,
      );
      if (r == null || !context.mounted) return;
      amount = r['a']!.trim().isEmpty ? null : parseInt(r['a']!);
    }
    final due = c.payBill(b.id, amount: amount, createTransaction: amount != null);
    if (!context.mounted) return;
    if (due == null) {
      if (amount != null && c.transactionsFull) showToast(context, 'Журнал операций заполнен — новые операции не принимаются');
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${b.title}: срок ${fmtDate(due)} оплачен${amount != null ? ' · операция ${fmtCur(amount)}' : ''}'),
        action: SnackBarAction(label: 'Отменить', onPressed: () => c.undoLastBillPayment(b.id)),
      ));
  }

  Future<void> _menu(BuildContext context, Bill b, String action) async {
    switch (action) {
      case 'edit':
        await _edit(context, b);
      case 'undo':
        final ok = await confirmDialog(context,
            title: 'Отменить последнюю оплату?', message: 'Запись об оплате и созданная ею операция будут удалены.', confirmLabel: 'Отменить оплату', danger: true);
        if (ok) c.undoLastBillPayment(b.id);
      case 'archive':
        c.archiveBill(b.id, archived: b.archivedAt == null);
      case 'remove':
        final ok = await confirmDialog(context,
            title: 'Удалить счёт?',
            message: '«${b.title}» и история его оплат будут удалены. Операции расхода останутся в журнале. Чтобы просто перестать платить — «В архив».',
            confirmLabel: 'Удалить',
            danger: true);
        if (ok) c.removeBill(b.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Счета к оплате'), backgroundColor: AppColors.panel, elevation: 0),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('add_bill'),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        tooltip: 'Новый счёт',
        onPressed: () => _edit(context),
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final list = c.bills;
          final now = c.now;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text('Счетов нет. Добавьте то, что платится регулярно: интернет, аренду, страховку, подписки.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ),
              for (final b in list) _tile(context, b, now),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(BuildContext context, Bill b, DateTime now) {
    final due = nextDue(b);
    final last = b.payments.isEmpty ? null : b.payments.last;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(b.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: b.archivedAt == null ? AppColors.text : AppColors.muted)),
        if (due != null) billDueLine(b, due, now) else Text(b.archivedAt != null ? 'в архиве' : 'оплачен', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        Text(
          [BillRepeat.labels[b.repeat]!, if (last != null) 'последняя оплата ${fmtDate(last.paidAt)}'].join(' · '),
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    );
    final actions = <Widget>[
      if (due != null)
        TextButton(key: ValueKey('pay_${b.id}'), onPressed: () => _pay(context, b), child: const Text('Оплачено')),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: AppColors.muted, size: 20),
        onSelected: (v) => _menu(context, b, v),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Изменить')),
          if (b.payments.isNotEmpty) const PopupMenuItem(value: 'undo', child: Text('Отменить последнюю оплату')),
          PopupMenuItem(value: 'archive', child: Text(b.archivedAt == null ? 'В архив' : 'Вернуть из архива')),
          const PopupMenuItem(value: 'remove', child: Text('Удалить')),
        ],
      ),
    ];
    return Container(
      key: ValueKey('bill_${b.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      decoration: tileDecoration(radius: 20),
      // при крупном шрифте кнопки — под описанием: иначе название и срок рвутся посередине слова
      child: largeText(context)
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, Row(mainAxisAlignment: MainAxisAlignment.end, children: actions)])
          : Row(children: [Expanded(child: info), ...actions]),
    );
  }
}
