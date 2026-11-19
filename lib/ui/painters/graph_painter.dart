import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';

class LifeGraphPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final String? selectedNodeId;
  final String? selectedEdgeKey;
  final Set<String>? visibleCategories; // фильтр по измерению; null — все сферы
  final Map<String, int> degree; // суммарная сила связей узла — «хабы» рисуются крупнее
  final Set<String> isolated; // узлы без связей — пунктирное кольцо

  /// Подписи узлов для программы чтения экрана; каждый узел — отдельная кнопка (граф только нарисован).
  final Map<String, String> semanticLabels;
  final ValueChanged<String>? onSelect;

  LifeGraphPainter({
    required this.nodes,
    required this.edges,
    required this.degree,
    required this.isolated,
    this.selectedNodeId,
    this.selectedEdgeKey,
    this.visibleCategories,
    this.semanticLabels = const {},
    this.onSelect,
  });

  static double radiusOf(int degree, bool selected) => 8.0 + min(6, degree).toDouble() + (selected ? 4 : 0);

  /// Цвет связи со смыслом: помогает — зелёный, мешает — красный (и пунктир), просто связаны — нейтральный.
  static Color edgeColor(String kind) {
    switch (kind) {
      case EdgeKind.supports:
        return const Color(0xFF3FBF7F);
      case EdgeKind.conflicts:
        return const Color(0xFFE5575F);
      default:
        return AppColors.text;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    Offset pos(GraphNode n) => Offset(n.position.dx * size.width, n.position.dy * size.height);
    final nodeMap = {for (final n in nodes) n.id: n};
    bool hidden(GraphNode n) => visibleCategories != null && !visibleCategories!.contains(n.category);

    for (final edge in edges) {
      final from = nodeMap[edge.fromId];
      final to = nodeMap[edge.toId];
      if (from == null || to == null) continue;

      final selectedNode = selectedNodeId != null && (edge.fromId == selectedNodeId || edge.toId == selectedNodeId);
      final selectedEdge = edge.key == selectedEdgeKey;
      final highlighted = selectedNode || selectedEdge;
      // ребро приглушается, если НИ один его конец не входит в фильтр
      final filteredOut = hidden(from) && hidden(to);

      final base = edgeColor(edge.kind);
      final alpha = highlighted ? 0.95 : (filteredOut ? 0.05 : (edge.kind == EdgeKind.related ? 0.22 : 0.6));
      final paint = Paint()
        ..color = (selectedEdge ? AppColors.text : base).withValues(alpha: alpha)
        ..strokeWidth = 0.8 + edge.weight * 0.8 + (highlighted ? 0.8 : 0.0)
        ..strokeCap = StrokeCap.round;

      final a = pos(from), b = pos(to);
      if (edge.kind == EdgeKind.conflicts) {
        _dashed(canvas, a, b, paint);
      } else {
        canvas.drawLine(a, b, paint);
      }

      // стрелка у конца направленной связи, на краю целевого узла
      if (EdgeKind.isDirected(edge.kind) && !filteredOut) {
        final d = b - a;
        if (d.distance > 1) {
          final dir = d / d.distance;
          final r = radiusOf(degree[to.id] ?? 0, to.id == selectedNodeId) + 3;
          final tip = b - dir * r;
          final normal = Offset(-dir.dy, dir.dx);
          final arrow = Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo((tip - dir * 9 + normal * 4.5).dx, (tip - dir * 9 + normal * 4.5).dy)
            ..lineTo((tip - dir * 9 - normal * 4.5).dx, (tip - dir * 9 - normal * 4.5).dy)
            ..close();
          canvas.drawPath(arrow, Paint()..color = paint.color);
        }
      }

      if (!filteredOut) {
        // середина связи — место, куда нажимать, чтобы выбрать её
        canvas.drawCircle((a + b) / 2, selectedEdge ? 4.5 : 2.5, Paint()..color = selectedEdge ? AppColors.text : AppColors.muted.withValues(alpha: 0.5));
      }
    }

    for (final node in nodes) {
      final p = pos(node);
      final selected = node.id == selectedNodeId;
      final filteredOut = hidden(node);
      final opacity = filteredOut ? 0.20 : 1.0;
      final r = radiusOf(degree[node.id] ?? 0, selected);

      canvas.drawCircle(p, r, Paint()..color = node.color.withValues(alpha: opacity));
      if (selected) {
        canvas.drawCircle(p, r + 4, Paint()
          ..color = AppColors.text
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
      }

      if (isolated.contains(node.id)) {
        _dashedCircle(canvas, p, r + 6, Paint()
          ..color = AppColors.muted.withValues(alpha: 0.8 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4);
      }

      final tp = TextPainter(
        text: TextSpan(
          text: node.label,
          style: TextStyle(
            fontFamily: 'Inter', // холст не наследует тему
            color: (selected ? AppColors.text : AppColors.muted).withValues(alpha: opacity),
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: max(40.0, size.width - 12));

      // подпись не выходит за границы холста
      final tx = clampD(p.dx - tp.width / 2, 6, max(6.0, size.width - tp.width - 6));
      final ty = clampD(p.dy + r + 6, 2, max(2.0, size.height - tp.height - 6));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(tx - 4, ty - 2, tp.width + 8, tp.height + 4), const Radius.circular(4)),
        Paint()..color = AppColors.card.withValues(alpha: 0.9 * opacity),
      );
      tp.paint(canvas, Offset(tx, ty));
      tp.dispose();
    }
  }

  static void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final d = b - a;
    final len = d.distance;
    if (len < 1) return;
    final dir = d / len;
    const dash = 7.0, gap = 5.0;
    double t = 0;
    while (t < len) {
      final e = min(t + dash, len);
      canvas.drawLine(a + dir * t, a + dir * e, paint);
      t += dash + gap;
    }
  }

  static void _dashedCircle(Canvas canvas, Offset c, double r, Paint paint) {
    const segments = 14;
    for (int i = 0; i < segments; i++) {
      final a0 = (2 * pi * i) / segments;
      final a1 = a0 + (2 * pi / segments) * 0.55;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a0, a1 - a0, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LifeGraphPainter old) => true;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
        final ordered = [for (final n in nodes) if (semanticLabels[n.id] != null) n]
          // порядок чтения — сверху вниз, слева направо
          ..sort((a, b) {
            final byTop = a.position.dy.compareTo(b.position.dy);
            return byTop != 0 ? byTop : a.position.dx.compareTo(b.position.dx);
          });
        return [
          for (final n in ordered)
            CustomPainterSemantics(
              key: ValueKey('node_sem_${n.id}'),
              // 48 px — область фокуса не меньше рекомендуемой, даже если кружок узла мельче
              rect: Rect.fromCenter(center: Offset(n.position.dx * size.width, n.position.dy * size.height), width: 48, height: 48),
              properties: SemanticsProperties(
                label: semanticLabels[n.id],
                button: true,
                selected: n.id == selectedNodeId,
                textDirection: TextDirection.ltr,
                onTap: onSelect == null ? null : () => onSelect!(n.id),
              ),
            ),
        ];
      };

  @override
  bool shouldRebuildSemantics(covariant LifeGraphPainter old) => true;
}
