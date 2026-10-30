import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/workout_stats.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../painters/anatomy_geometry.dart';
import '../widgets/body_map_card.dart';
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: AppColors.green.withValues(alpha: 0.3))),
      child: InkWell(
        onTap: _openJournal,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.menu_book, color: AppColors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ЖУРНАЛ ТРЕНИРОВОК', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.6)),
                    const SizedBox(height: 2),
                    Text(
                      sets.isEmpty ? 'История подходов, прогрессия и объём нагрузки' : 'За 7 дней: $cnt подх. • ${fmtVolume(vol)} кг',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleBtn(String text, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: active ? AppColors.green : Colors.transparent, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: active ? Colors.black : Colors.white60, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildGymScreen() {
    final paths = AnatomicalGeometry.pathsFor(selection.showFront);
    // порядок — как на силуэте; «икры» теперь есть и в списке заднего вида
    final visible = [for (final k in paths.keys) if (c.muscles[k] != null) c.muscles[k]!];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('АНАТОМИЧЕСКАЯ КАРТА ТЕЛА', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Container(
                decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    _toggleBtn('Спереди', selection.showFront, () => selection.setFront(true)),
                    _toggleBtn('Сзади', !selection.showFront, () => selection.setFront(false)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          BodyMapCard(controller: c, selection: selection),
          const SizedBox(height: 12),
          _journalEntryCard(),
          const SizedBox(height: 16),
          const Text('СПИСОК МЫШЕЧНЫХ ГРУПП:', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          for (final muscle in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: selection.muscleId == muscle.id ? const Color(0xFF1C2330) : AppColors.card,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: selection.muscleId == muscle.id ? AppColors.green : Colors.transparent, width: 1.2),
                ),
                child: ListTile(
                  onTap: () => selection.select(muscle.id),
                  leading: CircleAvatar(
                    backgroundColor: muscle.color.withValues(alpha: 0.2),
                    radius: 14,
                    child: CircleAvatar(backgroundColor: muscle.color, radius: 5),
                  ),
                  title: Text(muscle.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('1RM: ${muscle.maxWeight.toInt()} кг • ${muscle.lastTrained}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF202630), elevation: 0),
                    onPressed: () => _logWorkoutForMuscle(muscle),
                    child: const Text('+ Подход', style: TextStyle(fontSize: 12, color: AppColors.green)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
