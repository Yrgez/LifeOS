import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/graph_stats.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../painters/graph_painter.dart';
import '../widgets/form_dialog.dart';
import '../widgets/toast.dart';
import '../widgets/confirm_dialog.dart';
import 'events_screen.dart';

/// Сферы узлов (хранятся как есть) — показываются через измерения жизни.
const _categoryNames = {
  'mind': 'Разум · смыслы, цели',
  'wealth': 'Материальное · деньги, капитал',
  'gym': 'Тело · тренировки',
  'health': 'Тело · здоровье, отдых',
};

/// Фильтр по измерению → какие сферы узлов он показывает.
const _filters = {'all': 'Все', 'body': 'Тело', 'mind': 'Разум', 'material': 'Материальное'};
const _filterCategories = {
  'body': {'gym', 'health'},
  'mind': {'mind'},
  'material': {'wealth'},
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

  /// Варианты связи узла: процессы и цели (уже связанные с другим узлом не предлагаются).
  Map<String, String> _refOptions({GraphNode? node}) {
    bool free(NodeRef r) => c.nodeForRef(r) == null || c.nodeForRef(r)!.id == node?.id;
    return {
      '': 'Не связан',
      for (final p in c.processes)
        if (free(NodeRef(NodeRef.process, p.id))) 'process:${p.id}': 'Процесс: ${p.title}',
      for (final g in c.goals)
        if (free(NodeRef(NodeRef.goal, g.id))) 'goal:${g.id}': 'Цель: ${g.title}',
      // связь с удалённой сущностью остаётся выбранной, пока её не сменят явно
      if (node?.ref != null && c.refTitle(node!.ref!) == null) _refKey(node.ref): '${node.label} (удалён)',
    };
  }

  static NodeRef? _parseRef(String v) {
    final i = v.indexOf(':');
    return i < 0 ? null : NodeRef(v.substring(0, i), v.substring(i + 1));
  }

  static String _refKey(NodeRef? r) => r == null ? '' : '${r.type}:${r.id}';

  void _fromEntities() {
    final r = c.graphFromEntities();
    showToast(
      context,
      r.nodes == 0 && r.edges == 0
          ? 'Все процессы и цели уже на графе'
          : 'Добавлено узлов: ${r.nodes}, связей «процесс → цель»: ${r.edges}',
    );
  }

  Future<void> _addNodeDialog() async {
    final refs = _refOptions();
    final r = await showFormDialog(
      context,
      title: 'Создать узел графа',
      actionLabel: 'Создать',
      accent: AppColors.accent,
      actionTextColor: Colors.black,
      fields: [
        if (refs.length > 1) FieldSpec('ref', 'Связать с процессом или целью', initial: '', options: refs),
        const FieldSpec('title', 'Название узла (для связанного — из процесса/цели)'),
        const FieldSpec('cat', 'Сфера жизни', initial: 'mind', options: _categoryNames),
      ],
      validate: (v) => v['title']!.isNotEmpty || (v['ref'] ?? '').isNotEmpty,
    );
    if (r == null || !mounted) return;
    final ref = _parseRef(r['ref'] ?? '');
    if (ref != null) {
      c.addNodeFor(ref);
    } else {
      c.addNode(r['title']!, r['cat']!);
    }
  }

  Future<void> _editNodeDialog(GraphNode n) async {
    final auto = AppController.autoNodeIds.contains(n.id);
    final r = await showFormDialog(
      context,
      title: auto ? 'Узел: ${n.label}' : 'Изменить узел',
      actionLabel: 'Сохранить',
      accent: AppColors.accent,
      actionTextColor: Colors.black,
      fields: [
        // подписи «живых» и связанных узлов подставляются из данных — переименовать их нельзя
        if (!auto && n.ref == null) FieldSpec('title', 'Название узла', initial: n.label),
        if (!auto) FieldSpec('ref', 'Связь с процессом или целью', initial: _refKey(n.ref), options: _refOptions(node: n)),
        FieldSpec('cat', 'Сфера жизни', initial: n.category, options: _categoryNames),
      ],
      validate: (v) => auto || n.ref != null || v['title']!.isNotEmpty,
    );
    if (r == null || !mounted) return;
    c.updateNode(n.id, label: auto || n.ref != null ? null : r['title'], category: r['cat']);
    if (!auto && r['ref'] != _refKey(n.ref)) c.linkNode(n.id, _parseRef(r['ref'] ?? ''));
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
      accent: AppColors.accent,
      actionTextColor: Colors.black,
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
      showToast(context, 'Эти узлы уже связаны — выберите связь на графе и измените её');
    }
  }

  // ---------------- построение ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Граф связей'),
        backgroundColor: AppColors.panel,
        elevation: 0,
        actions: [
          IconButton(
            key: const ValueKey('graph_from_entities'),
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'Собрать из процессов и целей',
            onPressed: _fromEntities,
          ),
          IconButton(key: const ValueKey('graph_add_node'), icon: const Icon(Icons.add), tooltip: 'Добавить узел', onPressed: _addNodeDialog),
          IconButton(icon: const Icon(Icons.link), tooltip: 'Связать узлы', onPressed: () => _addEdgeDialog(_selectedNodeId)),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(listenable: c, builder: (context, _) => _content()),
    );
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            [
              '${c.graphNodes.length} узлов · ${c.graphEdges.length} связей',
              if (isolated.isNotEmpty) 'без связей: ${isolated.length}',
            ].join(' · '),
            key: const ValueKey('graph_counts'),
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
        if (c.graphNodes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            // переключатель измерений — как выбор цели по весу на «Теле»
            child: Container(
              decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(AppRadii.pill), border: Border.all(color: AppColors.border)),
              child: Row(
                children: [
                  for (final f in _filters.entries)
                    Expanded(
                      flex: f.key == 'material' ? 3 : 2,
                      child: Semantics(
                        button: true,
                        selected: _filter == f.key,
                        inMutuallyExclusiveGroup: true,
                        label: f.value,
                        onTap: () => setState(() => _filter = f.key),
                        excludeSemantics: true,
                        child: GestureDetector(
                          key: ValueKey('graph_filter_${f.key}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _filter = f.key),
                          // область нажатия 48 px, видимый сегмент — с отступом 3 px внутри таблетки
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Container(
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _filter == f.key ? AppColors.accent : Colors.transparent,
                                borderRadius: BorderRadius.circular(AppRadii.pill),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    f.value,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _filter == f.key ? Colors.black : AppColors.muted),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(child: _canvas(isolated)),
        if (c.graphNodes.isNotEmpty && node == null && edge == null)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Зелёная стрелка — помогает, красный пунктир — мешает, серая линия — связаны; толщина — сила. Щипок — масштаб.',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ),
        if (node != null) _nodePanel(node),
        if (edge != null) _edgePanel(edge),
      ],
    );
  }

  Widget _canvas(Set<String> isolated) {
    if (c.graphNodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Граф пуст. Его можно собрать из ваших процессов и целей — связи «процесс → цель» берутся из того, что вы уже указали.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
                onPressed: _fromEntities,
                child: const Text('Собрать из процессов и целей'),
              ),
              TextButton(onPressed: _addNodeDialog, child: const Text('Добавить узел вручную')),
            ],
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: tileDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.tile),
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
                        // для программы чтения экрана нажатие — по узлам из semanticsBuilder, а не по холсту целиком
                        excludeFromSemantics: true,
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
                              visibleCategories: _filterCategories[_filter],
                              semanticLabels: {
                                for (final n in c.graphNodes)
                                  n.id: '${n.label}. ${isolated.contains(n.id) ? 'Без связей' : 'Связей: ${c.graphEdges.where((e) => e.fromId == n.id || e.toId == n.id).length}'}',
                              },
                              onSelect: (id) => setState(() {
                                _selectedNodeId = id;
                                _selectedEdgeKey = null;
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Column(
                    children: [
                      _canvasButton(Icons.donut_large_outlined, 'Расставить по кругу', () {
                        c.autoLayoutRadial();
                        _tc.value = Matrix4.identity();
                      }),
                      const SizedBox(height: 8),
                      _canvasButton(Icons.center_focus_strong_outlined, 'Сбросить масштаб', () => _tc.value = Matrix4.identity()),
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

  Widget _canvasButton(IconData icon, String tooltip, VoidCallback onTap) => Material(
        color: AppColors.raised,
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          icon: Icon(icon, size: 18, color: AppColors.text),
          tooltip: tooltip,
          onPressed: onTap,
          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          padding: EdgeInsets.zero,
        ),
      );

  // ---------------- панели выбора ----------------

  Widget _panel({required List<Widget> children}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
        decoration: tileDecoration(),
        child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children)),
      ),
    );
  }

  Widget _panelTitle(String text, {Color? dot}) => Row(
        children: [
          if (dot != null) ...[
            Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(text, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Закрыть', icon: const Icon(Icons.close, color: AppColors.muted, size: 20), onPressed: _clearSelection),
        ],
      );

  Future<void> _deleteNode(GraphNode node) async {
    final ok = await confirmDialog(context,
        title: 'Удалить узел?', message: '«${node.label}» и его связи исчезнут с графа. Процессы, цели и журналы не затрагиваются.', confirmLabel: 'Удалить', danger: true);
    if (!ok || !mounted) return;
    c.deleteNode(node.id);
    _clearSelection();
  }

  Future<void> _deleteEdge(GraphEdge edge) async {
    final ok = await confirmDialog(context, title: 'Удалить связь?', message: 'Узлы останутся на графе.', confirmLabel: 'Удалить', danger: true);
    if (!ok || !mounted) return;
    c.removeEdge(edge.key);
    _clearSelection();
  }

  Widget _nodePanel(GraphNode node) {
    final links = linksOf(node.id, c.graphNodes, c.graphEdges);
    final reach = downstream(node.id, c.graphEdges);
    final reachNames = [for (final id in reach) if (c.nodeById(id) != null) c.nodeById(id)!.label];
    final auto = AppController.autoNodeIds.contains(node.id);

    return _panel(
      children: [
        _panelTitle(node.label, dot: node.color),
        Text(
          '${_categoryNames[node.category] ?? node.category}${auto ? ' · значение подставляется из данных' : ''}',
          style: const TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        if (node.ref != null) _refLine(node.ref!),
        const SizedBox(height: 10),
        if (links.isEmpty)
          const Text('Связей нет', style: TextStyle(color: AppColors.muted, fontSize: 13))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final l in links)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    '${EdgeKind.isDirected(l.edge.kind) ? (l.outgoing ? '→ ' : '← ') : '— '}'
                    '${l.edge.kind == EdgeKind.conflicts ? 'мешает: ' : ''}${l.other.label}',
                    style: const TextStyle(fontSize: 13),
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
            'По цепочке связей ведёт к ${reachNames.length}: ${reachNames.take(4).join(', ')}${reachNames.length > 4 ? '…' : ''}',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            // на узком экране или с крупным шрифтом кнопки переносятся, а не вылезают за край
            Expanded(
              child: Wrap(
                children: [
                  TextButton.icon(onPressed: () => _addEdgeDialog(node.id), icon: const Icon(Icons.link, size: 18), label: const Text('Связать')),
                  TextButton.icon(onPressed: () => _editNodeDialog(node), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Изменить')),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('graph_delete_node'),
              tooltip: 'Удалить узел',
              onPressed: () => _deleteNode(node),
              icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.muted),
            ),
          ],
        ),
      ],
    );
  }

  /// Строка связи узла: что это за сущность, переход к ней, или пометка, что она удалена.
  Widget _refLine(NodeRef ref) {
    final title = c.refTitle(ref);
    final kind = ref.type == NodeRef.process ? 'Процесс' : 'Цель';
    if (title == null) {
      return Text('$kind удалён(а) — узел хранит последнее название', style: const TextStyle(color: AppColors.muted, fontSize: 13));
    }
    final open = ref.type == NodeRef.process
        ? EventsScreen(controller: c, processId: ref.id)
        : EventsScreen(controller: c, goalId: ref.id);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const ValueKey('node_ref_open'),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => open)),
        icon: Icon(ref.type == NodeRef.process ? Icons.autorenew : Icons.flag_outlined, size: 16),
        label: Text('$kind: события и ресурсы', style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  Widget _edgePanel(GraphEdge edge) {
    final from = c.nodeById(edge.fromId)?.label ?? '?';
    final to = c.nodeById(edge.toId)?.label ?? '?';
    final arrow = EdgeKind.isDirected(edge.kind) ? '→' : '—';

    return _panel(
      children: [
        _panelTitle('$from $arrow $to'),
        if (c.edgeEvidence(edge) case final ev?)
          Text('По журналу: $ev', key: const ValueKey('edge_evidence'), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 12),
        const Text('ТИП СВЯЗИ', style: AppText.caption),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final k in EdgeKind.labels.entries)
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text(k.value),
                selected: edge.kind == k.key,
                onSelected: (_) => c.updateEdge(edge.key, kind: k.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('СИЛА СВЯЗИ', style: AppText.caption),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final w in _weightNames.entries)
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text(w.value),
                selected: edge.weight == int.parse(w.key),
                onSelected: (_) => c.updateEdge(edge.key, weight: int.parse(w.key)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => _deleteEdge(edge),
          icon: const Icon(Icons.link_off, size: 18, color: AppColors.muted),
          label: const Text('Удалить связь', style: TextStyle(color: AppColors.muted)),
        ),
      ],
    );
  }
}
