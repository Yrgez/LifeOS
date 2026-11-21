import 'package:flutter_test/flutter_test.dart';
import 'package:catenna/core/resource_stats.dart';
import 'package:catenna/data/app_data.dart';
import 'package:catenna/data/app_repository.dart';
import 'package:catenna/models/life_event.dart';
import 'package:catenna/models/models.dart';
import 'package:catenna/state/app_controller.dart';

void main() {
  final now = DateTime(2026, 11, 15, 12);
  var n = 0;
  LifeEvent ev(DateTime at, List<String> dims, {List<String> procs = const [], int? min, int? rub, int? en}) => LifeEvent(
        id: 'e${n++}',
        at: at,
        recordedAt: at,
        dimensions: dims,
        kind: LifeEventKind.action,
        title: 't',
        processIds: procs,
        cost: ResourceCost(minutes: min, money: rub, energy: en),
      );

  test('границы периода: по календарным дням, сегодня включительно', () {
    final b = periodBounds(now, 7);
    expect(b.from, DateTime(2026, 11, 9));
    expect(b.to, DateTime(2026, 11, 16));
  });

  test('распределение по измерениям, процессам и прошлому периоду', () {
    const body = LifeDimension.body, mind = LifeDimension.mind, mat = LifeDimension.material;
    final events = [
      ev(DateTime(2026, 11, 14, 8), [body], procs: ['run'], min: 40, en: 3),
      ev(DateTime(2026, 11, 13, 19), [mind], procs: ['java'], min: 90, en: 4),
      ev(DateTime(2026, 11, 12, 19), [mind], procs: ['java'], min: 60),
      ev(DateTime(2026, 11, 10, 12), [mind, mat], procs: ['java'], min: 15, rub: 12000), // курс: два измерения
      ev(DateTime(2026, 11, 9, 0), [mat], rub: 3000), // первая минута периода, без процесса
      ev(DateTime(2026, 11, 15, 23, 59), [body]), // поздно сегодня — входит, ресурсы не указаны
      ev(DateTime(2026, 11, 8, 23, 59), [body], min: 500), // прошлый период
      ev(DateTime(2026, 11, 2), [body], min: 30), // прошлый период
      ev(DateTime(2026, 11, 1, 23), [body], min: 999), // раньше прошлого периода
    ];
    final txs = [
      MoneyTx(id: 't1', at: DateTime(2026, 11, 10), isIncome: false, amount: 12000, categoryId: 'education'),
      MoneyTx(id: 't2', at: DateTime(2026, 11, 11), isIncome: true, amount: 100000, categoryId: 'salary'),
      MoneyTx(id: 't3', at: DateTime(2026, 11, 1), isIncome: false, amount: 5000, categoryId: 'food'), // вне периода
    ];
    final b = resourceBreakdown(current: events, transactions: txs, now: now, days: 7);

    expect(b.total.events, 6);
    expect(b.total.minutes, 205);
    expect(b.total.minutesKnown, 4);
    expect(b.total.money, 15000);
    expect(b.total.energy, {3: 1, 4: 1});

    expect(b.byDimension.keys, [body, mind, mat]);
    expect(b.byDimension[body]!.minutes, 40);
    expect(b.byDimension[body]!.events, 2);
    expect(b.byDimension[mind]!.minutes, 165);
    expect(b.byDimension[mat]!.money, 15000);
    expect(b.byDimension[mat]!.minutes, 15); // курс учтён и в «разуме», и в «материальном»

    expect(b.byProcess.map((p) => p.processId), ['java', 'run']); // по убыванию времени
    expect(b.byProcess.first.summary.minutes, 165);
    expect(b.withoutProcess.events, 2);
    expect(b.withoutProcess.money, 3000);

    expect(b.previous.events, 2);
    expect(b.previous.minutes, 530);

    expect(b.financeExpense, 12000);
    expect(b.financeExpenseCount, 1);
    expect(b.elapsedMinutes, (6 * 24 + 12) * 60);
  });

  test('пустой период', () {
    final b = resourceBreakdown(current: const [], transactions: const [], now: now, days: 30);
    expect(b.total.events, 0);
    expect(b.byProcess, isEmpty);
    expect(b.byDimension.values.every((s) => s.events == 0), isTrue);
  });

  test('контроллер: отменённые и заменённые версии в распределение не входят', () async {
    var t = now;
    final c = AppController(MemoryAppRepository(), clock: () => t, saveDelay: const Duration(days: 1), initialData: (x) => AppData.blank(now: x));
    await c.load();
    final a = c.addEvent(title: 'a', dimensions: [LifeDimension.body], cost: const ResourceCost(minutes: 60))!;
    final v = c.addEvent(title: 'v', dimensions: [LifeDimension.body], cost: const ResourceCost(minutes: 999))!;
    c.voidEvent(v);
    t = t.add(const Duration(minutes: 1));
    c.reviseEvent(a, title: 'a', dimensions: [LifeDimension.body], kind: LifeEventKind.action, at: now, cost: const ResourceCost(minutes: 45));
    final b = c.resourceBreakdownFor(7);
    expect(b.total.events, 1);
    expect(b.total.minutes, 45);
  });
}
