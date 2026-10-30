import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/core/graph_stats.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:life_os/models/models.dart';
import 'package:life_os/state/app_controller.dart';

GraphNode node(String id) => GraphNode(id: id, label: id, category: 'mind', position: const Offset(0.5, 0.5), color: Colors.white);

void main() {
  group('анализ графа', () {
    final nodes = [node('a'), node('b'), node('c'), node('d'), node('lonely')];
    final edges = [
      const GraphEdge('a', 'b', kind: EdgeKind.supports, weight: 3),
      const GraphEdge('b', 'c', kind: EdgeKind.conflicts, weight: 1),
      const GraphEdge('c', 'a', kind: EdgeKind.supports), // цикл
      const GraphEdge('c', 'd'), // «связаны» — не направленная
      const GraphEdge('a', 'ghost'), // несуществующий узел
    ];

    test('weightedDegree суммирует силу входящих и исходящих; несуществующие узлы игнорируются', () {
      final d = weightedDegree(nodes, edges);
      expect(d['a'], 3 + 1); // a→b (3) + c→a (1)
      expect(d['b'], 3 + 1);
      expect(d['c'], 1 + 1 + 1);
      expect(d['d'], 1);
      expect(d['lonely'], 0);
      expect(d.containsKey('ghost'), isFalse);
    });

    test('isolatedNodeIds', () {
      expect(isolatedNodeIds(nodes, edges), {'lonely'});
    });

    test('downstream идёт по направленным связям и не зацикливается', () {
      expect(downstream('a', edges), {'b', 'c'}); // d достижим только через «связаны» — не входит
      expect(downstream('b', edges), {'c', 'a'});
      expect(downstream('lonely', edges), isEmpty);
    });

    test('downstream не включает сам узел даже при цикле', () {
      expect(downstream('a', edges).contains('a'), isFalse);
    });

    test('linksOf: направление и фильтр несуществующих узлов', () {
      final l = linksOf('a', nodes, edges);
      expect(l.length, 2);
      expect(l.firstWhere((x) => x.other.id == 'b').outgoing, isTrue);
      expect(l.firstWhere((x) => x.other.id == 'c').outgoing, isFalse);
    });
  });

  group('GraphEdge', () {
    test('JSON с типом и силой', () {
      const e = GraphEdge('a', 'b', kind: EdgeKind.conflicts, weight: 3);
      final back = GraphEdge.fromJson(e.toJson());
      expect(back.kind, EdgeKind.conflicts);
      expect(back.weight, 3);
      expect(back.key, 'a>b');
    });
    test('старый формат без типа и силы', () {
      final e = GraphEdge.fromJson({'fromId': 'a', 'toId': 'b'});
      expect(e.kind, EdgeKind.related);
      expect(e.weight, 1);
    });
    test('мусор в типе и силе приводится к допустимому', () {
      final e = GraphEdge.fromJson({'fromId': 'a', 'toId': 'b', 'kind': 'weird', 'weight': 99});
      expect(e.kind, EdgeKind.related);
      expect(e.weight, 3);
      expect(GraphEdge.fromJson({'fromId': 'a', 'toId': 'b', 'weight': -5}).weight, 1);
    });
    test('copyWith не меняет направление', () {
      final e = const GraphEdge('a', 'b').copyWith(kind: EdgeKind.supports, weight: 2);
      expect(e.fromId, 'a');
      expect(e.toId, 'b');
      expect(e.kind, EdgeKind.supports);
    });
  });

  group('контроллер: узлы и связи', () {
    late AppController c;
    setUp(() async {
      c = AppController(MemoryAppRepository(), clock: () => DateTime(2026, 10, 24, 12), saveDelay: Duration.zero);
      await c.load();
    });

    test('addEdge с типом и силой; сила зажимается в 1..3', () {
      expect(c.addEdge('n_goal_salary', 'n_cushion', kind: EdgeKind.conflicts, weight: 9), isTrue);
      final e = c.graphEdges.last;
      expect(e.kind, EdgeKind.conflicts);
      expect(e.weight, 3);
    });

    test('addEdge отклоняет неверный тип, дубль в обе стороны и петлю', () {
      expect(c.addEdge('n_goal_salary', 'n_cushion', kind: 'x'), isFalse);
      expect(c.addEdge('n_salary', 'n_capital'), isFalse);
      expect(c.addEdge('n_capital', 'n_salary'), isFalse);
      expect(c.addEdge('n_salary', 'n_salary'), isFalse);
    });

    test('updateEdge меняет тип и силу по ключу', () {
      const key = 'n_salary>n_capital';
      expect(c.updateEdge(key, kind: EdgeKind.conflicts, weight: 1), isTrue);
      final e = c.graphEdges.firstWhere((x) => x.key == key);
      expect(e.kind, EdgeKind.conflicts);
      expect(e.weight, 1);
      expect(c.updateEdge('нет>нет', weight: 2), isFalse);
      expect(c.updateEdge(key, kind: 'bad'), isFalse);
    });

    test('removeEdge', () {
      final n = c.graphEdges.length;
      expect(c.removeEdge('n_salary>n_capital'), isTrue);
      expect(c.graphEdges.length, n - 1);
      expect(c.removeEdge('n_salary>n_capital'), isFalse);
    });

    test('updateNode: переименование и смена сферы (цвет следует за сферой)', () {
      c.addNode('Идея', 'mind');
      final id = c.graphNodes.last.id;
      expect(c.updateNode(id, label: '  Новая идея ', category: 'wealth'), isTrue);
      final n = c.nodeById(id)!;
      expect(n.label, 'Новая идея');
      expect(n.category, 'wealth');
      expect(n.color, nodeColorFor('wealth'));
    });

    test('updateNode: пустое название отклоняется, авто-узлы не переименовываются', () {
      c.addNode('Идея', 'mind');
      final id = c.graphNodes.last.id;
      expect(c.updateNode(id, label: '   '), isFalse);
      expect(c.nodeById(id)!.label, 'Идея');

      final before = c.nodeById('n_capital')!.label;
      expect(c.updateNode('n_capital', label: 'Свой текст', category: 'gym'), isTrue);
      expect(c.nodeById('n_capital')!.label, before); // подпись осталась «живой»
      expect(c.nodeById('n_capital')!.category, 'gym'); // сферу сменить можно
      expect(c.updateNode('нет', label: 'x'), isFalse);
    });

    test('удаление узла убирает его связи (в том числе типизированные)', () {
      c.deleteNode('n_sleep');
      expect(c.graphEdges.any((e) => e.fromId == 'n_sleep' || e.toId == 'n_sleep'), isFalse);
    });

    test('связи с типами и силой переживают сохранение и загрузку', () async {
      final repo = MemoryAppRepository();
      final c1 = AppController(repo, clock: () => DateTime(2026, 10, 24, 12), saveDelay: Duration.zero);
      await c1.load();
      c1.updateEdge('n_salary>n_capital', kind: EdgeKind.conflicts, weight: 2);
      await c1.flush();
      final c2 = AppController(repo, clock: () => DateTime(2026, 10, 24, 12), saveDelay: Duration.zero);
      await c2.load();
      final e = c2.graphEdges.firstWhere((x) => x.key == 'n_salary>n_capital');
      expect(e.kind, EdgeKind.conflicts);
      expect(e.weight, 2);
    });

    test('стартовый граф: нет изолированных узлов', () {
      expect(isolatedNodeIds(c.graphNodes, c.graphEdges), isEmpty);
    });
  });

  test('AppData: связи сериализуются вместе с типом', () {
    final d = AppData.defaults();
    final back = AppData.fromJson(d.toJson());
    expect(back.graphEdges.map((e) => '${e.key}:${e.kind}:${e.weight}'), d.graphEdges.map((e) => '${e.key}:${e.kind}:${e.weight}'));
  });
}
