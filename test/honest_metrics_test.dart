import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:catenna/core/recovery_stats.dart';
import 'package:catenna/data/app_data.dart';
import 'package:catenna/data/app_repository.dart';
import 'package:catenna/models/life_event.dart';
import 'package:catenna/models/models.dart';
import 'package:catenna/state/app_controller.dart';

void main() {
  late DateTime now;
  AppController make() => AppController(
        MemoryAppRepository(),
        clock: () => now,
        saveDelay: const Duration(days: 1),
        initialData: (n) => AppData.blank(now: n),
      );

  setUp(() => now = DateTime(2026, 11, 15, 12));

  group('восстановление без процента', () {
    MuscleGroup m(String id, double hours, DateTime? at) => MuscleGroup.fromJson({
          'id': id,
          'name': id,
          'recoveryHours': hours,
          'lastTrainedAtMs': at?.millisecondsSinceEpoch,
          'maxWeight': 0,
          'lastSets': [],
          'history1RM': [0],
        });

    test('часы до восстановления по типовой оценке, сортировка по остатку', () {
      final muscles = {
        'chest': m('chest', 60, now.subtract(const Duration(hours: 10))),
        'abs': m('abs', 36, now.subtract(const Duration(hours: 35, minutes: 30))),
        'quads': m('quads', 72, now.subtract(const Duration(hours: 80))),
        'calves': m('calves', 36, null),
      };
      final o = recoveryOverview(muscles, now);
      expect(o.total, 4);
      expect(o.recovered, 2);
      expect(o.recovering.map((x) => x.id), ['chest', 'abs']);
      expect(o.recovering.first.hoursLeft, 50);
      expect(o.recovering.last.hoursLeft, 1); // полчаса — округление вверх
    });

    test('округлённая подпись', () {
      expect(fmtHoursLeft(5), '≈ 5 ч');
      expect(fmtHoursLeft(50), '≈ 2 дн');
    });

    test('контроллер: подход переводит мышцу в восстанавливающиеся', () async {
      final c = make();
      await c.load();
      expect(c.recovery.recovered, c.recovery.total);
      c.logWorkout('chest', 80, 5);
      expect(c.recovery.recovering.single.id, 'chest');
      now = now.add(const Duration(days: 4));
      expect(c.recovery.recovering, isEmpty);
    });
  });

  group('узлы графа связаны с процессами и целями', () {
    test('JSON: ссылка сохраняется, битая ссылка отвергает узел', () {
      final n = GraphNode(id: 'n', label: 'Java', category: 'mind', position: const Offset(0.5, 0.5), ref: const NodeRef(NodeRef.process, 'p1'));
      final back = GraphNode.tryFromJson(jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>)!;
      expect(back.ref, const NodeRef(NodeRef.process, 'p1'));
      expect(GraphNode.tryFromJson({...n.toJson(), 'ref': {'type': 'friend', 'id': 'x'}}), isNull);
      expect(GraphNode.tryFromJson({...n.toJson()}..remove('ref'))!.ref, isNull);
    });

    test('узел для процесса: подпись из процесса, одна сущность — один узел', () async {
      final c = make();
      await c.load();
      final p = c.addProcess(title: 'Изучение Java', dimensions: [LifeDimension.material])!;
      final nodes = c.graphNodes.length;
      final id = c.addNodeFor(const NodeRef(NodeRef.process, 'нет'));
      expect(id, isNull); // нет такого процесса
      final n1 = c.addNodeFor(NodeRef(NodeRef.process, p))!;
      expect(c.addNodeFor(NodeRef(NodeRef.process, p)), n1); // повторно — тот же узел
      expect(c.graphNodes.length, nodes + 1);
      final node = c.nodeById(n1)!;
      expect(node.label, 'Изучение Java');
      expect(node.category, 'wealth'); // по измерению процесса

      c.updateProcess(p, title: 'Java и Spring', dimensions: [LifeDimension.mind]);
      expect(c.nodeById(n1)!.label, 'Java и Spring'); // подпись следует за процессом
      expect(c.updateNode(n1, label: 'Своё имя'), isTrue);
      expect(c.nodeById(n1)!.label, 'Java и Spring'); // переименовать связанный узел нельзя

      c.removeProcess(p);
      expect(c.nodeById(n1)!.label, 'Java и Spring'); // узел хранит последнее название
      expect(c.refTitle(c.nodeById(n1)!.ref!), isNull);
    });

    test('связать существующий узел с целью и снять связь', () async {
      final c = make();
      await c.load();
      c.addGoal('Полумарафон', 'Спорт', []);
      final g = c.goals.single.id;
      c.addNode('Бег', 'gym');
      final n = c.graphNodes.last.id;
      expect(c.linkNode(n, const NodeRef(NodeRef.goal, 'нет')), isFalse);
      expect(c.linkNode(n, NodeRef(NodeRef.goal, g)), isTrue);
      expect(c.nodeById(n)!.label, 'Полумарафон');
      c.addNode('Другой', 'gym');
      expect(c.linkNode(c.graphNodes.last.id, NodeRef(NodeRef.goal, g)), isFalse); // цель уже занята
      expect(c.linkNode('n_capital', NodeRef(NodeRef.goal, g)), isFalse); // системный узел
      expect(c.linkNode(n, null), isTrue);
      expect(c.nodeById(n)!.ref, isNull);
    });

    test('копия сохраняет связи узлов', () async {
      final c = make();
      await c.load();
      final p = c.addProcess(title: 'Java', dimensions: [LifeDimension.mind])!;
      c.addNodeFor(NodeRef(NodeRef.process, p));
      final raw = c.exportBackup();
      final c2 = make();
      await c2.load();
      expect(c2.importBackup(raw), isTrue);
      expect(c2.exportBackup(), raw);
    });
  });
}
