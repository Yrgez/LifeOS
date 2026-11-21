part of '../app_controller.dart';

/// Счета со сроком оплаты. Оплата записывается в историю счёта и по желанию создаёт операцию расхода.
/// Расширение того же library: работает с состоянием контроллера напрямую, мутации — только через `_commit`.
extension BillOps on AppController {
  static const maxBills = 300;

  /// Активные — по ближайшему сроку, затем архив.
  List<Bill> get bills {
    final active = [for (final b in _d.bills) if (b.archivedAt == null) b]
      ..sort((a, b) => (nextDue(a) ?? DateTime(9999)).compareTo(nextDue(b) ?? DateTime(9999)));
    return [...active, for (final b in _d.bills) if (b.archivedAt != null) b];
  }

  Bill? billById(String id) => _d.bills.where((b) => b.id == id).firstOrNull;

  List<(Bill, DateTime)> upcomingBillsWithin(int days) => upcomingBills(_d.bills, _clock(), withinDays: days);

  String? addBill({required String title, int? amount, String categoryId = 'other_exp', required DateTime firstDue, String repeat = BillRepeat.month}) {
    final cat = finCategory(categoryId);
    if (cat == null || cat.isIncome || _d.bills.length >= maxBills) return null;
    final now = _clock();
    final b = Bill(
      id: 'bill_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
      title: title.trim(),
      amount: amount,
      categoryId: categoryId,
      firstDue: dayKey(firstDue),
      repeat: repeat,
      createdAt: now,
    );
    if (!b.isValid) return null;
    _commit(() => _d.bills.add(b));
    return b.id;
  }

  /// Меняет описание счёта. Первый срок и повтор после первой оплаты не меняются — иначе история оплат
  /// перестанет совпадать со сроками (для нового графика заведите новый счёт).
  bool updateBill(String id, {required String title, int? amount, required String categoryId, DateTime? firstDue, String? repeat}) {
    final b = billById(id);
    final cat = finCategory(categoryId);
    if (b == null || cat == null || cat.isIncome) return false;
    final schedule = firstDue != null && dayKey(firstDue) != b.firstDue || repeat != null && repeat != b.repeat;
    if (schedule && b.payments.isNotEmpty) return false;
    final probe = Bill(
      id: b.id,
      title: title.trim(),
      amount: amount,
      categoryId: categoryId,
      firstDue: firstDue == null ? b.firstDue : dayKey(firstDue),
      repeat: repeat ?? b.repeat,
      createdAt: b.createdAt,
    );
    if (!probe.isValid) return false;
    _commit(() {
      b
        ..title = probe.title
        ..amount = probe.amount
        ..categoryId = probe.categoryId
        ..firstDue = probe.firstDue
        ..repeat = probe.repeat;
    });
    return true;
  }

  /// Отмечает ближайший срок оплаченным. С [createTransaction] (и известной суммой) добавляется операция
  /// расхода с пометкой счёта. Возвращает оплаченный срок или null.
  DateTime? payBill(String id, {bool createTransaction = true, int? amount, DateTime? paidAt}) {
    final b = billById(id);
    if (b == null) return null;
    final due = nextDue(b);
    if (due == null || b.payments.length >= Bill.maxPayments) return null;
    final now = _clock();
    final when = paidAt ?? now;
    if (when.isAfter(now.add(const Duration(minutes: 5)))) return null;
    final sum = amount ?? b.amount;
    if (sum != null && sum <= 0) return null;
    if (createTransaction && sum != null && transactionsFull) return null;
    _commit(() {
      String? txId;
      if (createTransaction && sum != null) {
        final tx = MoneyTx(
          id: 'tx_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}',
          at: when,
          isIncome: false,
          amount: sum,
          categoryId: b.categoryId,
          note: 'Счёт: ${b.title}',
        );
        _insertTx(tx, applyNetWorth: true);
        txId = tx.id;
      }
      b.payments.add(BillPayment(due: dayKey(due), paidAt: when, txId: txId));
    });
    return due;
  }

  /// Отменяет последнюю оплату (ошибочное нажатие). Созданная ею операция удаляется, влияние на капитал
  /// откатывается. Явное действие с подтверждением.
  bool undoLastBillPayment(String id) {
    final b = billById(id);
    if (b == null || b.payments.isEmpty) return false;
    _commit(() {
      final p = b.payments.removeLast();
      final i = p.txId == null ? -1 : _d.transactions.indexWhere((t) => t.id == p.txId);
      if (i >= 0) {
        final t = _d.transactions.removeAt(i);
        _pending.deleteTx(t.id);
        if (t.affectsNetWorth) _d.netWorth -= t.signed;
      }
    });
    return true;
  }

  /// В архив: счёт больше не платится, история оплат остаётся. [archived] = false — вернуть.
  bool archiveBill(String id, {bool archived = true}) {
    final b = billById(id);
    if (b == null) return false;
    _commit(() => b.archivedAt = archived ? _clock() : null);
    return true;
  }

  /// Удаляет счёт с историей оплат (операции в журнале остаются). Явное действие с подтверждением.
  bool removeBill(String id) {
    final i = _d.bills.indexWhere((b) => b.id == id);
    if (i < 0) return false;
    _commit(() => _d.bills.removeAt(i));
    return true;
  }
}
