import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/workout_stats.dart';
import '../../state/app_controller.dart';
import '../painters/chart_painters.dart';
import 'form_dialog.dart';

/// Сравнение двух метрик на одном графике с коэффициентом корреляции.
class ComparisonCard extends StatefulWidget {
  final AppController controller;
  const ComparisonCard({super.key, required this.controller});

  @override
  State<ComparisonCard> createState() => _ComparisonCardState();
}

class _ComparisonCardState extends State<ComparisonCard> {
  static const Map<String, String> _metricNames = {
    'steps': 'Шаги (7 дн)',
    'calories': 'Калории (7 дн)',
    'chest': 'Жим груди 1RM',
    'quads': 'Присед 1RM',
    'graph': 'Узлы Графа',
  };
  static const Map<String, String> _metricUnits = {
    'steps': 'шагов',
    'calories': 'ккал',
    'chest': 'кг',
    'quads': 'кг',
    'graph': 'узлов',
  };
  static const Set<String> _weeklyMetrics = {'steps', 'calories', 'graph'};

  AppController get c => widget.controller;

  String _compareMetricA = 'steps';
  String _compareMetricB = 'calories';

  @override
  Widget build(BuildContext context) {
    // Ряды разной длины выравниваем по ХВОСТУ (последние n значений) — раньше брались первые n,
    // и точки не соответствовали друг другу по времени.
    final rawA = c.metricSeries(_compareMetricA);
    final rawB = c.metricSeries(_compareMetricB);
    final n = min(rawA.length, rawB.length);
    final seriesA = rawA.sublist(rawA.length - n);
    final seriesB = rawB.sublist(rawB.length - n);

    final bothWeekly = _weeklyMetrics.contains(_compareMetricA) && _weeklyMetrics.contains(_compareMetricB);
    final allDays = c.weekLabels;
    final labels = bothWeekly ? allDays.sublist(allDays.length - n) : List.generate(n, (i) => '${i + 1}');

    final r = pearson(seriesA, seriesB);
    String corrText;
    if (r == null) {
      corrText = 'Недостаточно данных для корреляции';
    } else {
      final abs = r.abs();
      final strength = abs >= 0.7 ? 'сильная' : (abs >= 0.4 ? 'умеренная' : 'слабая');
      final dir = abs < 0.2 ? '' : (r > 0 ? ' положительная' : ' отрицательная');
      corrText = 'Корреляция Пирсона: r = ${r.toStringAsFixed(2)} ($strength$dir, n = $n)';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.compare_arrows, color: Colors.cyanAccent, size: 18),
                  SizedBox(width: 8),
                  Text('СРАВНЕНИЕ И КОРРЕЛЯЦИЯ', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.cyanAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Text('2 Метрики', style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LabeledDropdown(
                  label: 'Метрика A (Зеленый)',
                  labelColor: AppColors.green,
                  value: _compareMetricA,
                  items: _metricNames,
                  onChanged: (v) => setState(() => _compareMetricA = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledDropdown(
                  label: 'Метрика B (Бирюзовый)',
                  labelColor: Colors.cyanAccent,
                  value: _compareMetricB,
                  items: _metricNames,
                  onChanged: (v) => setState(() => _compareMetricB = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 170,
            width: double.infinity,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: DualLineComparisonPainter(
                  dataA: seriesA,
                  dataB: seriesB,
                  labels: labels,
                  colorA: AppColors.green,
                  colorB: Colors.cyanAccent,
                  unitA: _metricUnits[_compareMetricA] ?? '',
                  unitB: _metricUnits[_compareMetricB] ?? '',
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(corrText, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          const Text('Кривые нормализованы по шкале 0–100% для выявления взаимной корреляции.', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }
}
