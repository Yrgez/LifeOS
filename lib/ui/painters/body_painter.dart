import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/recovery_stats.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import 'anatomy_geometry.dart';

/// Плоская анатомическая фигура в общем стиле приложения. Тело состоит из мышц: сегменты лежат прямо на
/// фоне плитки, разделены тонкими линиями цвета фона, а голова, кисти, колени и стопы показаны контуром.
/// Коралловый — группа ещё восстанавливается (насыщеннее — больше часов осталось по оценке),
/// светлая — выбранная. Без свечения и градиентов.
class AnatomicalSilhouettePainter extends CustomPainter {
  final Map<String, MuscleGroup> muscles;
  final bool isFront;
  final String? selectedMuscleId;
  final DateTime now;

  AnatomicalSilhouettePainter({required this.muscles, required this.isFront, this.selectedMuscleId, DateTime? now}) : now = now ?? DateTime.now();

  static const muscle = Color(0xFF566A84); // мышца в покое
  static const load = Color(0xFFE5484D); // восстанавливается
  static const selected = Color(0xFFE6EBF2); // выбранная
  static const outline = Color(0xFF5A6678); // контур тела там, где мышц нет
  static const gap = AppColors.card; // линии между мышцами = фон плитки

  /// Цвет группы: покой → коралловый по доле оставшегося восстановления → осветление, если выбрана.
  Color _fill(String? group) {
    var fill = muscle;
    final m = group == null ? null : muscles[group];
    if (m != null) {
      final r = muscleRecovery(m, now);
      if (!r.recovered && m.recoveryHours > 0) {
        final share = (r.hoursLeft / m.recoveryHours).clamp(0.0, 1.0);
        fill = Color.lerp(muscle, load, 0.4 + 0.6 * share)!;
      }
    }
    if (group != null && group == selectedMuscleId) fill = Color.lerp(fill, selected, fill == muscle ? 1.0 : 0.5)!;
    return fill;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = min(size.width / AnatomicalGeometry.baseWidth, size.height / AnatomicalGeometry.baseHeight);
    final dx = (size.width - AnatomicalGeometry.baseWidth * scale) / 2;
    final dy = (size.height - AnatomicalGeometry.baseHeight * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    final silhouette = AnatomicalGeometry.silhouetteFor(isFront);
    final outlinePaint = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeJoin = StrokeJoin.round;
    final gapPaint = Paint()
      ..color = gap
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(silhouette, outlinePaint);

    // Сегменты — по порядку, каждый следующий поверх предыдущих; всё обрезано по контуру тела.
    canvas.save();
    canvas.clipPath(silhouette);
    final fills = <String?, Color>{};
    for (final s in AnatomicalGeometry.shapesFor(isFront)) {
      canvas.drawPath(s.path, Paint()..color = fills.putIfAbsent(s.group, () => _fill(s.group)));
      canvas.drawPath(s.path, gapPaint);
    }
    canvas.restore();

    // Голова поверх: закрывает стык шеи.
    canvas.drawPath(AnatomicalGeometry.head, Paint()..color = gap);
    canvas.drawPath(AnatomicalGeometry.head, outlinePaint);

    canvas.restore();
  }

  // Карта muscles — та же ссылка, мутируется на месте: перерисовываем всегда.
  @override
  bool shouldRepaint(covariant AnatomicalSilhouettePainter old) => true;
}
