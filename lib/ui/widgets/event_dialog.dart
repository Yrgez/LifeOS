import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/currency.dart';
import '../../core/utils.dart';
import '../../models/life_event.dart';
import '../../models/life_process.dart';
import '../../models/models.dart';

Color dimensionColor(String d) => switch (d) {
      LifeDimension.body => AppColors.green,
      LifeDimension.mind => AppColors.violet,
      _ => AppColors.gold,
    };

/// Заливка столбиков графиков по измерению: приглушённые шаги тех же оттенков
/// (яркие [dimensionColor] на тёмной поверхности выходят из полосы светлоты; проверено валидатором палитры).
Color dimensionChartColor(String d) => switch (d) {
      LifeDimension.body => const Color(0xFF00A653),
      LifeDimension.mind => const Color(0xFF8B63FF),
      _ => const Color(0xFFB08A00),
    };

/// Что ввёл пользователь в диалоге события.
class EventDraft {
  final String title;
  final Set<String> dimensions;
  final String kind;
  final DateTime at;
  final String note;
  final ResourceCost cost;
  final Set<String> goalIds;
  final Set<String> processIds;
  const EventDraft({
    required this.title,
    required this.dimensions,
    required this.kind,
    required this.at,
    required this.note,
    required this.cost,
    required this.goalIds,
    required this.processIds,
  });
}

/// Диалог «Зафиксировать событие» / «Новая версия». [initial] — правка существующего события.
Future<EventDraft?> showEventDialog(
  BuildContext context, {
  required DateTime now,
  required List<GlobalGoal> goals,
  List<LifeProcess> processes = const [],
  LifeEvent? initial,
  String? presetDimension,
  String? presetProcessId,
  String? presetGoalId,
}) {
  // нижняя панель во всю высоту содержимого (как в макете), клавиатура её поднимает
  return showModalBottomSheet<EventDraft>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EventDialog(
      now: now,
      goals: goals,
      processes: processes,
      initial: initial,
      presetDimension: presetDimension,
      presetProcessId: presetProcessId,
      presetGoalId: presetGoalId,
    ),
  );
}

