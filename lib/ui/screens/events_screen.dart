import 'package:flutter/material.dart';

import '../../core/life_events.dart';
import '../../core/currency.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/life_event.dart';
import '../../state/app_controller.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/event_dialog.dart';
import '../widgets/process_ui.dart';
import '../widgets/toast.dart';

/// Журнал событий жизни: факты по измерениям BODY / MIND / MATERIAL, их ресурсы и версии.
/// С [processId] — экран процесса: шапка процесса и только его события.
/// С [goalId] — события цели (напрямую и через её процессы).
class EventsScreen extends StatefulWidget {
  final AppController controller;
  final String? processId;
  final String? goalId;
  const EventsScreen({super.key, required this.controller, this.processId, this.goalId});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  AppController get c => widget.controller;

  String? _dimension; // null — все измерения
  int _shown = 50;

  Future<void> _add() async {
    if (c.eventsFull) {
      showToast(context, 'Журнал событий заполнен — новые события не принимаются');
      return;
    }
    final d = await showEventDialog(
      context,
      now: c.now,
      goals: c.goals,
      processes: c.processes,
      presetDimension: _dimension,
      presetProcessId: widget.processId,
      presetGoalId: widget.goalId,
    );
    if (d == null || !mounted) return;
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

  Future<void> _revise(LifeEvent e) async {
    final d = await showEventDialog(context, now: c.now, goals: c.goals, processes: c.processes, initial: e);
    if (d == null || !mounted) return;
    final id = c.reviseEvent(
      e.id,
      title: d.title,
      dimensions: d.dimensions,
      kind: d.kind,
      at: d.at,
      note: d.note,
      cost: d.cost,
      goalIds: d.goalIds,
      processIds: d.processIds,
    );
    showToast(context, id == null ? 'Не удалось сохранить новую версию' : 'Сохранена новая версия');
  }

  void _repeat(LifeEvent e) {
    final id = c.repeatEvent(e.id);
    showToast(context, id == null ? 'Не удалось повторить событие' : 'Записано такое же событие сегодня');
  }

  void _void(LifeEvent e) {
    if (!c.voidEvent(e.id)) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Событие отменено и осталось в истории'),
      action: SnackBarAction(label: 'Вернуть', onPressed: () => c.unvoidEvent(e.id)),
    ));
  }

  Future<void> _purge(LifeEvent e) async {
    final versions = c.eventRevisions(e.id).length;
    final ok = await confirmDialog(
      context,
      title: 'Удалить навсегда?',
      message: 'Событие «${e.title}»${versions > 1 ? ' и все его версии ($versions)' : ''} будет удалено без возможности '
          'восстановления. Чтобы просто убрать его из текущей картины, используйте «Отменить».',
      confirmLabel: 'Удалить',
      danger: true,
    );
    if (ok && mounted) c.purgeEvent(e.id);
  }

  void _showHistory(LifeEvent e) {
    final chain = c.eventRevisions(e.id);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('История версий', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (var i = 0; i < chain.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${i + 1}. ${chain[i].title}', style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    'событие: ${_fmt(chain[i].at)} · записано: ${_fmt(chain[i].recordedAt)}'
                    '${chain[i].isVoided ? ' · отменено ${_fmt(chain[i].voidedAt!)}' : ''}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
      ),
    );
  }

  static String _fmt(DateTime d) => '${dayKey(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Text(
            widget.processId != null
                ? (c.processById(widget.processId!)?.title ?? 'Процесс')
                : widget.goalId != null
                    ? (c.goals.where((g) => g.id == widget.goalId).firstOrNull?.title ?? 'Цель')
                    : 'События',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
        ),
        backgroundColor: AppColors.panel,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('add_event'),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Событие', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _add,
      ),
      body: ListenableBuilder(listenable: c, builder: (context, _) => _content()),
    );
  }

  Widget _content() {
    final pid = widget.processId;
    final process = pid == null ? null : c.processById(pid);
    final gid = widget.goalId;
    final source = gid == null ? c.events : c.eventsForGoal(gid);
    final all = source.reversed
        .where((e) => (_dimension == null || e.touches(_dimension!)) && (pid == null || e.processIds.contains(pid)))
        .toList();
    final now = c.now;
    final week = summarizeResources(
      source,
      from: now.subtract(const Duration(days: 7)),
      to: now.add(const Duration(minutes: 6)),
      dimension: _dimension,
      processId: pid,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        if (process != null) ...[ProcessHeader(controller: c, process: process), const SizedBox(height: 12)],
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(label: const Text('Все'), selected: _dimension == null, onSelected: (_) => setState(() => _dimension = null)),
            for (final d in LifeDimension.all)
              ChoiceChip(
                label: Text(LifeDimension.labels[d]!),
                selected: _dimension == d,
                selectedColor: dimensionColor(d).withValues(alpha: 0.3),
                onSelected: (_) => setState(() => _dimension = d),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _WeekCard(summary: week),
        const SizedBox(height: 12),
        if (all.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'Событий пока нет. Фиксируйте то, что происходит: тренировку, занятие, покупку, решение — '
              'так складывается объективная история вашего пути.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
        for (final e in all.take(_shown)) _EventTile(event: e, controller: c, onRevise: _revise, onVoid: _void, onPurge: _purge, onHistory: _showHistory, onRepeat: _repeat),
        if (all.length > _shown)
          TextButton(onPressed: () => setState(() => _shown += 50), child: Text('Показать ещё (${all.length - _shown})')),
      ],
    );
  }
}

