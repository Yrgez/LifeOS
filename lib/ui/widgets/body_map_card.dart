import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/chart_text.dart';
import '../../core/recovery_stats.dart';
import '../../core/theme.dart';
import '../../state/app_controller.dart';
import '../painters/anatomy_geometry.dart';
import '../painters/body_painter.dart';
import '../painters/chart_painters.dart';
import 'adaptive_pair.dart';
import 'chart_semantics.dart';
import 'log_set_dialog.dart';
import 'segment_pill.dart';

/// Выбор на карте тела: ракурс и выбранная мышца. Хранится в оболочке и переживает переключение вкладок.
class BodyMapSelection extends ChangeNotifier {
  bool showFront = true;
  String? muscleId = 'chest';

  void select(String id) {
    muscleId = id;
    notifyListeners();
  }

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
    final info = activeMuscle == null
        ? const SizedBox()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(activeMuscle.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 2),
              Text(
                _recoveryText(muscleRecovery(activeMuscle, controller.now), activeMuscle.lastTrainedOn(controller.now)),
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          );
    final addSet = ElevatedButton.icon(
      style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
      onPressed: activeMuscle == null ? null : () => showLogSetDialog(context, c, muscleId: activeMuscle.id),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('Подход'),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: tileDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wrap: при крупном системном шрифте переключатель уходит на следующую строку, а не за край
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              const Text('Мышцы', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              // переключатель ракурса — «таблетка» из двух сегментов
              SegmentPill<bool>(
                options: const {true: 'Спереди', false: 'Сзади'},
                value: selection.showFront,
                onChanged: selection.setFront,
                keyPrefix: 'body_front_',
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
                return Semantics(
                  container: true,
                  label: 'Фигура, ${selection.showFront ? 'спереди' : 'сзади'}: выберите мышцу',
                  child: GestureDetector(
                    // для программы чтения экрана нажатие — по мышцам из semanticsBuilder, а не по фигуре целиком
                    excludeFromSemantics: true,
                    onTapUp: (d) => _handleAnatomicalTap(d.localPosition, size),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: size,
                        painter: AnatomicalSilhouettePainter(
                          muscles: c.muscles,
                          isFront: selection.showFront,
                          selectedMuscleId: selection.muscleId,
                          semanticLabels: {
                            for (final id in AnatomicalGeometry.pathsFor(selection.showFront).keys)
                              if (c.muscles[id] case final m?) id: '${m.name}. ${_recoveryText(muscleRecovery(m, c.now), m.lastTrainedOn(c.now))}',
                          },
                          onSelect: selection.select,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          if (activeMuscle != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: tileDecoration(radius: 20, color: AppColors.field),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // при крупном шрифте кнопка уходит под название: в узкой колонке слова рвались бы посередине
                  if (largeText(context))
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, const SizedBox(height: 8), addSet])
                  else
                    Row(children: [Expanded(child: info), const SizedBox(width: 8), addSet]),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Expanded(child: Text('Рекорд 1RM', style: TextStyle(color: AppColors.muted, fontSize: 13))),
                      // настоящий максимум, а не последний подход
                      Text('${activeMuscle.maxWeight.toInt()} кг', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ChartSemantics(
                    label: 'Прогрессия 1RM, кг: ${describeSeries(c.progression(activeMuscle.id))}',
                    child: SizedBox(
                      height: 42,
                      width: double.infinity,
                      child: CustomPaint(painter: MiniSparklinePainter(data: c.progression(activeMuscle.id), color: AppColors.text)),
                    ),
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

/// «Тренировка 2 дн. назад · ещё ≈ 20 ч (оценка)» — без процента «готовности».
String _recoveryText(MuscleRecovery r, String lastTrained) {
  if (r.lastTrainedAt == null) return lastTrained;
  return 'Тренировка ${lastTrained.toLowerCase()} · ${r.recovered ? 'восстановлена' : 'ещё ${fmtHoursLeft(r.hoursLeft)}'} (оценка)';
}
