import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/models.dart';

void drawText(Canvas canvas, String text, Offset offset, TextStyle style, {double anchor = 0, TextAlign align = TextAlign.start}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: align,
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(offset.dx - tp.width * anchor, offset.dy));
  tp.dispose();
}

// ---------------------------------------------------------------------------
// 5. ХОЛСТЫ
// ---------------------------------------------------------------------------

/// Сравнение двух рядов. Ряды уже выровнены по длине (хвост), подписи соответствуют точкам.
class DualLineComparisonPainter extends CustomPainter {
  final List<double> dataA;
  final List<double> dataB;
  final List<String> labels;
  final Color colorA;
  final Color colorB;
  final String unitA;
  final String unitB;

  DualLineComparisonPainter({
    required this.dataA,
    required this.dataB,
    required this.labels,
    required this.colorA,
    required this.colorB,
    required this.unitA,
    required this.unitB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = min(dataA.length, dataB.length);
    if (n < 2) return;

    // Боковые поля: крайние точки и подписи больше не обрезаются.
    const padX = 20.0, top = 28.0, bottom = 22.0;
    final plotW = size.width - padX * 2;
    final plotH = size.height - top - bottom;
    final stepX = plotW / (n - 1);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = top + plotH * f;
      canvas.drawLine(Offset(padX, y), Offset(size.width - padX, y), gridPaint);
    }

    final minA = dataA.reduce(min), maxA = dataA.reduce(max);
    final minB = dataB.reduce(min), maxB = dataB.reduce(max);

    double yOf(double v, double mn, double mx) {
      final norm = mx == mn ? 0.5 : (v - mn) / (mx - mn); // плоский ряд — по центру, а не прижат к низу
      return top + plotH * (1 - norm);
    }

    final pathA = Path(), pathB = Path();
    final dotA = Paint()..color = colorA, dotB = Paint()..color = colorB;
    final labelStyle = const TextStyle(color: Colors.white38, fontSize: 9);

    for (int i = 0; i < n; i++) {
      final x = padX + i * stepX;
      final yA = yOf(dataA[i], minA, maxA);
      final yB = yOf(dataB[i], minB, maxB);
      if (i == 0) {
        pathA.moveTo(x, yA);
        pathB.moveTo(x, yB);
      } else {
        pathA.lineTo(x, yA);
        pathB.lineTo(x, yB);
      }
      canvas.drawCircle(Offset(x, yA), 4, dotA);
      canvas.drawCircle(Offset(x, yB), 4, dotB);
      if (i < labels.length) {
        drawText(canvas, labels[i], Offset(x, size.height - 14), labelStyle, anchor: 0.5);
      }
    }

    canvas.drawPath(pathA, Paint()..color = colorA..strokeWidth = 2.5..style = PaintingStyle.stroke);
    canvas.drawPath(pathB, Paint()..color = colorB..strokeWidth = 2.5..style = PaintingStyle.stroke);

    drawText(canvas, '${dataA.last.toInt()} $unitA', Offset(size.width, 0), TextStyle(color: colorA, fontSize: 9, fontWeight: FontWeight.bold), anchor: 1);
    drawText(canvas, '${dataB.last.toInt()} $unitB', Offset(size.width, 13), TextStyle(color: colorB, fontSize: 9, fontWeight: FontWeight.bold), anchor: 1);
  }

  @override
  bool shouldRepaint(covariant DualLineComparisonPainter old) => true; // данные мутируются на месте
}

class MiniSparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  MiniSparklinePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    if (data.length == 1) {
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), 4, Paint()..color = color);
      return;
    }

    final minVal = data.reduce(min);
    final maxVal = data.reduce(max);
    final stepX = size.width / (data.length - 1);
    final dotPaint = Paint()..color = color; // один Paint вместо создания в цикле

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final norm = maxVal == minVal ? 0.5 : (data[i] - minVal) / (maxVal - minVal);
      final y = size.height - (norm * (size.height - 12)) - 6;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0.3), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(path, Paint()..color = color..strokeWidth = 2.0..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant MiniSparklinePainter old) => true;
}

class SalaryLineChartPainter extends CustomPainter {
  final List<SalaryStep> steps;
  SalaryLineChartPainter({required this.steps});

