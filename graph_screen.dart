import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/graph_stats.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../painters/chart_painters.dart';
import '../painters/graph_painter.dart';
import '../widgets/form_dialog.dart';

const _categoryNames = {
  'mind': 'Смыслы / Цели',
  'wealth': 'Капитал / Финансы',
  'gym': 'Тело / Тренировки',
  'health': 'Здоровье / Отдых',
};

const _weightNames = {'1': 'Слабая', '2': 'Средняя', '3': 'Сильная'};

/// Граф связей: зум и панорама (щипок / перетаскивание пустого места), перетаскивание узлов,
/// правка узлов и связей, типы и сила связей, анализ влияния.
class GraphScreen extends StatefulWidget {
  final AppController controller;
  const GraphScreen({super.key, required this.controller});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  AppController get c => widget.controller;

  final TransformationController _tc = TransformationController();
  String? _selectedNodeId;
  String? _selectedEdgeKey;
  String _filter = 'all';

  // Перетаскивание узла идёт через сырые события указателя (Listener), а не через pan-жест:
  // иначе жест «съедал» бы перетаскивание пустого места, которым InteractiveViewer двигает холст.
  String? _dragNodeId;
  bool _nodeTouched = false; // пока палец на узле, панорама/зум холста отключены
  int _pointers = 0;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  double get _zoom => _tc.value.getMaxScaleOnAxis();

  Offset _posOf(GraphNode n, Size size) => Offset(n.position.dx * size.width, n.position.dy * size.height);

  GraphNode? _hitNode(Offset pos, Size size) {
    GraphNode? best;
    double bestDist = clampD(32 / _zoom, 18, 44);
    for (final n in c.graphNodes) {
      final d = (_posOf(n, size) - pos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = n;
      }
    }
    return best;
  }

  GraphEdge? _hitEdge(Offset pos, Size size) {
    final nodes = {for (final n in c.graphNodes) n.id: n};
    GraphEdge? best;
    double bestDist = clampD(20 / _zoom, 12, 28);
    for (final e in c.graphEdges) {
      final a = nodes[e.fromId], b = nodes[e.toId];
      if (a == null || b == null) continue;
      final d = (((_posOf(a, size) + _posOf(b, size)) / 2) - pos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = e;
      }
    }
    return best;
  }

  void _clearSelection() => setState(() {
        _selectedNodeId = null;
        _selectedEdgeKey = null;
      });

  void _onTap(Offset pos, Size size) {
    final n = _hitNode(pos, size);
    if (n != null) {
      setState(() {
        _selectedNodeId = n.id;
        _selectedEdgeKey = null;
      });
      return;
    }
    final e = _hitEdge(pos, size);
    if (e != null) {
      setState(() {
        _selectedEdgeKey = e.key;
        _selectedNodeId = null;
      });
      return;
    }
    _clearSelection();
  }

  void _onPointerDown(PointerDownEvent e, Size size) {
    _pointers++;
    if (_pointers > 1) {
      // второй палец — это зум; перетаскивание узла отменяем
      _dragNodeId = null;
      if (_nodeTouched) setState(() => _nodeTouched = false);
      return;
    }
    final n = _hitNode(e.localPosition, size);
    if (n != null) {
      setState(() {
        _dragNodeId = n.id;
        _nodeTouched = true;
        _selectedNodeId = n.id;
        _selectedEdgeKey = null;
      });
    }
  }

  void _onPointerMove(PointerMoveEvent e, Size size) {
    final id = _dragNodeId;
    if (id == null || _pointers != 1) return;
    final n = c.nodeById(id);
    if (n == null) return;
    // e.delta уже в координатах холста (с учётом зума), поэтому делим только на размер
    c.moveNode(id, Offset(n.position.dx + e.delta.dx / size.width, n.position.dy + e.delta.dy / size.height));
  }

  void _onPointerEnd() {
    _pointers = max(0, _pointers - 1);
    if (_pointers == 0) {
      if (_dragNodeId != null) c.endMove();
      _dragNodeId = null;
      if (_nodeTouched) setState(() => _nodeTouched = false);
    }
  }

  // ---------------- диалоги ----------------

  Future<void> _addNodeDialog() async {
    final r = await showFormDialog(
      context,
      title: 'Создать узел графа',
      actionLabel: 'Создать',
      accent: AppColors.violet,
      fields: const [
        FieldSpec('title', 'Название узла'),
        FieldSpec('cat', 'Сфера жизни', initial: 'mind', options: _categoryNames),
      ],
      validate: (v) => v['title']!.isNotEmpty,
    );
    if (r == null || !mounted) return;
    c.addNode(r['title']!, r['cat']!);
  }

