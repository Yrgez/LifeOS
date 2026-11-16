import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/workout_stats.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../painters/anatomy_geometry.dart';
import '../widgets/body_map_card.dart';
import '../widgets/body_metrics.dart';
import '../widgets/comparison_card.dart';
import '../widgets/log_set_dialog.dart';
import 'journal_screen.dart';

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

  Widget _buildGymScreen() {
    final groups = AnatomicalGeometry.groupsFor(selection.showFront);
    // порядок — сверху вниз по телу, как на фигуре
    final visible = [for (final k in groups) if (c.muscles[k] != null) c.muscles[k]!];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Тело', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -0.8)),
          const SizedBox(height: 2),
          const Text('Вес, восстановление, тренировки', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 20),
          BodyMetrics(controller: c),
          const SizedBox(height: 12),
          BodyMapCard(controller: c, selection: selection),
          const SizedBox(height: 12),
          _journalEntryCard(),
          const SizedBox(height: 16),
          ComparisonCard(controller: c),
          const SizedBox(height: 16),
          const Text('Группы мышц', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          for (final muscle in visible)
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
                  subtitle: Text('1RM ${muscle.maxWeight.toInt()} кг · ${muscle.lastTrained}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  trailing: OutlinedButton(
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
