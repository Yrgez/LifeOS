import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/life_process.dart';
import '../../security/security_service.dart';
import '../../state/app_controller.dart';
import '../widgets/health_card.dart';
import '../widgets/resources_card.dart';
import '../widgets/event_dialog.dart';
import '../widgets/process_ui.dart';
import '../widgets/toast.dart';
import 'events_screen.dart';
import 'processes_screen.dart';
import 'settings_screen.dart';

/// Вкладка «Сегодня» (PRESENT): что происходит сейчас — состояние дня, идущие процессы, ресурсы недели.
/// Отсюда же — быстрая запись события.
class HubScreen extends StatelessWidget {
  final AppController controller;
  final SecurityService security;
  const HubScreen({super.key, required this.controller, required this.security});

  AppController get c => controller;

  void _push(BuildContext context, Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _quickEvent(BuildContext context) async {
    if (c.eventsFull) {
      showToast(context, 'Журнал событий заполнен — новые события не принимаются');
      return;
    }
    final d = await showEventDialog(context, now: c.now, goals: c.goals, processes: c.processes);
    if (d == null || !context.mounted) return;
    final id = c.addEvent(
      title: d.title,
      dimensions: d.dimensions,
      kind: d.kind,
      at: d.at,
      note: d.note,
      cost: d.cost,
      goalIds: d.goalIds,
      processIds: d.processIds,
    );
    showToast(context, id == null ? 'Событие не сохранено: проверьте данные' : 'Событие зафиксировано');
  }

  @override
  Widget build(BuildContext context) {
    final now = c.now;
    final open = [for (final p in c.processes) if (p.status == ProcessStatus.active) p];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'СЕГОДНЯ · ${now.day} ${monthNames[now.month - 1].toLowerCase()}, ${dayNames[now.weekday - 1]}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 4),
                    Text(c.userName.isEmpty ? 'Life OS' : c.userName,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              // на узком экране плашка сжимается, а не выталкивает кнопки за край
              Flexible(
                child: Tooltip(
                  message: 'Оценка по типовому времени восстановления групп мышц после последней тренировки',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite, color: AppColors.green, size: 14),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Восстановлено ${c.recovery.recovered} из ${c.recovery.total}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white54),
                tooltip: 'Настройки',
                onPressed: () => _push(context, SettingsScreen(controller: c, security: security)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  key: const ValueKey('quick_event'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.black),
                  onPressed: () => _quickEvent(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Событие', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('open_events'),
                  onPressed: () => _push(context, EventsScreen(controller: c)),
                  icon: const Icon(Icons.timeline, size: 18),
                  label: const Text('События'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('open_processes'),
                  onPressed: () => _push(context, ProcessesScreen(controller: c)),
                  icon: const Icon(Icons.autorenew, size: 18),
                  label: const Text('Процессы'),
                ),
              ),
            ],
          ),
          if (open.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('ИДУТ СЕЙЧАС', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            for (final p in open.take(5))
              ProcessCard(
                key: ValueKey('today_${p.id}'),
                process: p,
                activity: c.processActivityOf(p.id),
                onTap: () => _push(context, EventsScreen(controller: c, processId: p.id)),
              ),
            if (open.length > 5)
              TextButton(onPressed: () => _push(context, ProcessesScreen(controller: c)), child: Text('Все процессы (${open.length})')),
          ],
          const SizedBox(height: 16),
          HealthCard(controller: c),
          const SizedBox(height: 16),
          ResourcesCard(controller: c),
        ],
      ),
    );
  }
}
