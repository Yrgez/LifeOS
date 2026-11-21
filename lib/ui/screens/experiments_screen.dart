import 'package:flutter/material.dart';

import '../../core/chart_text.dart';
import '../../core/experiments.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/day_checkin.dart';
import '../../models/experiment.dart';
import '../../models/life_process.dart';
import '../../state/app_controller.dart';
import '../widgets/body_metrics.dart' show fmtKg;
import '../widgets/chart_semantics.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/process_ui.dart';
import '../widgets/toast.dart';

/// Эксперименты: «что будет, если я поменяю X» — период до и период после рядом, без вердиктов.
class ExperimentsScreen extends StatelessWidget {
  final AppController controller;
  const ExperimentsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Эксперименты'), backgroundColor: AppColors.panel, elevation: 0),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey('add_experiment'),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        tooltip: 'Новый эксперимент',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NewExperimentScreen(controller: c))),
        child: const Icon(Icons.add),
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final list = c.experiments;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              const Text(
                'Поменяйте что-то одно и посмотрите, что стало с показателем: период «до» и «после» рядом. '
                'Это наблюдение, а не доказательство — выводы делаете вы.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Text('Экспериментов пока нет', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                ),
              for (final x in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppColors.card,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.tile), side: const BorderSide(color: AppColors.border)),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      key: ValueKey('exp_${x.id}'),
                      title: Text(x.title),
                      subtitle: Text('${ExperimentMetric.labels[x.metric]} · ${experimentStage(x, c.now)}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExperimentScreen(controller: c, id: x.id))),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// «Начнётся 12.11», «день 3 из 14», «завершён 20.11».
String experimentStage(Experiment x, DateTime now) {
  if (now.isBefore(x.startedAt)) return 'начнётся ${fmtDate(x.startedAt)}';
  if (x.isFinished(now)) return 'завершён ${fmtDate(x.end.subtract(const Duration(hours: 12)))}';
  final day = DateTime(now.year, now.month, now.day).difference(x.startedAt).inHours ~/ 24 + 1;
  return 'день ${day.clamp(1, x.days)} из ${x.days}';
}

String fmtExperimentValue(String metric, num v) => switch (metric) {
      ExperimentMetric.steps => fmtMoney(v.round()),
      ExperimentMetric.sleep => fmtMinutes(v.round()),
      ExperimentMetric.protein => '${v.round()} г',
      ExperimentMetric.calories => '${v.round()} ккал',
      ExperimentMetric.weight => fmtKg(v.toDouble()),
      _ => trimNum(v.toDouble()),
    };

// ---------------- создание ----------------

class NewExperimentScreen extends StatefulWidget {
  final AppController controller;
  const NewExperimentScreen({super.key, required this.controller});

  @override
  State<NewExperimentScreen> createState() => _NewExperimentScreenState();
}

class _NewExperimentScreenState extends State<NewExperimentScreen> {
  final _title = TextEditingController();
  final _hypothesis = TextEditingController();
  String _metric = ExperimentMetric.sleep;
  String? _processId;
  int _days = 14;
  late DateTime _start;

  @override
  void initState() {
    super.initState();
    final n = widget.controller.now;
    _start = DateTime(n.year, n.month, n.day);
  }

  @override
  void dispose() {
    _title.dispose();
    _hypothesis.dispose();
    super.dispose();
  }

  bool get _ok => _title.text.trim().isNotEmpty && (_metric != ExperimentMetric.process || _processId != null);

  Future<void> _pickStart() async {
    final n = widget.controller.now;
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(n.year, n.month, n.day - Experiment.maxDays),
      lastDate: DateTime(n.year, n.month, n.day + 30),
    );
    if (d != null) setState(() => _start = d);
  }

  void _save() {
    final id = widget.controller.addExperiment(
      title: _title.text,
      hypothesis: _hypothesis.text,
      metric: _metric,
      processId: _processId,
      startedAt: _start,
      days: _days,
    );
    if (id == null) {
      showToast(context, 'Эксперимент не сохранён: проверьте данные');
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final processes = [for (final p in widget.controller.processes) if (p.status != ProcessStatus.stopped) p];
    return Scaffold(
      appBar: AppBar(title: const Text('Новый эксперимент'), backgroundColor: AppColors.panel, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            key: const ValueKey('exp_title'),
            controller: _title,
            maxLength: Experiment.maxText,
            decoration: const InputDecoration(labelText: 'Что меняю', hintText: 'Без экрана после 22:00'),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            key: const ValueKey('exp_hypothesis'),
            controller: _hypothesis,
            maxLength: Experiment.maxText,
            decoration: const InputDecoration(labelText: 'Чего жду (необязательно)', hintText: 'Буду спать дольше'),
          ),
          const SizedBox(height: 8),
          const Text('ЗА ЧЕМ СЛЕДИТЬ', style: AppText.caption),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final m in ExperimentMetric.all)
                ChoiceChip(
                  key: ValueKey('metric_$m'),
                  label: Text(ExperimentMetric.labels[m]!),
                  selected: _metric == m,
                  onSelected: (_) => setState(() => _metric = m),
                ),
            ],
          ),
          if (_metric == ExperimentMetric.process) ...[
            const SizedBox(height: 8),
            if (processes.isEmpty)
              const Text('Процессов пока нет', style: TextStyle(color: AppColors.muted, fontSize: 13))
            else
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final p in processes)
                    ChoiceChip(label: Text(p.title), selected: _processId == p.id, onSelected: (_) => setState(() => _processId = p.id)),
                ],
              ),
          ],
          const SizedBox(height: 16),
          const Text('СРОКИ', style: AppText.caption),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickStart,
                  icon: const Icon(Icons.event, size: 16),
                  label: Text('Начало ${fmtDate(_start)}'),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _days,
                items: [for (final d in const [7, 14, 21, 30, 60, 90]) DropdownMenuItem(value: d, child: Text('$d дн.'))],
                onChanged: (v) => setState(() => _days = v ?? _days),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Сравнение: $_days дней до ${fmtDate(_start)} и $_days дней с этой даты. '
            'Показатель и даты потом не меняются — так сравнение нельзя незаметно подогнать.',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('exp_save'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black),
            onPressed: _ok ? _save : null,
            child: const Text('Начать'),
          ),
        ],
      ),
    );
  }
}


