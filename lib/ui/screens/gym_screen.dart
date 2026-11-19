import 'package:flutter/material.dart';

import '../../core/sections.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/workout_stats.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../painters/anatomy_geometry.dart';
import '../widgets/body_map_card.dart';
import '../widgets/body_metrics.dart';
import '../widgets/toast.dart';
import '../widgets/comparison_card.dart';
import '../widgets/log_set_dialog.dart';
import 'journal_screen.dart';
import '../widgets/adaptive_pair.dart';

/// Вкладка «Тело»: карта тела, вход в журнал, список мышечных групп.
class GymScreen extends StatefulWidget {
  final AppController controller;
  final BodyMapSelection selection;
  const GymScreen({super.key, required this.controller, required this.selection});

  @override
  State<GymScreen> createState() => _GymScreenState();
}

class _GymScreenState extends State<GymScreen> {
  AppController get c => widget.controller;
  BodyMapSelection get selection => widget.selection;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: selection, builder: (context, _) => _buildGymScreen());
  }

  Future<void> _logWorkoutForMuscle(MuscleGroup muscle) => showLogSetDialog(context, c, muscleId: muscle.id);

  void _openJournal() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => JournalScreen(controller: c)));
  }

  /// Карточка-вход в журнал на вкладке «Тело»: сводка объёма за 7 дней.
  Widget _journalEntryCard() {
    final sets = c.sets;
    final vol = volumeInWindow(sets, c.now, 7);
    final cnt = setsInWindow(sets, c.now, 7);
    return Material(
      color: AppColors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.tile), side: const BorderSide(color: AppColors.border)),
      child: InkWell(
        onTap: _openJournal,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(Icons.menu_book_outlined, color: AppColors.text),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Журнал тренировок', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      sets.isEmpty ? 'История подходов, прогрессия и объём' : 'За 7 дней: $cnt подх. · ${fmtVolume(vol)} кг',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }

  /// Тренировка дня ещё не записана событием: подходы журнала → событие «Тело» со ссылками на них.
  Widget _workoutEventTile() {
    final sets = c.unrecordedSets(c.now);
    final volume = sets.fold<double>(0, (a, s) => a + s.weight * s.reps);
    return Container(
      key: const ValueKey('workout_event_tile'),
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
      decoration: tileDecoration(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Тренировка сегодня', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text('${sets.length} подх. · ${fmtVolume(volume)} кг — ещё не в хронике', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            key: const ValueKey('record_workout'),
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
            onPressed: () {
              final id = c.recordWorkoutEvent(c.now);
              showToast(context, id == null ? 'Не удалось записать событие' : 'Тренировка записана событием');
            },
            child: const Text('В события'),
          ),
        ],
      ),
    );
  }

  Widget _buildGymScreen() {
    final paths = AnatomicalGeometry.pathsFor(selection.showFront);
    // порядок — как на силуэте; «икры» есть и в списке заднего вида
    final visible = [for (final k in paths.keys) if (c.muscles[k] != null) c.muscles[k]!];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('Тело', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -0.8))),
          const SizedBox(height: 2),
          const Text('Вес, восстановление, тренировки', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 20),
          if (!c.isShown(Sections.weight) && !c.isShown(Sections.workouts))
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Разделы «Вес и ИМТ» и «Тренировки» скрыты. Включить — в настройках, «Разделы». '
                'События и процессы тела по-прежнему в «Событиях» и Хронике.',
                key: ValueKey('body_all_hidden'),
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
          if (c.isShown(Sections.weight)) ...[BodyMetrics(controller: c), const SizedBox(height: 12)],
          if (c.isShown(Sections.workouts)) ...[
            BodyMapCard(controller: c, selection: selection),
            const SizedBox(height: 12),
            _journalEntryCard(),
            if (c.unrecordedSets(c.now).isNotEmpty) ...[const SizedBox(height: 12), _workoutEventTile()],
            const SizedBox(height: 16),
            ComparisonCard(controller: c),
            const SizedBox(height: 16),
            const Text('Группы мышц', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),
          ],
          for (final muscle in c.isShown(Sections.workouts) ? visible : const <MuscleGroup>[])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: AppColors.card,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: selection.muscleId == muscle.id ? AppColors.text : AppColors.border, width: selection.muscleId == muscle.id ? 1.2 : 1),
                ),
                child: ListTile(
                  onTap: () => selection.select(muscle.id),
                  title: Text(muscle.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('1RM ${muscle.maxWeight.toInt()} кг · ${muscle.lastTrained}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                      // при крупном шрифте кнопка — под текстом: иначе название мышцы рвётся посередине
                      if (largeText(context))
                        OutlinedButton(onPressed: () => _logWorkoutForMuscle(muscle), child: const Text('+ Подход', style: TextStyle(fontSize: 13))),
                    ],
                  ),
                  trailing: largeText(context)
                      ? null
                      : OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                          onPressed: () => _logWorkoutForMuscle(muscle),
                          child: const Text('+ Подход', style: TextStyle(fontSize: 13)),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
