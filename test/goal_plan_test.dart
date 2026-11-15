import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/goal_stats.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/models/life_event.dart';
import 'package:life_os/models/life_process.dart';
import 'package:life_os/models/models.dart';
import 'package:life_os/state/app_controller.dart';

void main() {
  late DateTime now;
  AppController make() => AppController(
        MemoryAppRepository(),
        clock: () => now,
        saveDelay: const Duration(days: 1),
        initialData: (n) => AppData.blank(now: n),
      );

  setUp(() => now = DateTime(2026, 11, 15, 12));

  group('план цели', () {
    test('JSON: круг, пустой план не хранится, битый план отвергает цель', () {
      final g = GlobalGoal(id: 'g', title: 'Java', category: 'Карьера', checkpoints: [], plan: const GoalPlan(minutes: 6000, money: 50000));
      final back = GlobalGoal.tryFromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>)!;
      expect(back.plan!.minutes, 6000);
      expect(back.plan!.money, 50000);
      expect(GlobalGoal.tryFromJson({...g.toJson(), 'plan': {}})!.plan, isNull);
      expect(GlobalGoal.tryFromJson({...g.toJson(), 'plan': {'min': -5}}), isNull);
      expect(GlobalGoal.tryFromJson({...g.toJson(), 'plan': {'rub': 1.5}}), isNull);
      expect(GlobalGoal.tryFromJson({...g.toJson(), 'plan': 'много'}), isNull);
      // старые данные без плана
      final old = g.toJson()..remove('plan');
      expect(GlobalGoal.tryFromJson(old)!.plan, isNull);
    });

    test('строгий импорт отвергает копию с битым планом', () {
      final j = AppData.blank(now: now).toJson()
        ..['goals'] = [
          {'id': 'g', 'title': 't', 'checkpoints': [], 'plan': {'min': 0}},
        ];
      expect(() => AppData.fromJson(j, strict: true), throwsFormatException);
    });

    test('контроллер: задать, снять, отвергнуть неверный', () async {
      final c = make();
      await c.load();
      c.addGoal('Java', 'Карьера', []);
      final id = c.goals.single.id;
      expect(c.setGoalPlan(id, const GoalPlan(minutes: 0)), isFalse);
      expect(c.setGoalPlan(id, const GoalPlan(minutes: 600)), isTrue);
      expect(c.goals.single.plan!.minutes, 600);
      expect(c.setGoalPlan(id, const GoalPlan()), isTrue);
      expect(c.goals.single.plan, isNull);
      expect(c.setGoalPlan('нет', const GoalPlan(money: 1)), isFalse);
    });
  });

  group('факт по цели', () {
    LifeEvent ev(String id, {List<String> goals = const [], List<String> procs = const [], int? min, int? rub, List<String> dims = const ['mind']}) =>
        LifeEvent(
          id: id,
          at: DateTime(2026, 11, 1),
          recordedAt: DateTime(2026, 11, 1),
          dimensions: dims,
          kind: LifeEventKind.action,
          title: id,
          goalIds: goals,
          processIds: procs,
          cost: ResourceCost(minutes: min, money: rub),
        );
    LifeProcess proc(String id, List<String> goals) => LifeProcess(
          id: id,
          title: id,
          dimensions: [LifeDimension.mind],
          goalIds: goals,
          createdAt: DateTime(2026, 1, 1),
          statusLog: [ProcessStatusChange(at: DateTime(2026, 1, 1), status: ProcessStatus.active)],
        );

    test('напрямую и через процессы, событие учитывается один раз', () {
      final events = [
        ev('a', goals: ['g'], min: 60),
        ev('b', procs: ['java'], min: 30, rub: 1000, dims: ['mind', 'material']),
        ev('c', goals: ['g'], procs: ['java'], min: 15), // и напрямую, и через процесс — один раз
        ev('d', procs: ['other'], min: 999),
        ev('e', goals: ['другая'], min: 999),
      ];
      final f = goalFact('g', events, [proc('java', ['g']), proc('other', [])]);
      expect(f.resources.events, 3);
      expect(f.resources.minutes, 105);
      expect(f.resources.money, 1000);
      expect(f.resources.moneyKnown, 1);
      expect(f.direct, 2);
      expect(f.viaProcess, 1);
      expect(f.processIds, ['java']);
      expect(f.dimensions, ['mind', 'material']);
    });

    test('контроллер: события цели включают события её процессов', () async {
      final c = make();
      await c.load();
      c.addGoal('Стать разработчиком', 'Карьера', []);
      final g = c.goals.single.id;
      final p = c.addProcess(title: 'Java', dimensions: [LifeDimension.mind], goalIds: [g])!;
      c.addEvent(title: 'урок', dimensions: [LifeDimension.mind], processIds: [p], cost: const ResourceCost(minutes: 90));
      now = now.add(const Duration(minutes: 1)); // одинаковое время — порядок решала бы случайная часть id
      c.addEvent(title: 'резюме', dimensions: [LifeDimension.material], goalIds: [g]);
      c.addEvent(title: 'не про цель', dimensions: [LifeDimension.body]);
      expect(c.eventsForGoal(g).map((e) => e.title), ['урок', 'резюме']);
      final f = c.goalFactOf(g);
      expect(f.resources.minutes, 90);
      expect(f.resources.minutesKnown, 1);
      expect(f.dimensions, ['mind', 'material']);
    });

    test('копия сохраняет план', () async {
      final c = make();
      await c.load();
      c.addGoal('Java', 'Карьера', []);
      c.setGoalPlan(c.goals.single.id, const GoalPlan(minutes: 6000, money: 30000));
      final raw = c.exportBackup();
      final c2 = make();
      await c2.load();
      expect(c2.importBackup(raw), isTrue);
      expect(c2.goals.single.plan!.money, 30000);
      expect(c2.exportBackup(), raw);
    });
  });
}