// ---------------- карточка эксперимента ----------------

class ExperimentScreen extends StatefulWidget {
  final AppController controller;
  final String id;
  const ExperimentScreen({super.key, required this.controller, required this.id});

  @override
  State<ExperimentScreen> createState() => _ExperimentScreenState();
}

class _ExperimentScreenState extends State<ExperimentScreen> {
  AppController get c => widget.controller;
  late final TextEditingController _conclusion = TextEditingController(text: c.experimentById(widget.id)?.conclusion ?? '');

  @override
  void dispose() {
    _conclusion.dispose();
    super.dispose();
  }

  Future<void> _remove() async {
    final ok = await confirmDialog(context,
        title: 'Удалить эксперимент?', message: 'Данные показателя останутся в журналах — удаляется только сам эксперимент.', confirmLabel: 'Удалить', danger: true);
    if (!ok || !mounted) return;
    c.removeExperiment(widget.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final x = c.experimentById(widget.id);
        if (x == null) return const Scaffold(body: SizedBox.shrink());
        final r = c.experimentResultOf(x);
        final now = c.now;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Эксперимент'),
            backgroundColor: AppColors.panel,
            elevation: 0,
            actions: [IconButton(tooltip: 'Удалить', icon: const Icon(Icons.delete_outline), onPressed: _remove)],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(x.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              if (x.hypothesis.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Ожидание: ${x.hypothesis}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ],
              const SizedBox(height: 4),
              Text(
                '${ExperimentMetric.labels[x.metric]}'
                '${x.processId == null ? '' : ' «${c.processById(x.processId!)?.title ?? 'процесс удалён'}»'} · ${experimentStage(x, now)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _comparison(x, r),
              const SizedBox(height: 16),
              const Text('ВАШ ВЫВОД', style: AppText.caption),
              TextField(
                key: const ValueKey('exp_conclusion'),
                controller: _conclusion,
                maxLines: null,
                maxLength: 2000,
                decoration: const InputDecoration(hintText: 'Что заметили? Продолжите, бросите, поменяете?'),
              ),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  TextButton(
                    key: const ValueKey('exp_save_conclusion'),
                    onPressed: () {
                      if (c.updateExperimentText(x.id, conclusion: _conclusion.text)) showToast(context, 'Вывод сохранён');
                    },
                    child: const Text('Сохранить вывод'),
                  ),
                  if (!x.isFinished(now) && !now.isBefore(x.startedAt))
                    TextButton(key: const ValueKey('exp_end'), onPressed: () => c.endExperiment(x.id), child: const Text('Завершить сегодня')),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _comparison(Experiment x, ExperimentResult r) {
    final sides = [('ДО', r.before), if (r.after != null) ('ПОСЛЕ', r.after!)];
    final daily = ExperimentMetric.isDaily(x.metric);
    final thin = (daily && sides.any((s) => s.$2.values.length < kExperimentMinDays)) ||
        (x.metric == ExperimentMetric.dayRating && sides.any((s) => s.$2.ratedDays < kExperimentMinDays));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: tileDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, s) in sides.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: _side(x, s.$1, s.$2)),
              ],
              if (r.after == null) ...[
                const SizedBox(width: 12),
                Expanded(child: Text('ПОСЛЕ\nначнётся ${fmtDate(x.startedAt)}', style: const TextStyle(color: AppColors.muted, fontSize: 13))),
              ],
            ],
          ),
          if (daily && sides.any((s) => s.$2.values.isNotEmpty)) ...[
            const SizedBox(height: 12),
            ChartSemantics(
              label: 'Значения по дням. ${[for (final s in sides) '${s.$1}: ${describeSeries(s.$2.values)}'].join('. ')}',
              child: SizedBox(
                height: 18.0 * sides.length + 8,
                child: CustomPaint(painter: _StripPainter([for (final s in sides) s.$2.values])),
              ),
            ),
            const Text('Каждая точка — один день с данными', style: TextStyle(color: AppColors.muted, fontSize: 11)),
          ],
          if (thin) ...[
            const SizedBox(height: 8),
            const Text(
              'Меньше $kExperimentMinDays дней с данными в периоде — по таким числам сравнивать рано.',
              style: TextStyle(color: AppColors.text, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _side(Experiment x, String label, ExperimentSide s) {
    const muted = TextStyle(color: AppColors.muted, fontSize: 13);
    final range = '${fmtDate(s.from)} – ${fmtDate(s.to.subtract(const Duration(hours: 12)))}';
    if (ExperimentMetric.isDaily(x.metric)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption),
          Text(range, style: muted),
          const SizedBox(height: 6),
          Text(s.median == null ? '—' : fmtExperimentValue(x.metric, s.median!), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const Text('медиана по дням', style: muted),
          if (s.min != null && s.min != s.max) Text('от ${fmtExperimentValue(x.metric, s.min!)} до ${fmtExperimentValue(x.metric, s.max!)}', style: muted),
          Text('дней с данными: ${s.values.length} из ${s.days}', style: muted),
        ],
      );
    }
    if (x.metric == ExperimentMetric.dayRating) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption),
          Text(range, style: muted),
          const SizedBox(height: 6),
          Text(s.ratedDays == 0 ? '—' : ratingDistribution(s.ratings!), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Text('дней с оценкой: ${s.ratedDays} из ${s.days}', style: muted),
        ],
      );
    }
    final e = s.events!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption),
        Text(range, style: muted),
        const SizedBox(height: 6),
        if (x.metric == ExperimentMetric.energy) ...[
          Text(e.energyKnown == 0 ? '—' : [for (var i = 1; i <= 5; i++) if (e.energy[i] != null) '$i×${e.energy[i]}'].join('  '),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Text('оценок: ${e.energyKnown} из ${e.events} событий', style: muted),
        ] else ...[
          Text('${e.events} событий', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          Text('дней с событиями: ${s.daysWithEvents} из ${s.days}', style: muted),
          if (e.minutesKnown > 0) Text('время ${fmtMinutes(e.minutes)}${e.minutesKnown == e.events ? '' : ' (указано в ${e.minutesKnown})'}', style: muted),
        ],
      ],
    );
  }
}

/// Точки значений по дням: строка на период, общая шкала. Подписи — в тексте выше.
class _StripPainter extends CustomPainter {
  final List<List<num>> rows;
  _StripPainter(this.rows);

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final r in rows) ...r];
    if (all.isEmpty) return;
    final lo = all.reduce((a, b) => a < b ? a : b).toDouble(), hi = all.reduce((a, b) => a > b ? a : b).toDouble();
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    final line = Paint()..color = AppColors.border;
    for (var i = 0; i < rows.length; i++) {
      final y = 9.0 + i * 18;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      final dot = Paint()..color = (i == 0 ? AppColors.muted : AppColors.text).withValues(alpha: 0.75);
      for (final v in rows[i]) {
        canvas.drawCircle(Offset(4 + (v - lo) / span * (size.width - 8), y), 3.5, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) => old.rows != rows;
}
