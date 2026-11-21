import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/day_snapshot.dart' show dayFromKey;
import '../../models/life_event.dart';
import '../../models/life_process.dart';
import '../../models/life_task.dart';
import '../../state/app_controller.dart';
import 'confirm_dialog.dart';
import 'toast.dart';

/// «Сегодня», «завтра», «чт, 21 ноя» — день задачи словами.
String taskDayLabel(String? day, DateTime now) {
  if (day == null) return 'без даты';
  final today = dayKey(now);
  final tomorrow = dayKey(DateTime(now.year, now.month, now.day + 1));
  if (day == today) return 'сегодня';
  if (day == tomorrow) return 'завтра';
  return shortDate(dayFromKey(day));
}

/// Строка задачи: «Сделано» в одно нажатие, факты о дне и переносах без оценок, действия в меню.
class TaskRow extends StatelessWidget {
  final AppController controller;
  final LifeTask task;
  final bool showDay; // в группе по дню день не повторяется (кроме «с прошлого дня»)
  const TaskRow({super.key, required this.controller, required this.task, this.showDay = true});

  AppController get c => controller;

  void _done(BuildContext context) {
    final ev = c.completeTask(task.id);
    if (ev == null) {
      showToast(context, 'Не получилось отметить задачу');
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Сделано — событие записано в журнал'),
        action: SnackBarAction(label: 'Отменить', onPressed: () => c.reopenTask(task.id)),
      ));
  }

  Future<void> _menu(BuildContext context, String v) async {
    final now = c.now;
    switch (v) {
      case 'today':
        c.planTask(task.id, now);
      case 'tomorrow':
        c.planTask(task.id, DateTime(now.year, now.month, now.day + 1));
      case 'date':
        final d = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: DateTime(now.year + 5));
        if (d != null) c.planTask(task.id, d);
      case 'someday':
        c.planTask(task.id, null);
      case 'edit':
        if (context.mounted) await showTaskSheet(context, c, initial: task);
      case 'cancel':
        final ok = await confirmDialog(context,
            title: 'Отменить задачу?', message: '«${task.title}» уйдёт из списков. Задача и её история сохранятся.', confirmLabel: 'Отменить задачу');
        if (ok) c.cancelTask(task.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = c.now;
    final today = dayKey(now);
    final day = task.day;
    final link = task.processId != null ? c.processById(task.processId!)?.title : null;
    final goal = task.goalId != null ? c.goals.where((g) => g.id == task.goalId).firstOrNull?.title : null;
    final meta = [
      if (day != null && day.compareTo(today) < 0) 'назначена на ${fmtDate(dayFromKey(day))}' else if (showDay && day != today) taskDayLabel(day, now),
      if (link != null) link,
      if (goal != null) '→ $goal',
      if (task.minutes != null) '~${task.minutes} мин',
      if (task.postponed > 0) 'переносилась: ${task.postponed}',
    ];
    return InkWell(
      key: ValueKey('task_${task.id}'),
      onTap: () => showTaskSheet(context, c, initial: task),
      borderRadius: BorderRadius.circular(AppRadii.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            IconButton(
              key: ValueKey('task_done_${task.id}'),
              tooltip: 'Сделано',
              onPressed: () => _done(context),
              icon: const Icon(Icons.radio_button_unchecked, color: AppColors.muted),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
                  if (meta.isNotEmpty) Text(meta.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              key: ValueKey('task_menu_${task.id}'),
              icon: const Icon(Icons.more_vert, color: AppColors.muted, size: 20),
              onSelected: (v) => _menu(context, v),
              itemBuilder: (_) => [
                if (day != today) const PopupMenuItem(value: 'today', child: Text('На сегодня')),
                const PopupMenuItem(value: 'tomorrow', child: Text('На завтра')),
                const PopupMenuItem(value: 'date', child: Text('На дату…')),
                if (day != null) const PopupMenuItem(value: 'someday', child: Text('Без даты')),
                const PopupMenuItem(value: 'edit', child: Text('Изменить')),
                const PopupMenuItem(value: 'cancel', child: Text('Отменить задачу')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Новая задача или правка описания. День новой задачи выбирается здесь; у существующей — переносом из меню.
Future<void> showTaskSheet(BuildContext context, AppController c, {LifeTask? initial, String? presetProcessId, String? presetGoalId}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TaskSheet(controller: c, initial: initial, presetProcessId: presetProcessId, presetGoalId: presetGoalId),
  );
}

class _TaskSheet extends StatefulWidget {
  final AppController controller;
  final LifeTask? initial;
  final String? presetProcessId;
  final String? presetGoalId;
  const _TaskSheet({required this.controller, this.initial, this.presetProcessId, this.presetGoalId});

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

enum _Day { today, tomorrow, date, none }

class _TaskSheetState extends State<_TaskSheet> {
  AppController get c => widget.controller;
  late final TextEditingController _title = TextEditingController(text: widget.initial?.title ?? '');
  late final TextEditingController _note = TextEditingController(text: widget.initial?.note ?? '');
  late final TextEditingController _minutes = TextEditingController(text: widget.initial?.minutes?.toString() ?? '');
  late String? _processId = widget.initial?.processId ?? widget.presetProcessId;
  late String? _goalId = widget.initial?.goalId ?? widget.presetGoalId;
  late final Set<String> _dims = {...?widget.initial?.dimensions};
  _Day _day = _Day.today;
  DateTime? _date;

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _minutes.dispose();
    super.dispose();
  }

  int? get _min => _minutes.text.trim().isEmpty ? null : parseInt(_minutes.text);
  bool get _minOk => _minutes.text.trim().isEmpty || ((_min ?? 0) > 0 && _min! <= ResourceCost.maxMinutes);

  /// Измерения можно не выбирать, если есть процесс или цель — возьмутся от них.
  bool get _ok => _title.text.trim().isNotEmpty && _minOk && (_dims.isNotEmpty || _processId != null || _goalId != null);

  DateTime? get _pickedDay {
    final n = c.now;
    return switch (_day) {
      _Day.today => n,
      _Day.tomorrow => DateTime(n.year, n.month, n.day + 1),
      _Day.date => _date,
      _Day.none => null,
    };
  }

  void _save() {
    final dims = _dims.isNotEmpty
        ? _dims
        : _processId != null
            ? c.processById(_processId!)?.dimensions ?? const <String>[]
            : c.goalFactOf(_goalId!).dimensions;
    final ok = widget.initial == null
        ? c.addTask(title: _title.text, dimensions: dims, day: _pickedDay, processId: _processId, goalId: _goalId, minutes: _min, note: _note.text) != null
        : c.updateTask(widget.initial!.id, title: _title.text, dimensions: dims, note: _note.text, processId: _processId, goalId: _goalId, minutes: _min);
    if (!ok) {
      showToast(context, 'Задача не сохранена: проверьте данные');
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final processes = [for (final p in c.processes) if (p.isOpen || p.id == _processId) p];
    final editing = widget.initial != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(editing ? 'Задача' : 'Новая задача', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('task_title'),
              controller: _title,
              autofocus: !editing,
              maxLength: LifeTask.maxTitle,
              decoration: const InputDecoration(hintText: 'Что сделать', counterText: ''),
              onChanged: (_) => setState(() {}),
            ),
            if (!editing) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final (d, label) in [(_Day.today, 'Сегодня'), (_Day.tomorrow, 'Завтра'), (_Day.none, 'Без даты')])
                    ChoiceChip(key: ValueKey('task_day_${d.name}'), label: Text(label), selected: _day == d, onSelected: (_) => setState(() => _day = d)),
                  ChoiceChip(
                    label: Text(_day == _Day.date && _date != null ? fmtDate(_date!) : 'Дата…'),
                    selected: _day == _Day.date,
                    onSelected: (_) async {
                      final n = c.now;
                      final d = await showDatePicker(context: context, initialDate: n, firstDate: n, lastDate: DateTime(n.year + 5));
                      if (d != null) {
                        setState(() {
                          _day = _Day.date;
                          _date = d;
                        });
                      }
                    },
                  ),
                ],
              ),
            ],
            if (processes.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButton<String?>(
                isExpanded: true,
                value: _processId,
                hint: const Text('Процесс (необязательно)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Без процесса')),
                  for (final LifeProcess p in processes) DropdownMenuItem<String?>(value: p.id, child: Text(p.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _processId = v),
              ),
            ],
            if (c.goals.isNotEmpty)
              DropdownButton<String?>(
                isExpanded: true,
                value: c.goals.any((g) => g.id == _goalId) ? _goalId : null,
                hint: const Text('Цель (необязательно)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Без цели')),
                  for (final g in c.goals) DropdownMenuItem<String?>(value: g.id, child: Text(g.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _goalId = v),
              ),
            const SizedBox(height: 8),
            Text(_processId != null || _goalId != null ? 'Измерения (по умолчанию — от процесса или цели)' : 'Измерения',
                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            Wrap(
              spacing: 6,
              children: [
                for (final d in LifeDimension.all)
                  FilterChip(
                    key: ValueKey('task_dim_$d'),
                    label: Text(LifeDimension.labels[d]!),
                    selected: _dims.contains(d),
                    onSelected: (v) => setState(() => v ? _dims.add(d) : _dims.remove(d)),
                  ),
              ],
            ),
            TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Примерно минут (необязательно)'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _note,
              maxLines: 3,
              minLines: 1,
              maxLength: LifeTask.maxNote,
              decoration: const InputDecoration(hintText: 'Заметка (необязательно)', counterText: ''),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('task_save'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
              onPressed: _ok ? _save : null,
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
}
