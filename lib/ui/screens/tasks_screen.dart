import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/life_task.dart';
import '../../state/app_controller.dart';
import '../widgets/task_ui.dart';

/// Все задачи: на сегодня (с невыполненными с прошлых дней), дальше по дням, без даты, сделанные за неделю.
class TasksScreen extends StatelessWidget {
  final AppController controller;
  const TasksScreen({super.key, required this.controller});

  AppController get c => controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Задачи'), backgroundColor: AppColors.panel, elevation: 0),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('add_task'),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        tooltip: 'Новая задача',
        onPressed: () => showTaskSheet(context, c),
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final now = c.now;
          final today = c.tasksForToday;
          final upcoming = c.tasksUpcoming;
          final someday = c.tasksSomeday;
          final done = c.tasksDoneRecently();
          final byDay = <String, List<LifeTask>>{};
          for (final t in upcoming) {
            (byDay[t.day!] ??= []).add(t);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              const Text(
                'Задача — намерение. «Сделано» записывает событие в журнал: с него считаются время, процессы и цели.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              _Group(title: 'СЕГОДНЯ', empty: 'На сегодня задач нет', children: [for (final t in today) TaskRow(controller: c, task: t)]),
              for (final e in byDay.entries)
                _Group(title: taskDayLabel(e.key, now).toUpperCase(), children: [for (final t in e.value) TaskRow(controller: c, task: t, showDay: false)]),
              if (someday.isNotEmpty) _Group(title: 'БЕЗ ДАТЫ', children: [for (final t in someday) TaskRow(controller: c, task: t, showDay: false)]),
              if (done.isNotEmpty)
                _Group(
                  title: 'СДЕЛАНО ЗА НЕДЕЛЮ',
                  children: [
                    for (final t in done)
                      Row(
                        key: ValueKey('done_${t.id}'),
                        children: [
                          const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.check_circle_outline, color: AppColors.muted)),
                          Expanded(
                            child: Text('${t.title} · ${shortDate(t.doneChange!.at)}',
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                          ),
                          TextButton(onPressed: () => c.reopenTask(t.id), child: const Text('Вернуть')),
                        ],
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String? empty;
  const _Group({required this.title, required this.children, this.empty});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: tileDecoration(radius: AppRadii.card),
              child: children.isEmpty && empty != null
                  ? Padding(padding: const EdgeInsets.all(14), child: Text(empty!, style: const TextStyle(color: AppColors.muted, fontSize: 13)))
                  : Column(children: children),
            ),
          ],
        ),
      );
}

