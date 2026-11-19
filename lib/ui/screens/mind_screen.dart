import 'package:flutter/material.dart';

import '../../core/sections.dart';
import '../../core/theme.dart';
import '../../state/app_controller.dart';
import '../widgets/adaptive_pair.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';
import '../widgets/goals_ui.dart';
import 'experiments_screen.dart';
import 'graph_screen.dart';
import 'processes_screen.dart';

/// Вкладка «Разум» (MIND): цели, достижения, вход в граф связей и процессы.
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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Разум', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -0.8)),
          const SizedBox(height: 2),
          const Text('Цели, достижения, связи', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 20),
          AdaptivePair(
            spacing: 8,
            children: [
              if (c.isShown(Sections.graph))
                OutlinedButton.icon(
                  key: const ValueKey('open_graph'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GraphScreen(controller: c))),
                  icon: const Icon(Icons.hub_outlined, size: 18),
                  label: const Text('Граф связей'),
                ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProcessesScreen(controller: c))),
                icon: const Icon(Icons.autorenew, size: 18),
                label: const Text('Процессы'),
              ),
            ],
          ),
          if (c.isShown(Sections.experiments)) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('open_experiments'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExperimentsScreen(controller: c))),
                icon: const Icon(Icons.science_outlined, size: 18),
                label: const Text('Эксперименты'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(child: Text('Цели', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              IconButton(tooltip: 'Новая цель', onPressed: _addNewGoalDialog, icon: const Icon(Icons.add_circle_outline, color: AppColors.text, size: 26)),
            ],
          ),
          const SizedBox(height: 12),
          for (final goal in c.goals) GoalCard(key: ValueKey(goal.id), controller: c, goal: goal),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(child: Text('Достижения', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              IconButton(tooltip: 'Новое достижение', onPressed: _addNewAchievementDialog, icon: const Icon(Icons.add_circle_outline, color: AppColors.text, size: 26)),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in c.achievements)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: tileDecoration(radius: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(14)),
                    child: Icon(item.icon, color: AppColors.text, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${item.category} • ${item.date}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Удалить достижение',
                    icon: const Icon(Icons.close, color: AppColors.muted, size: 16),
                    onPressed: () async {
                      final ok = await confirmDialog(context,
                          title: 'Удалить достижение?', message: '«${item.title}» будет удалено без возможности вернуть.', confirmLabel: 'Удалить', danger: true);
                      if (ok) c.removeAchievement(item.id);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