class _EventDialog extends StatefulWidget {
  final DateTime now;
  final List<GlobalGoal> goals;
  final List<LifeProcess> processes;
  final LifeEvent? initial;
  final String? presetDimension;
  final String? presetProcessId;
  final String? presetGoalId;
  const _EventDialog({
    required this.now,
    required this.goals,
    required this.processes,
    this.initial,
    this.presetDimension,
    this.presetProcessId,
    this.presetGoalId,
  });

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _minutes;
  late final TextEditingController _money;
  late Set<String> _dims;
  late String _kind;
  late DateTime _at;
  int? _energy;
  String? _attention;
  late Set<String> _goals;
  late Set<String> _procs;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _title = TextEditingController(text: e?.title ?? '');
    _note = TextEditingController(text: e?.note ?? '');
    int? presetMinutes;
    for (final p in widget.processes) {
      if (p.id == widget.presetProcessId) presetMinutes = p.defaultMinutes;
    }
    _minutes = TextEditingController(text: (e?.cost.minutes ?? (e == null ? presetMinutes : null))?.toString() ?? '');
    _money = TextEditingController(text: e?.cost.money?.toString() ?? '');
    _dims = e != null ? e.dimensions.toSet() : {if (widget.presetDimension != null) widget.presetDimension!};
    _kind = e?.kind ?? LifeEventKind.action;
    _at = e?.at ?? widget.now;
    _energy = e?.cost.energy;
    _attention = e?.cost.attention;
    _goals = e?.goalIds.toSet() ?? {if (widget.presetGoalId != null) widget.presetGoalId!};
    _procs = e?.processIds.toSet() ?? {if (widget.presetProcessId != null) widget.presetProcessId!};
    // событие в процессе по умолчанию относится к его измерениям
    if (e == null && widget.presetProcessId != null) {
      for (final p in widget.processes) {
        if (p.id == widget.presetProcessId) _dims.addAll(p.dimensions);
      }
    }
  }

  // выбирать можно открытые процессы; уже связанные закрытые остаются видны, чтобы связь можно было снять
  List<LifeProcess> get _processOptions => [
        for (final p in widget.processes)
          if (p.isOpen || _procs.contains(p.id)) p
      ];

  @override
  void dispose() {
    for (final c in [_title, _note, _minutes, _money]) {
      c.dispose();
    }
    super.dispose();
  }

  // пусто — «не указано»; иначе неотрицательное целое
  int? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : parseInt(c.text);
  bool _optOk(TextEditingController c) => c.text.trim().isEmpty || (parseInt(c.text) ?? -1) >= 0;

  bool get _valid =>
      _title.text.trim().isNotEmpty &&
      _dims.isNotEmpty &&
      _optOk(_minutes) &&
      _optOk(_money) &&
      (_opt(_minutes) ?? 0) <= ResourceCost.maxMinutes &&
      !_at.isAfter(widget.now.add(const Duration(minutes: 5)));

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(1900),
      lastDate: widget.now,
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (!mounted) return;
    var at = DateTime(d.year, d.month, d.day, t?.hour ?? _at.hour, t?.minute ?? _at.minute);
    if (at.isAfter(widget.now)) at = widget.now;
    setState(() => _at = at);
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.field,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(t, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
      );

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    editing ? 'Новая версия события' : 'Новое событие',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.4),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(backgroundColor: AppColors.raised, side: const BorderSide(color: AppColors.border)),
                  icon: const Icon(Icons.close, size: 18, color: Color(0xFFC8C8CC)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (editing)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('Прежняя версия останется в истории.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
              ),
            TextField(
              key: const ValueKey('event_title'),
              controller: _title,
              maxLength: LifeEvent.maxTitle,
              decoration: _dec('Что произошло?'),
              onChanged: (_) => setState(() {}),
            ),
            _label('ИЗМЕРЕНИЯ'),
            Wrap(
              spacing: 8,
              children: [
                for (final d in LifeDimension.all)
                  FilterChip(
                    key: ValueKey('dim_$d'),
                    label: Text(LifeDimension.labels[d]!),
                    selected: _dims.contains(d),
                    selectedColor: dimensionColor(d).withValues(alpha: 0.3),
                    onSelected: (v) => setState(() => v ? _dims.add(d) : _dims.remove(d)),
                  ),
              ],
            ),
            _label('ВИД'),
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: _dec('Вид события'),
              items: [
                // «обзор» создаётся только экраном обзора недели
                  for (final e in LifeEventKind.labels.entries)
                    if (e.key != LifeEventKind.review || _kind == LifeEventKind.review) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _kind = v ?? _kind),
            ),
            _label('КОГДА'),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event, size: 16),
              label: Text('${dayKey(_at)} ${_at.hour.toString().padLeft(2, '0')}:${_at.minute.toString().padLeft(2, '0')}'),
            ),
            _label('РЕСУРСЫ (НЕОБЯЗАТЕЛЬНО)'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    decoration: _dec('Время, мин'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _money,
                    keyboardType: TextInputType.number,
                    decoration: _dec('Деньги, $cur'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            if (_opt(_minutes) != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final a in Attention.all)
                    ChoiceChip(
                      key: ValueKey('attention_$a'),
                      label: Text(Attention.labels[a]!),
                      selected: _attention == a,
                      onSelected: (v) => setState(() => _attention = v ? a : null),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            const Text('Энергия — ваша оценка, сколько сил ушло (1 — почти не ушло, 5 — всё)', style: TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (var i = ResourceCost.minEnergy; i <= ResourceCost.maxEnergy; i++)
                  ChoiceChip(
                    label: Text('$i'),
                    selected: _energy == i,
                    onSelected: (v) => setState(() => _energy = v ? i : null),
                  ),
              ],
            ),
            if (widget.goals.isNotEmpty) ...[
              _label('ВЕДЁТ К ЦЕЛЯМ'),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final g in widget.goals)
                    FilterChip(
                      label: Text(g.title, overflow: TextOverflow.ellipsis),
                      selected: _goals.contains(g.id),
                      onSelected: (v) => setState(() => v ? _goals.add(g.id) : _goals.remove(g.id)),
                    ),
                ],
              ),
            ],
            if (_processOptions.isNotEmpty) ...[
              _label('В ПРОЦЕССЕ'),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final p in _processOptions)
                    FilterChip(
                      key: ValueKey('proc_${p.id}'),
                      label: Text(p.title, overflow: TextOverflow.ellipsis),
                      selected: _procs.contains(p.id),
                      onSelected: (v) => setState(() => v ? _procs.add(p.id) : _procs.remove(p.id)),
                    ),
                ],
              ),
            ],
            _label('ЗАМЕТКА'),
            TextField(controller: _note, maxLines: 3, maxLength: LifeEvent.maxNote, decoration: _dec('Подробности, контекст')),
            const SizedBox(height: 20),
            ElevatedButton(
              key: const ValueKey('event_save'),
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(56), padding: const EdgeInsets.fromLTRB(24, 0, 8, 0)),
              onPressed: _valid
                  ? () => Navigator.pop(
                        context,
                        EventDraft(
                          title: _title.text.trim(),
                          dimensions: _dims,
                          kind: _kind,
                          at: _at,
                          note: _note.text.trim(),
                          cost: ResourceCost(
                            minutes: _opt(_minutes),
                            money: _opt(_money),
                            energy: _energy,
                            attention: _opt(_minutes) == null ? null : _attention),
                          // цели, удалённые после записи события, сохраняются в его истории
                          goalIds: _goals,
                          processIds: _procs,
                        ),
                      )
                  : null,
              child: Row(
                children: [
                  Expanded(child: Text(editing ? 'Сохранить версию' : 'Зафиксировать', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: _valid ? Colors.black : Colors.black26, shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_forward, size: 18, color: AppColors.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
