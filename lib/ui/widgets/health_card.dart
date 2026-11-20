import 'package:flutter/material.dart';

import '../../core/chart_text.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_controller.dart';
import '../painters/chart_painters.dart';
import 'chart_semantics.dart';
import 'form_dialog.dart';
import 'health_actions.dart';
import 'process_ui.dart';

/// Карточка «Здоровье и активность»: шаги, калории, белок, 7-дневная динамика, Health Connect.
class HealthCard extends StatefulWidget {
  final AppController controller;
  const HealthCard({super.key, required this.controller});

  @override
  State<HealthCard> createState() => _HealthCardState();
}

class _HealthCardState extends State<HealthCard> {
  AppController get c => widget.controller;

  Future<void> _editHealthMetricsDialog() async {
    // при подключённом Health Connect шаги и калории приходят из источника — вручную правится только белок
    final auto = c.healthEnabled;
    final r = await showFormDialog(
      context,
      title: auto ? 'Белок за день' : 'Сводка активности дня',
      actionLabel: 'Обновить',
      fields: [
        if (!auto) FieldSpec('s', 'Шаги', initial: '${c.dailySteps}', numeric: true),
        if (!auto) FieldSpec('c', 'Активные калории (ккал)', initial: '${c.activeCalories}', numeric: true),
        FieldSpec('p', 'Белок (г)', initial: '${c.proteinGrams}', numeric: true),
      ],
    );
    if (r == null || !mounted) return;
    c.updateHealth(
      steps: auto ? null : parseInt(r['s']!),
      calories: auto ? null : parseInt(r['c']!),
      protein: parseInt(r['p']!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('HEALTH & ACTIVITY (7 ДНЕЙ)', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.bold))),
              if (c.healthSyncing)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent))
              else if (c.healthSupported)
                IconButton(
                  icon: const Icon(Icons.sync, color: AppColors.accent, size: 20),
                  tooltip: c.healthEnabled ? 'Синхронизировать' : 'Подключить Health Connect',
                  onPressed: () => syncHealthWithToast(context, c),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              IconButton(
                icon: const Icon(Icons.edit, color: AppColors.muted, size: 18),
                tooltip: 'Ввести вручную',
                onPressed: _editHealthMetricsDialog,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  healthStatusLine(c),
                  style: TextStyle(color: c.healthMessage != null ? AppColors.red : AppColors.muted, fontSize: 10),
                ),
              ),
              if (c.healthEnabled)
                TextButton(
                  onPressed: c.disconnectHealth,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 24)),
                  child: const Text('Отключить', style: TextStyle(fontSize: 10, color: AppColors.muted)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // равные доли ширины: на узком экране колонки переносят текст, а не вылезают за край
              Expanded(child: _MetricCol('Шаги', fmtMoney(c.dailySteps), 'Цель: ${fmtMoney(c.stepsGoal)}', Colors.cyanAccent)),
              Expanded(child: _MetricCol('Активность', '${c.activeCalories} ккал', 'Калории', Colors.orangeAccent)),
              Expanded(child: _MetricCol('Белок', '${c.proteinGrams}г', 'Норма: ${c.proteinGoal}г', Colors.greenAccent)),
            ],
          ),
          const SizedBox(height: 14),
          if (c.snapshotFor(c.now)?.sleepMinutes != null) ...[
            Text(
              'Сон прошлой ночью: ${fmtMinutes(c.snapshotFor(c.now)!.sleepMinutes!)} · Health Connect',
              key: const ValueKey('sleep_line'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
          ],
          const Text('ДИНАМИКА ШАГОВ ЗА НЕДЕЛЮ:', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          ChartSemantics(
            label: 'Шаги за неделю: ${describeSeries(c.stepsWeekHistory, labels: c.weekLabels)}',
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: CustomPaint(painter: MiniSparklinePainter(data: c.stepsWeekHistory, color: Colors.cyanAccent)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCol extends StatelessWidget {
  final String title;
  final String val;
  final String sub;
  final Color col;
  const _MetricCol(this.title, this.val, this.sub, this.col);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 4),
        Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: col)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
      ],
    );
  }
}
