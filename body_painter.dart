import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import 'anatomy_geometry.dart';

class AnatomicalSilhouettePainter extends CustomPainter {
  final Map<String, MuscleGroup> muscles;
  final bool isFront;
  final String? selectedMuscleId;

  AnatomicalSilhouettePainter({required this.muscles, required this.isFront, this.selectedMuscleId});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = min(size.width / AnatomicalGeometry.baseWidth, size.height / AnatomicalGeometry.baseHeight);
    final dx = (size.width - AnatomicalGeometry.baseWidth * scale) / 2;
    final dy = (size.height - AnatomicalGeometry.baseHeight * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    _paintMannequinBody(canvas);

    for (final entry in AnatomicalGeometry.pathsFor(isFront).entries) {
      final key = entry.key;
      final path = entry.value;
      final isSelected = key == selectedMuscleId;
      final color = muscles[key]?.color ?? AppColors.green;

      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: isSelected ? 0.55 : 0.22)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, isSelected ? 12 : 6),
      );

      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [color.withValues(alpha: isSelected ? 0.85 : 0.50), color.withValues(alpha: isSelected ? 0.40 : 0.15)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(path.getBounds()),
      );

      canvas.drawPath(
        path,
        Paint()
          ..color = isSelected ? Colors.white : color
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.2 : 1.2,
      );
    }

    canvas.restore();
  }

  void _paintMannequinBody(Canvas canvas) {
    final framePaint = Paint()..color = const Color(0xFF13171F)..style = PaintingStyle.fill;
    final strokePaint = Paint()..color = Colors.white10..style = PaintingStyle.stroke..strokeWidth = 1.0;

    const headRect = Rect.fromLTWH(135, 12, 30, 38);
    canvas.drawOval(headRect, framePaint);
    canvas.drawOval(headRect, strokePaint);
    canvas.drawRect(const Rect.fromLTWH(143, 48, 14, 18), framePaint);

    canvas.drawCircle(const Offset(72, 250), 6, framePaint);
    canvas.drawCircle(const Offset(228, 250), 6, framePaint);

    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(112, 436, 18, 16), const Radius.circular(4)), framePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(170, 436, 18, 16), const Radius.circular(4)), framePaint);

    canvas.drawCircle(const Offset(124, 335), 4, strokePaint);
    canvas.drawCircle(const Offset(176, 335), 4, strokePaint);
    canvas.drawCircle(const Offset(84, 175), 3, strokePaint);
    canvas.drawCircle(const Offset(216, 175), 3, strokePaint);
  }

  // Карта muscles — та же ссылка, мутируется на месте, поэтому сравнение по ссылке
  // (как было раньше) НЕ перерисовывало силуэт после записи подхода.
  @override
  bool shouldRepaint(covariant AnatomicalSilhouettePainter old) => true;
}
