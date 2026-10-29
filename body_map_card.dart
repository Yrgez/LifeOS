import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../state/app_controller.dart';
import '../painters/anatomy_geometry.dart';
import '../painters/body_painter.dart';
import '../painters/chart_painters.dart';
import 'log_set_dialog.dart';

/// Общий выбор на карте тела: ракурс и выбранная мышца. Один объект на HUB и «Тело» — выбор синхронизирован.
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.biotech, color: AppColors.green, size: 16),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        selection.showFront ? 'ПРОЕКЦИЯ: ANTERIOR (ФАС)' : 'ПРОЕКЦИЯ: POSTERIOR (ТЫЛ)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: selection.flip,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.flip_camera_android, size: 12, color: AppColors.green),
                      const SizedBox(width: 4),
                      Text(selection.showFront ? 'Повернуть спиной' : 'Повернуть лицом', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 380,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final size = Size(constraints.maxWidth, 380);
                return GestureDetector(
                  onTapUp: (d) => _handleAnatomicalTap(d.localPosition, size),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: AnatomicalSilhouettePainter(muscles: c.muscles, isFront: selection.showFront, selectedMuscleId: selection.muscleId),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (activeMuscle != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: activeMuscle.color.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(radius: 5, backgroundColor: activeMuscle.color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(activeMuscle.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(
                              'Готовность: ${(activeMuscle.recovery * 100).round()}% • 1RM: ${activeMuscle.maxWeight.toInt()} кг',
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                        ),
                        onPressed: () => showLogSetDialog(context, c, muscleId: activeMuscle.id),
                        child: const Text('Записать подход', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ИСТОРИЯ 1RM (ПРОГРЕСС СИЛЫ):', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                      // раньше показывался последний подход как «рекорд»; теперь — настоящий максимум
                      Text('${activeMuscle.maxWeight.toInt()} кг рекорд', style: const TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 42,
                    width: double.infinity,
                    child: CustomPaint(painter: MiniSparklinePainter(data: c.progression(activeMuscle.id), color: activeMuscle.color)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _handleAnatomicalTap(Offset localPos, Size size) {
    final scale = min(size.width / AnatomicalGeometry.baseWidth, size.height / AnatomicalGeometry.baseHeight);
    final dx = (size.width - AnatomicalGeometry.baseWidth * scale) / 2;
    final dy = (size.height - AnatomicalGeometry.baseHeight * scale) / 2;
    final touch = Offset((localPos.dx - dx) / scale, (localPos.dy - dy) / scale);

    for (final entry in AnatomicalGeometry.pathsFor(selection.showFront).entries) {
      if (entry.value.contains(touch)) {
        selection.select(entry.key);
        return;
      }
    }
  }
}
