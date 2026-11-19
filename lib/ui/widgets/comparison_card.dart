import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/chart_text.dart';
import '../../core/theme.dart';
import '../../state/app_controller.dart';
import '../painters/chart_painters.dart';
import 'chart_semantics.dart';
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

    // Коэффициент корреляции по 7 точкам не говорит о связи ничего надёжного (и дни без данных здесь — нули),
    // поэтому число и вердикт не показываются: только сами кривые и честное число точек.
    final corrText = 'Точек: $n. Этого мало для вывода о связи — сравнивайте форму кривых сами; '
        'дни без данных показаны нулём.';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: tileDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.compare_arrows, color: AppColors.text, size: 18),
              SizedBox(width: 8),
              Flexible(
                child: Text('Сравнение метрик', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
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
          ChartSemantics(
            label: 'Сравнение. ${_metricNames[_compareMetricA]}: ${describeSeries(seriesA, labels: labels)}. '
                '${_metricNames[_compareMetricB]}: ${describeSeries(seriesB, labels: labels)}',
            child: SizedBox(
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
          ),
          const SizedBox(height: 8),
          Text(corrText, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          const Text('Каждая кривая приведена к своему диапазону (от минимума до максимума), чтобы сравнить форму.', style: TextStyle(color: AppColors.muted, fontSize: 10)),
        ],
      ),
    );
  }
}
