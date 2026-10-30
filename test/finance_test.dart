import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/finance_categories.dart';
import 'package:life_os/core/finance_stats.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/models/models.dart';
import 'package:life_os/state/app_controller.dart';

MoneyTx tx(DateTime at, int amount, {bool income = false, String cat = 'food', String id = ''}) =>
    MoneyTx(id: id.isEmpty ? '${at.microsecondsSinceEpoch}_$amount$cat' : id, at: at, isIncome: income, amount: amount, categoryId: cat);

void main() {
  group('статистика', () {
    final txs = [
      tx(DateTime(2026, 10, 3), 100000, income: true, cat: 'salary'),
      tx(DateTime(2026, 10, 5), 30000, cat: 'food'),
      tx(DateTime(2026, 10, 9), 10000, cat: 'food'),
      tx(DateTime(2026, 10, 12), 50000, cat: 'housing'),
      tx(DateTime(2026, 9, 30), 5000, cat: 'fun'),
      tx(DateTime(2025, 10, 5), 777, cat: 'fun'), // тот же месяц, но прошлый год
    ];

    test('monthTotals учитывает год и месяц', () {
      final t = monthTotals(txs, 2026, 10);
      expect(t.income, 100000);
      expect(t.expense, 90000);
      expect(t.saldo, 10000);
      expect(t.savingsRate, closeTo(10, 1e-9));
    });

    test('без дохода норма сбережений = null; пустой месяц', () {
      expect(monthTotals(txs, 2026, 9).savingsRate, isNull);
      expect(monthTotals(txs, 2026, 1).isEmpty, isTrue);
    });

    test('расходы по категориям по убыванию, доходы не входят', () {
      final r = expenseByCategory(txs, 2026, 10);
      expect(r.map((e) => e.key), ['housing', 'food']);
      expect(r.first.value, 50000);
      expect(r.last.value, 40000); // food: 30000 + 10000
    });

    test('lastMonthsTotals: последний элемент — текущий месяц, переход через год', () {
      final r = lastMonthsTotals(txs, DateTime(2026, 10, 15), 3);
      expect(r.length, 3);
      expect(r.last.income, 100000);
      expect(r[1].expense, 5000); // сентябрь
      final jan = lastMonthsTotals(txs, DateTime(2026, 1, 10), 2);
      expect(jan.length, 2); // декабрь 2025 + январь 2026 без ошибок
    });

    test('addMonths корректно переходит через границу года', () {
      expect(addMonths(DateTime(2026, 1, 20), -1), DateTime(2025, 12, 1));
      expect(addMonths(DateTime(2026, 12, 5), 1), DateTime(2027, 1, 1));
    });

    test('txsOfMonth по убыванию времени', () {
      final r = txsOfMonth(txs, 2026, 10);
      expect(r.first.at, DateTime(2026, 10, 12));
      expect(r.length, 4);
    });
  });

  group('категории', () {
    test('идентификаторы уникальны, есть и доходы, и расходы', () {
      final ids = kFinCategories.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(kFinCategories.any((c) => c.isIncome), isTrue);
      expect(kFinCategories.any((c) => !c.isIncome), isTrue);
    });
    test('finCategory', () {
      expect(finCategory('salary')!.isIncome, isTrue);
      expect(finCategory('food')!.isIncome, isFalse);
      expect(finCategory('нет'), isNull);
    });
  });

  group('MoneyTx', () {
    test('JSON туда-обратно и знак', () {
      final t = MoneyTx(id: 'a', at: DateTime.fromMillisecondsSinceEpoch(1760000000000), isIncome: false, amount: 500, categoryId: 'food', note: 'кофе', affectsNetWorth: false);
      final b = MoneyTx.fromJson(t.toJson());
      expect(b.at, t.at);
      expect(b.note, 'кофе');
      expect(b.affectsNetWorth, isFalse);
      expect(b.signed, -500);
    });
    test('старые данные без полей: заметка пустая, капитал учитывается', () {
      final b = MoneyTx.fromJson({'id': 'a', 't': 1760000000000, 'in': true, 'a': 10, 'c': 'salary'});
      expect(b.note, '');
      expect(b.affectsNetWorth, isTrue);
      expect(b.signed, 10);
    });
  });

  group('контроллер', () {
    late DateTime now;
    late MemoryAppRepository repo;

    Future<AppController> make() async {
      repo = MemoryAppRepository();
      final c = AppController(repo, clock: () => now, saveDelay: Duration.zero);
      await c.load();
      return c;
    }

    setUp(() => now = DateTime(2026, 10, 24, 12));

    test('расход уменьшает капитал, доход увеличивает; тип берётся из категории', () async {
      final c = await make();
      final w0 = c.netWorth;
      expect(c.addTransaction(categoryId: 'food', amount: 1500), isTrue);
      expect(c.netWorth, w0 - 1500);
      expect(c.transactions.single.isIncome, isFalse);
      expect(c.addTransaction(categoryId: 'salary', amount: 100000), isTrue);
      expect(c.netWorth, w0 - 1500 + 100000);
      expect(c.transactions.last.isIncome, isTrue);
    });

    test('«вне капитала» не меняет капитал ни при добавлении, ни при удалении', () async {
      final c = await make();
      final w0 = c.netWorth;
      c.addTransaction(categoryId: 'food', amount: 700, affectsNetWorth: false);
      expect(c.netWorth, w0);
      c.deleteTransaction(c.transactions.single.id);
      expect(c.netWorth, w0);
    });

    test('удаление откатывает капитал, «Отменить» применяет снова (без дублей)', () async {
      final c = await make();
      final w0 = c.netWorth;
      c.addTransaction(categoryId: 'food', amount: 2000);
      final removed = c.deleteTransaction(c.transactions.single.id)!;
      expect(c.netWorth, w0);
      c.restoreTransaction(removed);
      c.restoreTransaction(removed);
      expect(c.transactions.length, 1);
      expect(c.netWorth, w0 - 2000);
    });

    test('некорректный ввод отклоняется', () async {
      final c = await make();
      expect(c.addTransaction(categoryId: 'food', amount: 0), isFalse);
      expect(c.addTransaction(categoryId: 'food', amount: -5), isFalse);
      expect(c.addTransaction(categoryId: 'нет', amount: 100), isFalse);
      expect(c.transactions, isEmpty);
    });

    test('операции сортируются по времени, задним числом тоже', () async {
      final c = await make();
      c.addTransaction(categoryId: 'food', amount: 1, at: DateTime(2026, 10, 20));
      c.addTransaction(categoryId: 'food', amount: 2, at: DateTime(2026, 10, 10));
      c.addTransaction(categoryId: 'food', amount: 3, at: DateTime(2026, 10, 15));
      expect(c.transactions.map((t) => t.amount), [2, 3, 1]);
    });

    test('лимит операций: старейшие удаляются, капитал не трогается', () async {
      final data = AppData.defaults(now: now);
      for (int i = 0; i < kMaxTransactions; i++) {
        data.transactions.add(tx(DateTime(2020, 1, 1).add(Duration(minutes: i)), 1, id: 'old$i'));
      }
      repo = MemoryAppRepository(data: data);
      final c = AppController(repo, clock: () => now, saveDelay: Duration.zero);
      await c.load();
      final w0 = c.netWorth;
      c.addTransaction(categoryId: 'food', amount: 10);
      expect(c.transactions.length, kMaxTransactions);
      expect(c.transactions.any((t) => t.id == 'old0'), isFalse);
      expect(c.netWorth, w0 - 10);
    });

    test('операции переживают сохранение и загрузку', () async {
      final c = await make();
      c.addTransaction(categoryId: 'salary', amount: 123456, note: 'аванс');
      await c.flush();
      final c2 = AppController(repo, clock: () => now, saveDelay: Duration.zero);
      await c2.load();
      expect(c2.transactions.single.note, 'аванс');
      expect(c2.transactions.single.amount, 123456);
    });

    test('цель «капитал ≥» реагирует на операции', () async {
      final c = await make();
      c.addGoal('Накопить', '', []);
      final id = c.goals.last.id;
      c.addCheckpoint(id, '', link: MetricLink(kind: MetricLink.netWorth, target: (c.netWorth + 1000).toDouble()));
      final cp = c.goals.last.checkpoints.single;
      expect(cp.isCompleted, isFalse);
      c.addTransaction(categoryId: 'side', amount: 1000);
      expect(cp.isCompleted, isTrue);
      c.deleteTransaction(c.transactions.single.id);
      expect(cp.isCompleted, isFalse);
    });
  });
}