  Future<void> _editNodeDialog(GraphNode n) async {
    final auto = AppController.autoNodeIds.contains(n.id);
    final r = await showFormDialog(
      context,
      title: auto ? 'Узел: ${n.label}' : 'Изменить узел',
      actionLabel: 'Сохранить',
      accent: AppColors.violet,
      fields: [
        // подписи «живых» узлов подставляются из данных — переименовать их нельзя
        if (!auto) FieldSpec('title', 'Название узла', initial: n.label),
        FieldSpec('cat', 'Сфера жизни', initial: n.category, options: _categoryNames),
      ],
      validate: (v) => auto || v['title']!.isNotEmpty,
    );
    if (r == null || !mounted) return;
    c.updateNode(n.id, label: auto ? null : r['title'], category: r['cat']);
  }

  Future<void> _addEdgeDialog([String? fromId]) async {
    if (c.graphNodes.length < 2) return;
    final from = c.nodeById(fromId)?.id ?? c.graphNodes.first.id;
    final to = c.graphNodes.firstWhere((n) => n.id != from).id;
    final options = {for (final n in c.graphNodes) n.id: n.label};

    final r = await showFormDialog(
      context,
      title: 'Связать узлы графа',
      actionLabel: 'Соединить',
      accent: Colors.cyanAccent,
      fields: [
        FieldSpec('from', 'Откуда', initial: from, options: options),
        FieldSpec('to', 'Куда', initial: to, options: options),
        const FieldSpec('kind', 'Тип связи', initial: EdgeKind.related, options: {
          EdgeKind.related: 'Связаны (без направления)',
          EdgeKind.supports: 'Откуда → помогает → куда',
          EdgeKind.conflicts: 'Откуда → мешает → куда',
        }),
        const FieldSpec('w', 'Сила связи', initial: '1', options: _weightNames),
      ],
      validate: (v) => v['from'] != v['to'],
    );
    if (r == null || !mounted) return;
    final ok = c.addEdge(r['from']!, r['to']!, kind: r['kind']!, weight: int.parse(r['w']!));
    if (!ok) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Эти узлы уже связаны — выберите связь на графе и измените её')));
    }
  }

  // ---------------- построение ----------------

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: c, builder: (context, _) => _content());
  }

  Widget _content() {
    // выбранный объект мог быть удалён
    final node = c.nodeById(_selectedNodeId);
    final edge = c.graphEdges.where((e) => e.key == _selectedEdgeKey).firstOrNull;
    final isolated = isolatedNodeIds(c.graphNodes, c.graphEdges);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SECOND BRAIN GRAPH', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Щипок — зум, перетаскивание фона — панорама', style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.add_circle, color: AppColors.violet, size: 24), tooltip: 'Добавить узел', onPressed: _addNodeDialog),
                  IconButton(icon: const Icon(Icons.alt_route, color: Colors.cyanAccent, size: 24), tooltip: 'Связать узлы', onPressed: () => _addEdgeDialog(_selectedNodeId)),
                ],
              ),
            ],
          ),
        ),
        _statsCard(isolated.length),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _pill('all', 'Все'),
              _pill('mind', 'Смыслы'),
              _pill('wealth', 'Капитал'),
              _pill('health', 'Здоровье'),
              _pill('gym', 'Тело'),
            ],
          ),
        ),
        Expanded(child: _canvas(isolated)),
        if (node != null) _nodePanel(node),
        if (edge != null) _edgePanel(edge),
      ],
    );
  }

  Widget _statsCard(int isolatedCount) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ИСТОРИЯ РОСТА ЗНАНИЙ (УЗЛЫ)', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
              Text('${c.graphNodes.length} узлов • ${c.graphEdges.length} связей', style: const TextStyle(color: AppColors.violet, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(height: 36, width: double.infinity, child: CustomPaint(painter: MiniSparklinePainter(data: c.graphEvolutionHistory, color: AppColors.violet))),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '→ помогает   ┄ мешает   — связаны   толщина = сила',
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                ),
              ),
              if (isolatedCount > 0)
                Text('без связей: $isolatedCount', style: const TextStyle(color: AppColors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _canvas(Set<String> isolated) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: LayoutBuilder(
          builder: (ctx, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            final degree = weightedDegree(c.graphNodes, c.graphEdges);
            return Stack(
              children: [
                InteractiveViewer(
                  transformationController: _tc,
                  minScale: 0.6,
                  maxScale: 4,
                  boundaryMargin: const EdgeInsets.all(160),
                  panEnabled: !_nodeTouched,
                  scaleEnabled: !_nodeTouched,
                  child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (e) => _onPointerDown(e, size),
                      onPointerMove: (e) => _onPointerMove(e, size),
                      onPointerUp: (_) => _onPointerEnd(),
                      onPointerCancel: (_) => _onPointerEnd(),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => _onTap(d.localPosition, size),
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: size,
                            painter: LifeGraphPainter(
                              nodes: c.graphNodes,
                              edges: c.graphEdges,
                              degree: degree,
                              isolated: isolated,
                              selectedNodeId: _selectedNodeId,
                              selectedEdgeKey: _selectedEdgeKey,
                              activeCategoryFilter: _filter,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'graph_layout',
                        backgroundColor: AppColors.field,
                        tooltip: 'Организовать по кругу',
                        onPressed: () {
                          c.autoLayoutRadial();
                          _tc.value = Matrix4.identity();
                        },
                        child: const Icon(Icons.refresh, color: Colors.cyanAccent, size: 20),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'graph_reset_view',
                        backgroundColor: AppColors.field,
                        tooltip: 'Сбросить масштаб',
                        onPressed: () => _tc.value = Matrix4.identity(),
                        child: const Icon(Icons.center_focus_strong, color: Colors.white70, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pill(String key, String label) {
    final active = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.cyanAccent.withValues(alpha: 0.2) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? Colors.cyanAccent : Colors.white12),
        ),
        child: Text(label, style: TextStyle(color: active ? Colors.cyanAccent : Colors.white60, fontSize: 11, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  // ---------------- панели выбора ----------------

  Widget _panel({required Color border, required List<Widget> children}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.34),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: border.withValues(alpha: 0.5))),
        child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children)),
      ),
    );
  }

  Widget _nodePanel(GraphNode node) {
    final links = linksOf(node.id, c.graphNodes, c.graphEdges);
    final reach = downstream(node.id, c.graphEdges);
    final reachNames = [for (final id in reach) if (c.nodeById(id) != null) c.nodeById(id)!.label];
    final auto = AppController.autoNodeIds.contains(node.id);

    return _panel(
      border: node.color,
      children: [
        Row(
          children: [
            CircleAvatar(radius: 5, backgroundColor: node.color),
            const SizedBox(width: 8),
            Expanded(child: Text(node.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            IconButton(icon: const Icon(Icons.close, color: Colors.white38, size: 18), onPressed: _clearSelection, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ],
        ),
        Text(
          '${_categoryNames[node.category] ?? node.category}${auto ? ' • значение обновляется автоматически' : ''}',
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 8),
        if (links.isEmpty)
          const Text('Связей нет — свяжите узел с другими, чтобы увидеть влияние', style: TextStyle(color: AppColors.amber, fontSize: 11))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final l in links)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppColors.field,
                  side: BorderSide(color: LifeGraphPainter.edgeColor(l.edge.kind).withValues(alpha: 0.6)),
                  label: Text(
                    '${EdgeKind.isDirected(l.edge.kind) ? (l.outgoing ? '→ ' : '← ') : '— '}${l.other.label}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () => setState(() {
                    _selectedEdgeKey = l.edge.key;
                    _selectedNodeId = null;
                  }),
                ),
            ],
          ),
        if (reachNames.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Влияет по цепочке на ${reachNames.length}: ${reachNames.take(4).join(', ')}${reachNames.length > 4 ? '…' : ''}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.cyanAccent, side: const BorderSide(color: Colors.cyanAccent), padding: const EdgeInsets.symmetric(vertical: 8)),
                onPressed: () => _addEdgeDialog(node.id),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('Связать', style: TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24), padding: const EdgeInsets.symmetric(vertical: 8)),
                onPressed: () => _editNodeDialog(node),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Изменить', style: TextStyle(fontSize: 11)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.red, size: 20),
              tooltip: 'Удалить узел',
              onPressed: () {
                c.deleteNode(node.id);
                _clearSelection();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _edgePanel(GraphEdge edge) {
    final from = c.nodeById(edge.fromId)?.label ?? '?';
    final to = c.nodeById(edge.toId)?.label ?? '?';
    final arrow = EdgeKind.isDirected(edge.kind) ? '→' : '—';

    return _panel(
      border: Colors.cyanAccent,
      children: [
        Row(
          children: [
            Expanded(child: Text('$from $arrow $to', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            IconButton(icon: const Icon(Icons.close, color: Colors.white38, size: 18), onPressed: _clearSelection, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
          ],
        ),
        const SizedBox(height: 8),
        const Text('ТИП СВЯЗИ', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            for (final k in EdgeKind.labels.entries)
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text(k.value, style: const TextStyle(fontSize: 11)),
                selected: edge.kind == k.key,
                selectedColor: LifeGraphPainter.edgeColor(k.key).withValues(alpha: 0.3),
                onSelected: (_) => c.updateEdge(edge.key, kind: k.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('СИЛА СВЯЗИ', style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          children: [
            for (final w in _weightNames.entries)
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text(w.value, style: const TextStyle(fontSize: 11)),
                selected: edge.weight == int.parse(w.key),
                selectedColor: Colors.cyanAccent.withValues(alpha: 0.25),
                onSelected: (_) => c.updateEdge(edge.key, weight: int.parse(w.key)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              c.removeEdge(edge.key);
              _clearSelection();
            },
            icon: const Icon(Icons.link_off, size: 16, color: AppColors.red),
            label: const Text('Удалить связь', style: TextStyle(color: AppColors.red, fontSize: 12)),
          ),
        ),
      ],
    );
  }
}
