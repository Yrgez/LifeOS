import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/recovery_stats.dart';
import '../../core/theme.dart';
import '../../state/app_controller.dart';
import '../painters/anatomy_geometry.dart';
import '../painters/body_painter.dart';
import '../painters/chart_painters.dart';
import 'log_set_dialog.dart';

/// Выбор на карте тела: ракурс и выбранная мышца. Хранится в оболочке и переживает переключение вкладок.
class BodyMapSelection extends ChangeNotifier {
  bool showFront = true;
  String? muscleId = 'chest';

  void select(String id) {
    muscleId = id;
    notifyListeners();
  }

  /// Повернуть спиной/лицом; выбирается мышца по умолчанию для ракурса.
  void flip() => setFront(!showFront);

  void setFront(bool front) {
    showFront = front;
    muscleId = front ? 'chest' : 'lats';
    notifyListeners();
  }
}

/// Силуэт с группами мышц, готовностью и прогрессией выбранной мышцы.
class BodyMapCard extends StatelessWidget {
  final AppController controller;
  final BodyMapSelection selection;
  const BodyMapCard({super.key, required this.controller, required this.selection});

  AppController get c => controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: selection, builder: (context, _) => _buildVectorBodyCard(context));
  }

  Widget _buildVectorBodyCard(BuildContext context) {
    final activeMuscle = c.muscles[selection.muscleId];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: tileDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Мышцы', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              ),
              // переключатель ракурса — «таблетка» из двух сегментов
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _segment('Спереди', selection.showFront, () => selection.setFront(true)),
                    _segment('Сзади', !selection.showFront, () => selection.setFront(false)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 500,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final size = Size(constraints.maxWidth, 500);
                return GestureDetector(
                  onTapUp: (d) => _handleAnatomicalTap(d.localPosition, size),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: AnatomicalSilhouettePainter(muscles: c.muscles, isFront: selection.showFront, selectedMuscleId: selection.muscleId, now: c.now),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // легенда переносится на узком экране
          const Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 6,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                _LegendDot(AnatomicalSilhouettePainter.load),
                SizedBox(width: 6),
                Flexible(child: Text('восстанавливается (оценка)', style: TextStyle(color: AppColors.muted, fontSize: 12))),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _LegendDot(AnatomicalSilhouettePainter.muscle),
                SizedBox(width: 6),
                Flexible(child: Text('восстановлена', style: TextStyle(color: AppColors.muted, fontSize: 12))),
              ]),
            ],
          ),
          const SizedBox(height: 14),
          if (activeMuscle != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: tileDecoration(radius: 20, color: AppColors.field),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(activeMuscle.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                            const SizedBox(height: 2),
                            Text(
                              _recoveryText(muscleRecovery(activeMuscle, controller.now), activeMuscle.lastTrainedOn(controller.now)),
                              style: const TextStyle(color: AppColors.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
                        onPressed: () => showLogSetDialog(context, c, muscleId: activeMuscle.id),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Подход'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(child: Text('Рекорд 1RM', style: TextStyle(color: AppColors.muted, fontSize: 13))),
                      // настоящий максимум, а не последний подход
                      Text('${activeMuscle.maxWeight.toInt()} кг', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 42,
                    width: double.infinity,
                    child: CustomPaint(painter: MiniSparklinePainter(data: c.progression(activeMuscle.id), color: AppColors.text)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _segment(String label, bool active, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: active ? AppColors.accent : Colors.transparent, borderRadius: BorderRadius.circular(16)),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: active ? Colors.black : AppColors.muted)),
        ),
      );

  void _handleAnatomicalTap(Offset localPos, Size size) {
    final scale = min(size.width / AnatomicalGeometry.baseWidth, size.height / AnatomicalGeometry.baseHeight);
    final dx = (size.width - AnatomicalGeometry.baseWidth * scale) / 2;
    final dy = (size.height - AnatomicalGeometry.baseHeight * scale) / 2;
    final touch = Offset((localPos.dx - dx) / scale, (localPos.dy - dy) / scale);

    final group = AnatomicalGeometry.groupAt(selection.showFront, touch);
    if (group != null && c.muscles.containsKey(group)) selection.select(group);
  }
}

/// «Тренировка 2 дн. назад · ещё ≈ 20 ч (оценка)» — без процента «готовности».
String _recoveryText(MuscleRecovery r, String lastTrained) {
  if (r.lastTrainedAt == null) return lastTrained;
  return 'Тренировка ${lastTrained.toLowerCase()} · ${r.recovered ? 'восстановлена' : 'ещё ${fmtHoursLeft(r.hoursLeft)}'} (оценка)';
}

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot(this.color);

  @override
  Widget build(BuildContext context) => Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