class _WeekCard extends StatelessWidget {
  final ResourceSummary summary;
  const _WeekCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: tileDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ЗА 7 ДНЕЙ: ${summary.events} событий', style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.bold)),
          if (summary.events > 0) ...[
            const SizedBox(height: 6),
            for (final line in resourceLines(summary)) Text(line, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final LifeEvent event;
  final AppController controller;
  final void Function(LifeEvent) onRevise;
  final void Function(LifeEvent) onVoid;
  final void Function(LifeEvent) onPurge;
  final void Function(LifeEvent) onHistory;
  final void Function(LifeEvent) onRepeat;
  const _EventTile({
    required this.event,
    required this.controller,
    required this.onRevise,
    required this.onVoid,
    required this.onPurge,
    required this.onHistory,
    required this.onRepeat,
  });

  @override
  Widget build(BuildContext context) {
    final e = event;
    final goalTitles = {for (final g in controller.goals) g.id: g.title};
    final processTitles = {for (final p in controller.processes) p.id: p.title};
    final versions = e.supersedesId == null ? 1 : controller.eventRevisions(e.id).length;
    final cost = [
      if (e.cost.minutes != null) '${e.cost.minutes} мин',
      if (e.cost.money != null) '${fmtCur(e.cost.money!)}',
      if (e.cost.energy != null) 'энергия ${e.cost.energy}/5',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: tileDecoration(radius: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [for (final d in e.dimensions) Container(width: 6, height: 14, margin: const EdgeInsets.only(bottom: 2), color: dimensionColor(d))],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  '${LifeEventKind.labels[e.kind]} · ${e.dimensions.map((d) => LifeDimension.labels[d]).join(' + ')} · ${dayKey(e.at)}'
                  '${versions > 1 ? ' · версий: $versions' : ''}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                if (cost.isNotEmpty) Text(cost.join(' · '), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                if (e.goalIds.isNotEmpty)
                  Text(
                    '→ ${e.goalIds.map((id) => goalTitles[id] ?? 'цель удалена').join(', ')}',
                    style: const TextStyle(color: AppColors.violet, fontSize: 11),
                  ),
                if (e.processIds.isNotEmpty)
                  Text(
                    '⟳ ${e.processIds.map((id) => processTitles[id] ?? 'процесс удалён').join(', ')}',
                    style: const TextStyle(color: AppColors.amber, fontSize: 11),
                  ),
                if (e.note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(e.note, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.muted, size: 18),
            onSelected: (v) => switch (v) {
              'edit' => onRevise(e),
              'history' => onHistory(e),
              'repeat' => onRepeat(e),
              'void' => onVoid(e),
              _ => onPurge(e),
            },
            itemBuilder: (_) => [
              if (e.kind != LifeEventKind.review) const PopupMenuItem(value: 'repeat', child: Text('Повторить сегодня')),
              const PopupMenuItem(value: 'edit', child: Text('Исправить (новая версия)')),
              if (versions > 1) const PopupMenuItem(value: 'history', child: Text('История версий')),
              const PopupMenuItem(value: 'void', child: Text('Отменить')),
              const PopupMenuItem(value: 'purge', child: Text('Удалить навсегда', style: TextStyle(color: AppColors.red))),
            ],
          ),
        ],
      ),
    );
  }
}
