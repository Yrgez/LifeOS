import '../models/models.dart';

/// Анализ графа: чистые функции без Flutter и состояния.

/// Суммарная «сила» связей узла (сумма весов всех рёбер, входящих и исходящих).
Map<String, int> weightedDegree(Iterable<GraphNode> nodes, Iterable<GraphEdge> edges) {
  final ids = {for (final n in nodes) n.id};
  final m = {for (final n in nodes) n.id: 0};
  for (final e in edges) {
    if (!ids.contains(e.fromId) || !ids.contains(e.toId)) continue;
    m[e.fromId] = m[e.fromId]! + e.weight;
    m[e.toId] = m[e.toId]! + e.weight;
  }
  return m;
}

/// Узлы без единой связи.
Set<String> isolatedNodeIds(Iterable<GraphNode> nodes, Iterable<GraphEdge> edges) {
  final ids = {for (final n in nodes) n.id};
  final linked = <String>{};
  for (final e in edges) {
    if (ids.contains(e.fromId) && ids.contains(e.toId)) {
      linked.add(e.fromId);
      linked.add(e.toId);
    }
  }
  return ids.difference(linked);
}

/// Все узлы, на которые [start] влияет по цепочке направленных связей («помогает» и «мешает»).
/// Связи типа «связаны» не направлены и в цепочку влияния не входят. Циклы безопасны.
Set<String> downstream(String start, Iterable<GraphEdge> edges) {
  final out = <String, List<String>>{};
  for (final e in edges) {
    if (EdgeKind.isDirected(e.kind)) out.putIfAbsent(e.fromId, () => []).add(e.toId);
  }
  final seen = <String>{};
  final queue = [start];
  while (queue.isNotEmpty) {
    final cur = queue.removeLast();
    for (final next in out[cur] ?? const <String>[]) {
      if (next != start && seen.add(next)) queue.add(next);
    }
  }
  return seen;
}

/// Прямая связь узла с соседом.
class NodeLink {
  final GraphNode other;
  final GraphEdge edge;
  final bool outgoing; // true — связь исходит из выбранного узла
  const NodeLink(this.other, this.edge, this.outgoing);
}

List<NodeLink> linksOf(String nodeId, Iterable<GraphNode> nodes, Iterable<GraphEdge> edges) {
  final byId = {for (final n in nodes) n.id: n};
  final out = <NodeLink>[];
  for (final e in edges) {
    if (e.fromId == nodeId && byId[e.toId] != null) out.add(NodeLink(byId[e.toId]!, e, true));
    if (e.toId == nodeId && byId[e.fromId] != null) out.add(NodeLink(byId[e.fromId]!, e, false));
  }
  return out;
}
