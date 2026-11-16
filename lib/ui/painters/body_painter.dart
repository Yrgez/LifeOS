import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/recovery_stats.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import 'anatomy_geometry.dart';

/// Плоская анатомическая фигура в общем стиле приложения: тёмно-сланцевый силуэт, мышцы — светлее,
/// разделены тонкими просветами цвета фона. Коралловый — группа ещё восстанавливается (насыщеннее —
/// больше часов осталось по оценке), светлая с белым контуром — выбранная. Без свечения и градиентов.
class AnatomicalSilhouettePainter extends CustomPainter {
  final Map<String, MuscleGroup> muscles;
  final bool isFront;
  final String? selectedMuscleId;
  final DateTime now;

  AnatomicalSilhouettePainter({required this.muscles, required this.isFront, this.selectedMuscleId, DateTime? now}) : now = now ?? DateTime.now();

  static const body = Color(0xFF262C35); // силуэт
  static const muscle = Color(0xFF3A4452); // мышца в покое
  static const neutral = Color(0xFF313946); // сегменты без группы (приводящие, разгибатели спины)
  static const load = Color(0xFFE5484D); // восстанавливается
  static const selected = Color(0xFFD8DEE6); // выбранная
  static const gap = AppColors.card; // просветы между мышцами = фон плитки

  @override
  void paint(Canvas canvas, Size size) {
    final scale = min(size.width / AnatomicalGeometry.baseWidth, size.height / AnatomicalGeometry.baseHeight);
    final dx = (size.width - AnatomicalGeometry.baseWidth * scale) / 2;
    final dy = (size.height - AnatomicalGeometry.baseHeight * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    AnatomicalGeometry.paintSilhouette(canvas, Paint()..color = body);

    final gapPaint = Paint()
      ..color = gap
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round;

    final neutralPath = AnatomicalGeometry.neutralFor(isFront);
    canvas.drawPath(neutralPath, Paint()..color = neutral);
    canvas.drawPath(neutralPath, gapPaint);

    for (final entry in AnatomicalGeometry.pathsFor(isFront).entries) {
      final id = entry.key;
      final path = entry.value;
      final m = muscles[id];
      Color fill = muscle;
      if (m != null) {
        final r = muscleRecovery(m, now);
        if (!r.recovered && m.recoveryHours > 0) {
          final share = (r.hoursLeft / m.recoveryHours).clamp(0.0, 1.0);
          fill = Color.lerp(muscle, load, 0.35 + 0.65 * share)!;
        }
      }
      if (id == selectedMuscleId) fill = Color.lerp(fill, selected, 0.55)!;
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(path, gapPaint);
      if (id == selectedMuscleId) {
        canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
    }

    canvas.restore();
  }

  // Карта muscles — та же ссылка, мутируется на месте: перерисовываем всегда.
  @override
  bool shouldRepaint(covariant AnatomicalSilhouettePainter old) => true;
}
