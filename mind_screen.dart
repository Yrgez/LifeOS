import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../state/app_controller.dart';
import '../widgets/form_dialog.dart';
import '../widgets/goals_ui.dart';

/// Вкладка «Смыслы»: стратегические цели и история достижений.
class MindScreen extends StatefulWidget {
  final AppController controller;
  const MindScreen({super.key, required this.controller});

  @override
  State<MindScreen> createState() => _MindScreenState();
}

class _MindScreenState extends State<MindScreen> {
  AppController get c => widget.controller;

  Future<void> _addNewAchievementDialog() async {
    final r = await showFormDialog(
      context,
      title: 'Зафиксировать достижение',
      actionLabel: 'Сохранить',
      fields: const [
        FieldSpec('t', 'Что было достигнуто?'),
        FieldSpec('c', 'Категория', initial: 'Личный рекорд'),
      ],
      validate: (v) => v['t']!.isNotEmpty,
    );
    if (r == null || !mounted) return;
    c.addAchievement(r['t']!, r['c']!);
  }

  Future<void> _addNewGoalDialog() => showNewGoalDialog(context, c);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('СТРАТЕГИЧЕСКИЕ ЦЕЛИ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(onPressed: _addNewGoalDialog, icon: const Icon(Icons.add_circle, color: AppColors.violet, size: 28)),
            ],
          ),
          const SizedBox(height: 12),
          for (final goal in c.goals) GoalCard(key: ValueKey(goal.id), controller: c, goal: goal),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ИСТОРИЯ ДОСТИЖЕНИЙ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: _addNewAchievementDialog, icon: const Icon(Icons.add_circle, color: AppColors.green, size: 28)),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in c.achievements)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Icon(item.icon, color: AppColors.green, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${item.category} • ${item.date}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white24, size: 16),
                    onPressed: () => c.removeAchievement(item.id),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