  @override
  void paint(Canvas canvas, Size size) {
    if (steps.isEmpty) return;

    const padX = 24.0; // поля, чтобы первая/последняя подписи не обрезались
    const labelStyle = TextStyle(color: Colors.white70, fontSize: 10);
    final dot = Paint()..color = AppColors.green;

    if (steps.length == 1) {
      final x = size.width / 2, y = size.height / 2;
      canvas.drawCircle(Offset(x, y), 6, dot);
      drawText(canvas, '${steps[0].year}\n${steps[0].salary ~/ 1000}к', Offset(x, y - 32), labelStyle, anchor: 0.5, align: TextAlign.center);
      return;
    }

    final maxSalary = steps.map((s) => s.salary).reduce(max).toDouble();
    final top = maxSalary * 1.3; // запас сверху под подпись
    final plotW = size.width - padX * 2;
    final stepX = plotW / (steps.length - 1);

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < steps.length; i++) {
      final x = padX + i * stepX;
      final norm = top == 0 ? 0.0 : steps[i].salary / top;
      final y = size.height - (norm * (size.height - 30)) - 20;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      canvas.drawCircle(Offset(x, y), 5, dot);
      canvas.drawCircle(Offset(x, y), 2, Paint()..color = Colors.black);
      drawText(canvas, '${steps[i].year}\n${steps[i].salary ~/ 1000}к', Offset(x, y - 30), labelStyle, anchor: 0.5, align: TextAlign.center);
    }

    fillPath.lineTo(padX + plotW, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          colors: [AppColors.green.withValues(alpha: 0.35), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(path, Paint()..color = AppColors.green..strokeWidth = 3.0..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant SalaryLineChartPainter old) => true;
}

/// Столбцы объёма нагрузки (дни или недели). Последний столбец — текущий период, выделен ярче.
class VolumeBarsPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final Color color;

  VolumeBarsPainter({required this.values, required this.labels, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const top = 16.0, bottom = 16.0;
    final plotH = size.height - top - bottom;
    final maxV = values.reduce(max);
    final slot = size.width / values.length;
    final barW = min(slot * 0.62, 34.0);
    final baseY = top + plotH;

    canvas.drawLine(
      Offset(0, baseY),
      Offset(size.width, baseY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..strokeWidth = 1,
    );

    for (int i = 0; i < values.length; i++) {
      final cx = slot * (i + 0.5);
      final h = maxV <= 0 ? 0.0 : (values[i] / maxV) * plotH;
      final isLast = i == values.length - 1;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barW / 2, baseY - max(h, values[i] > 0 ? 2.0 : 0.0), barW, max(h, values[i] > 0 ? 2.0 : 0.0)),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: isLast ? 0.95 : 0.45));
      if (values[i] > 0) {
        drawText(canvas, fmtVolume(values[i]), Offset(cx, baseY - max(h, 2.0) - 12), const TextStyle(color: Colors.white54, fontSize: 8), anchor: 0.5);
      }
      if (i < labels.length) {
        drawText(canvas, labels[i], Offset(cx, baseY + 3), const TextStyle(color: Colors.white38, fontSize: 9), anchor: 0.5);
      }
    }
  }

  @override
  bool shouldRepaint(covariant VolumeBarsPainter old) => true;
}

/// Парные столбцы по периодам (доходы и расходы по месяцам). Последняя пара — текущий период.
class DualBarsPainter extends CustomPainter {
  final List<double> a;
  final List<double> b;
  final List<String> labels;
  final Color colorA;
  final Color colorB;

  DualBarsPainter({required this.a, required this.b, required this.labels, required this.colorA, required this.colorB});

  @override
  void paint(Canvas canvas, Size size) {
    final n = min(a.length, b.length);
    if (n == 0) return;
    const top = 8.0, bottom = 16.0;
    final plotH = size.height - top - bottom;
    final maxV = [...a.take(n), ...b.take(n)].reduce(max);
    final slot = size.width / n;
    final barW = min(slot * 0.30, 18.0);
    final baseY = top + plotH;

    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), Paint()..color = Colors.white.withValues(alpha: 0.08)..strokeWidth = 1);

    void bar(double cx, double v, Color color, bool isLast) {
      final h = maxV <= 0 ? 0.0 : (v / maxV) * plotH;
      final hh = v > 0 ? max(h, 2.0) : 0.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(cx - barW / 2, baseY - hh, barW, hh), const Radius.circular(3)),
        Paint()..color = color.withValues(alpha: isLast ? 0.95 : 0.5),
      );
    }

    for (int i = 0; i < n; i++) {
      final cx = slot * (i + 0.5);
      final isLast = i == n - 1;
      bar(cx - barW * 0.6, a[i], colorA, isLast);
      bar(cx + barW * 0.6, b[i], colorB, isLast);
      if (i < labels.length) {
        drawText(canvas, labels[i], Offset(cx, baseY + 3), const TextStyle(color: Colors.white38, fontSize: 9), anchor: 0.5);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DualBarsPainter old) => true;
}
