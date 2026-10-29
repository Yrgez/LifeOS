import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/finance_stats.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/models/models.dart';
import 'package:life_os/state/app_controller.dart';

void main() {
  late DateTime now;
  late MemoryAppRepository repo;

  AppController build({AppData? data}) {
    repo = MemoryAppRepository(data: data);
    return AppController(repo, clock: () => now, saveDelay: Duration.zero);
  }

  Future<AppController> make() async {
    final c = build();
    await c.load();
    return c;
  }

  setUp(() => now = DateTime(2026, 10, 24, 12));

  group('правка операции', () {
    test('смена суммы пересчитывает капитал на разницу', () async {
      final c = await make();
      final w0 = c.netWorth;
      c.addTransaction(categoryId: 'food', amount: 1000);
      final id = c.transactions.single.id;
      expect(c.updateTransaction(id, categoryId: 'food', amount: 1500, at: c.transactions.single.at, affectsNetWorth: true), isTrue);
      expect(c.netWorth, w0 - 1500);
    });

    test('смена категории с расхода на доход меняет знак влияния', () async {
      final c = await make();
      final w0 = c.netWorth;
      c.addTransaction(categoryId: 'food', amount: 1000);
      final t = c.transactions.single;
      c.updateTransaction(t.id, categoryId: 'salary', amount: 1000, at: t.at, affectsNetWorth: true);
      expect(c.transactions.single.isIncome, isTrue);
      expect(c.netWorth, w0 + 1000);
    });

    test('переключение «вне капитала» убирает и возвращает влияние', () async {
      final c = await make();
      final w0 = c.netWorth;
      c.addTransaction(categoryId: 'food', amount: 700);
      final t = c.transactions.single;
      c.updateTransaction(t.id, categoryId: 'food', amount: 700, at: t.at, affectsNetWorth: false);
      expect(c.netWorth, w0);
      c.updateTransaction(t.id, categoryId: 'food', amount: 700, at: t.at, affectsNetWorth: true);
      expect(c.netWorth, w0 - 700);
    });

    test('перенос даты пересортировывает список; идентификатор сохраняется', () async {
      final c = await make();
      c.addTransaction(categoryId: 'food', amount: 1, at: DateTime(2026, 10, 20));
      c.addTransaction(categoryId: 'food', amount: 2, at: DateTime(2026, 10, 22));
      final first = c.transactions.first;
      c.updateTransaction(first.id, categoryId: 'food', amount: 1, at: DateTime(2026, 10, 23), affectsNetWorth: true);
      expect(c.transactions.map((t) => t.amount), [2, 1]);
      expect(c.transactions.last.id, first.id);
    });

    test('некорректные данные отклоняются без изменений', () async {
      final c = await make();
      c.addTransaction(categoryId: 'food', amount: 500);
      final t = c.transactions.single;
      final w = c.netWorth;
      expect(c.updateTransaction(t.id, categoryId: 'food', amount: 0, at: t.at, affectsNetWorth: true), isFalse);
      expect(c.updateTransaction(t.id, categoryId: 'нет', amount: 5, at: t.at, affectsNetWorth: true), isFalse);
      expect(c.updateTransaction('нет', categoryId: 'food', amount: 5, at: t.at, affectsNetWorth: true), isFalse);
      expect(c.netWorth, w);
      expect(c.transactions.single.amount, 500);
    });
  });

  group('бюджеты', () {
    test('лимит задаётся, меняется и снимается; только для расходов', () async {
      final c = await make();
      expect(c.setBudget('food', 20000), isTrue);
      expect(c.budgets['food'], 20000);
      expect(c.setBudget('food', 15000), isTrue);
      expect(c.budgets['food'], 15000);
      expect(c.setBudget('food', 0), isTrue);
      expect(c.budgets.containsKey('food'), isFalse);
      expect(c.setBudget('salary', 1000), isFalse); // доходная категория
      expect(c.setBudget('нет', 1000), isFalse);
    });

    test('budgetStatuses: превышение, остаток, категории с лимитом без трат', () {
      final txs = [
        MoneyTx(id: '1', at: DateTime(2026, 10, 5), isIncome: false, amount: 25000, categoryId: 'food'),
        MoneyTx(id: '2', at: DateTime(2026, 10, 6), isIncome: false, amount: 5000, categoryId: 'fun'),
        MoneyTx(id: '3', at: DateTime(2026, 9, 6), isIncome: false, amount: 99999, categoryId: 'food'), // другой месяц
      ];
      final r = budgetStatuses(txs, {'food': 20000, 'transport': 8000}, 2026, 10);
      final food = r.firstWhere((s) => s.categoryId == 'food');
      expect(food.spent, 25000);
      expect(food.exceeded, isTrue);
      expect(food.left, -5000);
      final tr = r.firstWhere((s) => s.categoryId == 'transport');
      expect(tr.spent, 0);
      expect(tr.exceeded, isFalse);
      final fun = r.firstWhere((s) => s.categoryId == 'fun');
      expect(fun.hasLimit, isFalse);
      expect(fun.exceeded, isFalse);
      expect(r.first.categoryId, 'food'); // по убыванию трат
    });

    test('лимиты переживают сохранение', () async {
      final c = await make();
      c.setBudget('food', 12345);
      await c.flush();
      final c2 = build(data: repo.data);
      await c2.load();
      expect(c2.budgets['food'], 12345);
    });
  });

  group('повторяющиеся операции', () {
    test('день ещё не наступил — операции нет; наступил — появляется один раз', () async {
      final c = await make();
      final w0 = c.netWorth;
      expect(c.addRecurring(categoryId: 'housing', amount: 40000, dayOfMonth: 25), isTrue);
      expect(c.transactions, isEmpty); // сегодня 24-е

      now = DateTime(2026, 10, 25, 8);
      await c.onResume();
      expect(c.transactions.length, 1);
      final t = c.transactions.single;
      expect(t.recurringId, c.recurring.single.id);
      expect(t.at, DateTime(2026, 10, 25, 9));
      expect(c.netWorth, w0 - 40000);

      await c.onResume(); // повторный вызов ничего не дублирует
      now = DateTime(2026, 10, 30);
      await c.onResume();
      expect(c.transactions.length, 1);
    });

    test('правило на сегодняшнее число срабатывает сразу', () async {
      final c = await make();
      c.addRecurring(categoryId: 'subs', amount: 500, dayOfMonth: 24);
      expect(c.transactions.length, 1);
    });

    test('день уже прошёл к моменту создания — первая операция в следующем месяце', () async {
      final c = await make();
      c.addRecurring(categoryId: 'subs', amount: 500, dayOfMonth: 10);
      expect(c.transactions, isEmpty);
      now = DateTime(2026, 11, 9);
      await c.onResume();
      expect(c.transactions, isEmpty);
      now = DateTime(2026, 11, 10);
      await c.onResume();
      expect(c.transactions.length, 1);
      expect(c.transactions.single.at.month, 11);
    });

    test('пропущенные месяцы догоняются, каждый ровно один раз', () async {
      final c = await make();
      c.addRecurring(categoryId: 'salary', amount: 100000, dayOfMonth: 5);
      now = DateTime(2027, 1, 20);
      await c.onResume();
      // ноя, дек, янв (октябрьское 5-е было до создания правила)
      expect(c.transactions.map((t) => t.at.month), [11, 12, 1]);
      expect(c.transactions.every((t) => t.isIncome), isTrue);
    });

    test('31-е число в коротком месяце → последний день месяца', () async {
      final c = await make();
      now = DateTime(2027, 1, 31, 12);
      c.addRecurring(categoryId: 'subs', amount: 100, dayOfMonth: 31); // янв: сразу
      now = DateTime(2027, 2, 27);
      await c.onResume();
      expect(c.transactions.length, 1); // 28 февраля ещё не наступило
      now = DateTime(2027, 2, 28);
      await c.onResume();
      expect(c.transactions.length, 2);
      expect(c.transactions.last.at.day, 28);
    });

    test('вручную удалённая операция не воссоздаётся', () async {
      final c = await make();
      final w0 = c.netWorth;
      c.addRecurring(categoryId: 'subs', amount: 500, dayOfMonth: 24);
      c.deleteTransaction(c.transactions.single.id);
      await c.onResume();
      now = DateTime(2026, 10, 28);
      await c.onResume();
      expect(c.transactions, isEmpty);
      expect(c.netWorth, w0);
    });

    test('удаление правила оставляет созданные операции и останавливает новые', () async {
      final c = await make();
      c.addRecurring(categoryId: 'subs', amount: 500, dayOfMonth: 24);
      c.removeRecurring(c.recurring.single.id);
      expect(c.recurring, isEmpty);
      expect(c.transactions.length, 1);
      now = DateTime(2026, 12, 1);
      await c.onResume();
      expect(c.transactions.length, 1);
    });

    test('«вне капитала» в правиле не меняет капитал', () async {
      final c = await make();
      final w0 = c.netWorth;
      c.addRecurring(categoryId: 'subs', amount: 500, dayOfMonth: 24, affectsNetWorth: false);
      expect(c.transactions.single.affectsNetWorth, isFalse);
      expect(c.netWorth, w0);
    });

    test('смена суток при открытом приложении (refresh) создаёт операции', () async {
      final c = await make();
      c.addRecurring(categoryId: 'subs', amount: 500, dayOfMonth: 25);
      now = DateTime(2026, 10, 25, 0, 5);
      c.refresh();
      expect(c.transactions.length, 1);
    });

    test('некорректные правила отклоняются', () async {
      final c = await make();
      expect(c.addRecurring(categoryId: 'нет', amount: 100, dayOfMonth: 5), isFalse);
      expect(c.addRecurring(categoryId: 'food', amount: 0, dayOfMonth: 5), isFalse);
      expect(c.addRecurring(categoryId: 'food', amount: 100, dayOfMonth: 0), isFalse);
      expect(c.addRecurring(categoryId: 'food', amount: 100, dayOfMonth: 32), isFalse);
      expect(c.recurring, isEmpty);
    });

    test('правила и состояние переживают сохранение; повторной генерации нет', () async {
      final c = await make();
      c.addRecurring(categoryId: 'subs', amount: 500, dayOfMonth: 24);
      await c.flush();
      final c2 = build(data: repo.data);
      await c2.load();
      expect(c2.recurring.single.lastMonth, '2026-10');
      expect(c2.transactions.length, 1);
    });
  });

  group('точки графика зарплаты', () {
    test('изменение и удаление, «Отменить» возвращает на место', () async {
      final c = await make();
      final n = c.salaryHistory.length;
      expect(c.updateSalaryStep(0, '2022', 'Intern', 50000), isTrue);
      expect(c.salaryHistory.first.year, '2022');
      expect(c.salaryHistory.first.salary, 50000);

      final removed = c.removeSalaryStep(1)!;
      expect(c.salaryHistory.length, n - 1);
      c.insertSalaryStep(1, removed);
      expect(c.salaryHistory.length, n);
      expect(c.salaryHistory[1].year, removed.year);
    });

    test('граничные случаи', () async {
      final c = await make();
      expect(c.updateSalaryStep(99, '2022', 'x', 1), isFalse);
      expect(c.updateSalaryStep(0, ' ', 'x', 1), isFalse);
      expect(c.updateSalaryStep(0, '2022', 'x', 0), isFalse);
      expect(c.removeSalaryStep(-1), isNull);
    });
  });

  group('ключи месяцев', () {
    test('ymKey / parseYm / daysInMonth', () {
      expect(ymKey(DateTime(2026, 3, 9)), '2026-03');
      expect(parseYm('2026-03'), DateTime(2026, 3, 1));
      expect(parseYm(''), isNull);
      expect(parseYm('2026-13'), isNull);
      expect(parseYm('26-03'), isNull);
      expect(daysInMonth(DateTime(2028, 2, 1)), 29);
      expect(daysInMonth(DateTime(2027, 2, 1)), 28);
    });
  });

  group('правка правила повторяющейся операции', () {
    String addRule(AppController c, {int amount = 500, int day = 24, String cat = 'subs', bool nw = true}) {
      c.addRecurring(categoryId: cat, amount: amount, dayOfMonth: day, affectsNetWorth: nw);
      return c.recurring.last.id;
    }

    test('новые значения действуют на следующие месяцы, созданные операции не меняются', () async {
      final c = await make();
      final w0 = c.netWorth;
      final id = addRule(c); // 24-е — сегодня: октябрьская операция создаётся сразу
      expect(c.transactions.single.amount, 500);

      expect(c.updateRecurring(id, categoryId: 'subs', amount: 700, dayOfMonth: 24, affectsNetWorth: true), isTrue);
      expect(c.transactions.length, 1);
      expect(c.transactions.single.amount, 500);

      now = DateTime(2026, 11, 24, 9);
      await c.onResume();
      expect(c.transactions.map((t) => t.amount), [500, 700]);
      expect(c.netWorth, w0 - 500 - 700);
    });

    test('смена числа в текущем месяце не дублирует уже созданную операцию', () async {
      final c = await make();
      final id = addRule(c);
      c.updateRecurring(id, categoryId: 'subs', amount: 500, dayOfMonth: 28, affectsNetWorth: true);
      now = DateTime(2026, 10, 28);
      await c.onResume();
      expect(c.transactions.length, 1); // октябрь уже обработан
      now = DateTime(2026, 11, 28);
      await c.onResume();
      expect(c.transactions.length, 2);
      expect(c.transactions.last.at.day, 28);
    });

    test('новое число уже наступило сегодня — операция создаётся сразу', () async {
      final c = await make();
      final id = addRule(c, day: 28);
      expect(c.transactions, isEmpty);
      c.updateRecurring(id, categoryId: 'subs', amount: 500, dayOfMonth: 24, affectsNetWorth: true);
      expect(c.transactions.length, 1);
    });

    test('число раньше даты начала правила не создаёт операцию задним числом', () async {
      final c = await make();
      final id = addRule(c, day: 30); // начало — 24 октября
      c.updateRecurring(id, categoryId: 'subs', amount: 500, dayOfMonth: 10, affectsNetWorth: true);
      expect(c.transactions, isEmpty); // 10 октября — до начала правила
      now = DateTime(2026, 11, 10);
      await c.onResume();
      expect(c.transactions.length, 1);
      expect(c.transactions.single.at.month, 11);
    });

    test('смена категории с расхода на доход меняет тип будущих операций', () async {
      final c = await make();
      final id = addRule(c);
      c.updateRecurring(id, categoryId: 'salary', amount: 100000, dayOfMonth: 24, affectsNetWorth: true);
      now = DateTime(2026, 11, 24);
      await c.onResume();
      expect(c.transactions.first.isIncome, isFalse);
      expect(c.transactions.last.isIncome, isTrue);
      expect(c.transactions.last.recurringId, id);
    });

    test('«вне капитала» в правиле переключается для будущих операций', () async {
      final c = await make();
      final w0 = c.netWorth;
      final id = addRule(c);
      c.updateRecurring(id, categoryId: 'subs', amount: 500, dayOfMonth: 24, affectsNetWorth: false);
      now = DateTime(2026, 11, 24);
      await c.onResume();
      expect(c.transactions.last.affectsNetWorth, isFalse);
      expect(c.netWorth, w0 - 500); // только октябрьская (до правки)
    });

    test('идентификатор, дата начала и обработанные месяцы сохраняются', () async {
      final c = await make();
      final id = addRule(c);
      final before = c.recurring.single;
      c.updateRecurring(id, categoryId: 'fun', amount: 900, dayOfMonth: 25, note: ' кино ', affectsNetWorth: true);
      final r = c.recurring.single;
      expect(r.id, before.id);
      expect(r.start, before.start);
      expect(r.lastMonth, before.lastMonth);
      expect(r.categoryId, 'fun');
      expect(r.amount, 900);
      expect(r.dayOfMonth, 25);
      expect(r.note, 'кино');
      expect(c.recurring.length, 1);
    });

    test('некорректные данные и неизвестное правило отклоняются без изменений', () async {
      final c = await make();
      final id = addRule(c);
      expect(c.updateRecurring(id, categoryId: 'нет', amount: 100, dayOfMonth: 5, affectsNetWorth: true), isFalse);
      expect(c.updateRecurring(id, categoryId: 'food', amount: 0, dayOfMonth: 5, affectsNetWorth: true), isFalse);
      expect(c.updateRecurring(id, categoryId: 'food', amount: 100, dayOfMonth: 0, affectsNetWorth: true), isFalse);
      expect(c.updateRecurring(id, categoryId: 'food', amount: 100, dayOfMonth: 32, affectsNetWorth: true), isFalse);
      expect(c.updateRecurring('нет', categoryId: 'food', amount: 100, dayOfMonth: 5, affectsNetWorth: true), isFalse);
      expect(c.recurring.single.amount, 500);
      expect(c.recurring.single.categoryId, 'subs');
    });

    test('правка переживает сохранение и загрузку, старые месяцы не воссоздаются', () async {
      final c = await make();
      final id = addRule(c);
      c.updateRecurring(id, categoryId: 'subs', amount: 750, dayOfMonth: 24, affectsNetWorth: true);
      await c.flush();
      final c2 = build(data: repo.data);
      await c2.load();
      expect(c2.recurring.single.amount, 750);
      expect(c2.transactions.length, 1);
      expect(c2.transactions.single.amount, 500);
    });
  });
}
