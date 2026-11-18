// Счёт со сроком оплаты: интернет, страховка, налог, подписка. Чистый Dart, без Flutter.
//
// Срок — дата; повтор — раз в месяц или в год (или разово). Оплата каждого срока записывается в [payments]:
// история оплат не теряется. Если оплата создала операцию расхода, хранится её id.

import 'day_snapshot.dart' show isValidDayKey, dayFromKey;

class BillRepeat {
  static const none = 'none';
  static const month = 'month';
  static const year = 'year';
  static const all = [none, month, year];
  static const labels = {none: 'разово', month: 'каждый месяц', year: 'каждый год'};
}

class BillPayment {
  final String due; // yyyy-MM-dd — какой срок оплачен
  final DateTime paidAt;
  final String? txId; // операция расхода, созданная при оплате
  const BillPayment({required this.due, required this.paidAt, this.txId});

  Map<String, dynamic> toJson() => {'due': due, 't': paidAt.millisecondsSinceEpoch, if (txId != null) 'tx': txId};

  static BillPayment? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final due = raw['due'], t = raw['t'], tx = raw['tx'];
    if (due is! String || !isValidDayKey(due) || t is! num || !t.isFinite || (tx != null && tx is! String)) return null;
    return BillPayment(due: due, paidAt: DateTime.fromMillisecondsSinceEpoch(t.toInt()), txId: tx as String?);
  }
}

class Bill {
  static const maxTitle = 80;
  static const maxPayments = 2000;

  final String id;
  String title;
  int? amount; // ожидаемая сумма; null — меняется от раза к разу
  String categoryId; // категория расхода для операции при оплате
  String firstDue; // yyyy-MM-dd — первый срок; от него считаются следующие
  String repeat;
  final DateTime createdAt;
  final List<BillPayment> payments;
  DateTime? archivedAt; // больше не платится; история остаётся

  Bill({
    required this.id,
    required this.title,
    this.amount,
    this.categoryId = 'other_exp',
    required this.firstDue,
    this.repeat = BillRepeat.month,
    required this.createdAt,
    List<BillPayment> payments = const [],
    this.archivedAt,
  }) : payments = List.of(payments);

  bool get isValid =>
      id.trim().isNotEmpty &&
      title.trim().isNotEmpty &&
      title.length <= maxTitle &&
      (amount == null || amount! > 0) &&
      categoryId.isNotEmpty &&
      isValidDayKey(firstDue) &&
      BillRepeat.all.contains(repeat) &&
      payments.length <= maxPayments;

  /// Срок номер [n] (с 0). Месячный повтор с 31-го числа в коротком месяце — последний день месяца.
  DateTime dueAt(int n) {
    final f = dayFromKey(firstDue);
    int lastDay(int y, int m) => DateTime(y, m + 1, 0).day;
    switch (repeat) {
      case BillRepeat.month:
        final y = f.year + (f.month - 1 + n) ~/ 12, m = (f.month - 1 + n) % 12 + 1;
        return DateTime(y, m, f.day > lastDay(y, m) ? lastDay(y, m) : f.day);
      case BillRepeat.year:
        final y = f.year + n;
        return DateTime(y, f.month, f.day > lastDay(y, f.month) ? lastDay(y, f.month) : f.day);
      default:
        return f;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (amount != null) 'a': amount,
        'c': categoryId,
        'first': firstDue,
        'rep': repeat,
        'ct': createdAt.millisecondsSinceEpoch,
        if (payments.isNotEmpty) 'paid': payments.map((p) => p.toJson()).toList(),
        if (archivedAt != null) 'arch': archivedAt!.millisecondsSinceEpoch,
      };

  factory Bill.fromJson(Map<String, dynamic> j) => tryFromJson(j) ?? (throw const FormatException('Bill'));

  static Bill? tryFromJson(Map<String, dynamic> j) {
    DateTime? t(Object? v) => v is num && v.isFinite && v == v.roundToDouble() ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;
    final id = j['id'], title = j['title'], a = j['a'], c = j['c'], first = j['first'], rep = j['rep'], ct = t(j['ct']);
    final paidRaw = j['paid'] ?? const [];
    if (id is! String || title is! String || c is! String || first is! String || rep is! String || ct == null || paidRaw is! List) return null;
    if (a != null && (a is! num || a != a.roundToDouble())) return null;
    if (j['arch'] != null && t(j['arch']) == null) return null;
    final paid = <BillPayment>[];
    for (final r in paidRaw) {
      final p = BillPayment.tryFromJson(r);
      if (p == null) return null;
      paid.add(p);
    }
    final b = Bill(
      id: id,
      title: title,
      amount: (a as num?)?.toInt(),
      categoryId: c,
      firstDue: first,
      repeat: rep,
      createdAt: ct,
      payments: paid,
      archivedAt: t(j['arch']),
    );
    return b.isValid ? b : null;
  }
}
