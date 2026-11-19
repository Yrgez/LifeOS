import 'package:flutter/material.dart';

import '../../core/life_events.dart';
import '../../core/currency.dart';
import '../../core/rhythm.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/life_event.dart';
import '../../models/life_process.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import 'adaptive_pair.dart';
import 'confirm_dialog.dart';
import 'event_dialog.dart';

// ---------------- общий текст ресурсов ----------------

String fmtMinutes(int m) => m < 60 ? '$m мин' : '${m ~/ 60} ч${m % 60 == 0 ? '' : ' ${m % 60} мин'}';

/// Строки сводки ресурсов: честно показывает, где значения не указаны.
List<String> resourceLines(ResourceSummary s) {
  String part(int known, String value) => known == 0 ? 'не указано' : known == s.events ? value : '$value (указано в $known из ${s.events})';
  return [
    'Время: ${part(s.minutesKnown, fmtMinutes(s.minutes))}',
    'Деньги: ${part(s.moneyKnown, '${fmtCur(s.money)}')}',
    'Энергия: ${s.energyKnown == 0 ? 'не указано' : [for (var i = 1; i <= 5; i++) if (s.energy[i] != null) '$i×${s.energy[i]}'].join(', ')}',
    // внимание показываем, только если его отмечали: пустая строка «не указано» здесь — шум
    if (s.attentionKnown > 0)
      'Внимание: в фокусе ${fmtMinutes(s.focusedMinutes)} · урывками ${fmtMinutes(s.scatteredMinutes)}'
          '${s.attentionKnown == s.minutesKnown ? '' : ' (отмечено в ${s.attentionKnown} из ${s.minutesKnown} со временем)'}',
  ];
}

Color processStatusColor(String s) => switch (s) {
      ProcessStatus.active => AppColors.green,
      ProcessStatus.paused => AppColors.amber,
      ProcessStatus.completed => AppColors.violet,
      _ => AppColors.muted,
    };

// ---------------- диалог процесса ----------------

class ProcessDraft {
  final String title;
  final Set<String> dimensions;
  final String description;
  final Set<String> goalIds;
  final DateTime startedAt;
  final int? defaultMinutes;
  final int rhythmTimes; // 0 — ритм не задан
  final String rhythmPeriod;
  const ProcessDraft({
    required this.title,
    required this.dimensions,
    required this.description,
    required this.goalIds,
    required this.startedAt,
    this.defaultMinutes,
    this.rhythmTimes = 0,
    this.rhythmPeriod = RhythmPeriod.week,
  });

  ProcessRhythm? get rhythm => rhythmTimes > 0 ? ProcessRhythm(at: startedAt, times: rhythmTimes, period: rhythmPeriod) : null;
}

/// Новый процесс или правка описания ([initial]). Дата начала задаётся только при создании.
Future<ProcessDraft?> showProcessDialog(BuildContext context, {required DateTime now, required List<GlobalGoal> goals, LifeProcess? initial}) {
  return showDialog<ProcessDraft>(context: context, builder: (_) => _ProcessDialog(now: now, goals: goals, initial: initial));
}

class _ProcessDialog extends StatefulWidget {
  final DateTime now;
  final List<GlobalGoal> goals;
  final LifeProcess? initial;
  const _ProcessDialog({required this.now, required this.goals, this.initial});

  @override
  State<_ProcessDialog> createState() => _ProcessDialogState();
}

class _ProcessDialogState extends State<_ProcessDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.initial?.title ?? '');
  late final TextEditingController _desc = TextEditingController(text: widget.initial?.description ?? '');
  late final TextEditingController _minutes = TextEditingController(text: widget.initial?.defaultMinutes?.toString() ?? '');
  late final Set<String> _dims = widget.initial?.dimensions.toSet() ?? <String>{};
  late final Set<String> _goals = widget.initial?.goalIds.toSet() ?? <String>{};
  late DateTime _start = widget.initial?.startedAt ?? widget.now;
  late int _rhythmTimes = widget.initial?.rhythm?.times ?? 0;
  late String _rhythmPeriod = widget.initial?.rhythm?.period ?? RhythmPeriod.week;

  int? get _minutesValue => _minutes.text.trim().isEmpty ? null : parseInt(_minutes.text);

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    _desc.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
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
    final minutesOk = _minutes.text.trim().isEmpty || ((parseInt(_minutes.text) ?? 0) > 0 && parseInt(_minutes.text)! <= ResourceCost.maxMinutes);
    final valid = _title.text.trim().isNotEmpty && _dims.isNotEmpty && minutesOk;
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(editing ? 'Процесс' : 'Новый процесс', style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!editing)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('Длительное направление усилий: «Изучение Java», «Набор массы», «Ремонт». '
                      'Что в него вложено, считается по событиям.', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                ),
              TextField(
                key: const ValueKey('process_title'),
                controller: _title,
                maxLength: LifeProcess.maxTitle,
                decoration: _dec('Название'),
                onChanged: (_) => setState(() {}),
              ),
              _label('ИЗМЕРЕНИЯ'),
              Wrap(
                spacing: 8,
                children: [
                  for (final d in LifeDimension.all)
                    FilterChip(
                      key: ValueKey('pdim_$d'),
                      label: Text(LifeDimension.labels[d]!),
                      selected: _dims.contains(d),
                      selectedColor: dimensionColor(d).withValues(alpha: 0.3),
                      onSelected: (v) => setState(() => v ? _dims.add(d) : _dims.remove(d)),
                    ),
                ],
              ),
              if (!editing) ...[
                _label('НАЧАЛО'),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: _start, firstDate: DateTime(1900), lastDate: widget.now);
                    if (d != null && mounted) setState(() => _start = d);
                  },
                  icon: const Icon(Icons.event, size: 16),
                  label: Text(dayKey(_start)),
                ),
              ],
              if (widget.goals.isNotEmpty) ...[
                _label('СЛУЖИТ ЦЕЛЯМ'),
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
              _label('ОПИСАНИЕ'),
              TextField(controller: _desc, maxLines: 3, maxLength: LifeProcess.maxDescription, decoration: _dec('Зачем, что считается результатом')),
              const SizedBox(height: 4),
              TextField(
                key: const ValueKey('process_minutes'),
                controller: _minutes,
                keyboardType: TextInputType.number,
                decoration: _dec('Обычная длительность события, мин (необязательно)'),
                onChanged: (_) => setState(() {}),
              ),
              _label('РИТМ (НЕОБЯЗАТЕЛЬНО)'),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  DropdownButton<int>(
                    key: const ValueKey('process_rhythm_times'),
                    isExpanded: largeText(context), // при крупном шрифте — на всю строку, иначе не помещается
                    value: _rhythmTimes.clamp(0, RhythmPeriod.maxTimes[_rhythmPeriod]!),
                    items: [
                      const DropdownMenuItem(value: 0, child: Text('не задан')),
                      for (var i = 1; i <= RhythmPeriod.maxTimes[_rhythmPeriod]!; i++) DropdownMenuItem(value: i, child: Text(timesLabel(i))),
                    ],
                    onChanged: (v) => setState(() => _rhythmTimes = v ?? 0),
                  ),
                  for (final per in RhythmPeriod.all)
                    ChoiceChip(
                      key: ValueKey('process_rhythm_$per'),
                      visualDensity: VisualDensity.compact,
                      label: Text(RhythmPeriod.labels[per]!),
                      selected: _rhythmPeriod == per,
                      onSelected: (_) => setState(() {
                        _rhythmPeriod = per;
                        _rhythmTimes = _rhythmTimes.clamp(0, RhythmPeriod.maxTimes[per]!);
                      }),
                    ),
                ],
              ),
              const Text('Раз — день с событием процесса. Пропуск не обнуляет прошлое: каждая неделя считается сама по себе.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена', style: TextStyle(color: AppColors.muted))),
        ElevatedButton(
          key: const ValueKey('process_save'),
          style: ElevatedButton.styleFrom(),
          onPressed: valid
              ? () => Navigator.pop(
                    context,
                    ProcessDraft(
                      title: _title.text.trim(),
                      dimensions: _dims,
                      description: _desc.text.trim(),
                      goalIds: _goals,
                      startedAt: _start,
                      defaultMinutes: _minutesValue,
                      rhythmTimes: _rhythmTimes,
                      rhythmPeriod: _rhythmPeriod,
                    ),
                  )
              : null,
          child: const Text('Сохранить', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ---------------- карточка в списке ----------------

class ProcessCard extends StatelessWidget {
  final LifeProcess process;
  final ProcessActivity activity;
  final VoidCallback onTap;
  const ProcessCard({super.key, required this.process, required this.activity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = process;
    final a = activity;
    final since = p.isOpen ? 'с ${dayKey(p.startedAt)}' : '${dayKey(p.startedAt)} — ${dayKey(p.endedAt!)}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: tileDecoration(radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (final d in p.dimensions) Container(width: 6, height: 14, margin: const EdgeInsets.only(right: 3), color: dimensionColor(d)),
                const SizedBox(width: 6),
                Expanded(child: Text(p.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                Text(ProcessStatus.labels[p.status]!, style: TextStyle(color: processStatusColor(p.status), fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$since · событий: ${a.resources.events}${a.lastAt == null ? '' : ' · последнее ${dayKey(a.lastAt!)}'}',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            if (a.resources.events > 0) ...[
              const SizedBox(height: 4),
              for (final line in resourceLines(a.resources).take(2)) Text(line, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------- шапка процесса ----------------

/// Шапка на экране процесса: описание, вложенные ресурсы, журнал статусов и действия.
class ProcessHeader extends StatelessWidget {
  final AppController controller;
  final LifeProcess process;
  const ProcessHeader({super.key, required this.controller, required this.process});

  Future<void> _edit(BuildContext context) async {
    final d = await showProcessDialog(context, now: controller.now, goals: controller.goals, initial: process);
    if (d == null) return;
    controller.updateProcess(process.id,
        title: d.title, dimensions: d.dimensions, description: d.description, goalIds: d.goalIds, defaultMinutes: d.defaultMinutes);
    controller.setProcessRhythm(process.id, d.rhythmTimes, period: d.rhythmPeriod);
  }

  Future<void> _status(BuildContext context, String status) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Статус: ${ProcessStatus.labels[status]}', style: const TextStyle(fontSize: 16)),
        content: TextField(
          controller: note,
          maxLength: ProcessStatusChange.maxNote,
          decoration: const InputDecoration(labelText: 'Почему (необязательно)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok == true) controller.setProcessStatus(process.id, status, note: note.text);
    note.dispose();
  }

  Future<void> _remove(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить процесс навсегда?',
      message: 'Процесс «${process.title}» и журнал его статусов будут удалены. События останутся в журнале '
          '(с пометкой «процесс удалён»). Чтобы просто закрыть процесс, выберите статус «Завершён» или «Прекращён».',
      confirmLabel: 'Удалить',
      danger: true,
    );
    if (ok && context.mounted) {
      controller.removeProcess(process.id);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = process;
    final a = controller.processActivityOf(p.id);
    final goalTitles = {for (final g in controller.goals) g.id: g.title};
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: tileDecoration(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${ProcessStatus.labels[p.status]} · ${p.dimensions.map((d) => LifeDimension.labels[d]).join(' + ')}',
                  style: TextStyle(color: processStatusColor(p.status), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              PopupMenuButton<String>(
                key: const ValueKey('process_menu'),
                icon: const Icon(Icons.more_vert, color: AppColors.muted, size: 18),
                onSelected: (v) => switch (v) {
                  'edit' => _edit(context),
                  'remove' => _remove(context),
                  _ => _status(context, v),
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Изменить описание')),
                  for (final s in ProcessStatus.all)
                    if (s != p.status) PopupMenuItem(value: s, child: Text('Статус: ${ProcessStatus.labels[s]}')),
                  const PopupMenuItem(value: 'remove', child: Text('Удалить навсегда', style: TextStyle(color: AppColors.red))),
                ],
              ),
            ],
          ),
          if (p.description.isNotEmpty) Text(p.description, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          if (p.goalIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('→ ${p.goalIds.map((id) => goalTitles[id] ?? 'цель удалена').join(', ')}', style: const TextStyle(color: AppColors.violetText, fontSize: 11)),
            ),
          if (p.rhythm != null) ...[
            const SizedBox(height: 10),
            RhythmStrip(process: p, spans: controller.rhythmOf(p.id)),
          ],
          const SizedBox(height: 8),
          Text('ВЛОЖЕНО ЗА ВСЁ ВРЕМЯ: событий ${a.resources.events}',
              style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.bold)),
          if (a.resources.events > 0)
            for (final line in resourceLines(a.resources)) Text(line, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          const Text('ЖУРНАЛ СТАТУСОВ', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.bold)),
          for (final c in p.statusLog.reversed)
            Text(
              '${dayKey(c.at)} — ${ProcessStatus.labels[c.status]}${c.note.isEmpty ? '' : ': ${c.note}'}',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

// ---------------- ритм ----------------

/// Ритм процесса: заголовок «3 раза в неделю · на этой неделе 2 из 3» и последние периоды —
/// старые слева, текущий справа. Каждый период — сам по себе: без серий и без «сгорания».
class RhythmStrip extends StatelessWidget {
  final LifeProcess process;
  final List<RhythmSpan> spans; // текущий первым
  const RhythmStrip({super.key, required this.process, required this.spans});

  static String _periodLabel(RhythmSpan s, String period) {
    if (s.current) return period == RhythmPeriod.month ? 'этот' : 'эта';
    return period == RhythmPeriod.month ? monthShortName(s.from.month) : '${s.from.day.toString().padLeft(2, '0')}.${s.from.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final r = process.rhythm;
    if (r == null || spans.isEmpty) return const SizedBox.shrink();
    final list = spans.reversed.toList();
    return Column(
      key: const ValueKey('rhythm_strip'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('РИТМ: ${rhythmLabel(r).toUpperCase()}', style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(rhythmNowLabel(r, spans.first), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final s in list)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      Container(
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: s.reached && s.active ? AppColors.raised : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: s.current ? AppColors.muted : AppColors.border),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Text(
                              !s.active ? 'пауза' : (s.target == null ? '${s.done}' : '${s.done}/${s.target}'),
                              style: TextStyle(fontSize: 12, color: s.active ? AppColors.text : AppColors.muted),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_periodLabel(s, r.period), style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
