import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/workout_stats.dart';
import '../../models/models.dart';
import '../../state/app_controller.dart';
import '../painters/chart_painters.dart';
import '../widgets/log_set_dialog.dart';

/// Журнал тренировок: история подходов, прогрессия и объём нагрузки.
/// Без упражнений, шаблонов и таймеров — только то, что нужно для отслеживания прогресса.
class JournalScreen extends StatefulWidget {
  final AppController controller;
  const JournalScreen({super.key, required this.controller});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  AppController get c => widget.controller;

  bool _weekly = false; // false — 7 дней, true — 8 недель
  String _muscleFilter = 'all';
  int _shown = 40;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ЖУРНАЛ ТРЕНИРОВОК', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1)),
        backgroundColor: AppColors.panel,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.green,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Подход', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: () => showLogSetDialog(context, c, muscleId: _muscleFilter == 'all' ? null : _muscleFilter),
      ),
      body: ListenableBuilder(listenable: c, builder: (context, _) => _content()),
    );
  }

  Widget _content() {
    final now = c.now;
    final all = c.sets;
    // если выбранной мышцы больше нет в журнале (удалили все подходы) — вернуться к «Все»
    final ids = all.map((s) => s.muscleId).toSet();
    final filter = (_muscleFilter == 'all' || ids.contains(_muscleFilter)) ? _muscleFilter : 'all';
    final sets = filter == 'all' ? all : all.where((s) => s.muscleId == filter).toList();

    final vol7 = volumeInWindow(sets, now, 7);
    final volPrev7 = volumeInWindow(sets, now, 7, offsetDays: 7);
    final change = percentChange(vol7, volPrev7);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        _muscleChips(ids, filter),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _statTile('ОБЪЁМ 7 ДН', '${fmtVolume(vol7)} кг', change == null ? 'нет данных за прошлую' : '${change >= 0 ? '+' : '−'}${change.abs().toStringAsFixed(0)}% к прошлой', change == null ? Colors.white38 : (change >= 0 ? AppColors.green : AppColors.red))),
            const SizedBox(width: 8),
            Expanded(child: _statTile('ПОДХОДОВ 7 ДН', '${setsInWindow(sets, now, 7)}', 'всего: ${sets.length}', Colors.white38)),
            const SizedBox(width: 8),
            Expanded(child: _statTile('ДНЕЙ / 28', '${trainingDaysInWindow(sets, now, 28)}', 'с тренировками', Colors.white38)),
          ],
        ),
        const SizedBox(height: 12),
        _volumeCard(sets, now),
        const SizedBox(height: 12),
        if (filter == 'all') _distributionCard(sets, now) else _progressionCard(filter, sets),
        const SizedBox(height: 16),
        const Text('ИСТОРИЯ ПОДХОДОВ', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ..._history(sets),
      ],
    );
  }

  Widget _muscleChips(Set<String> ids, String filter) {
    // порядок — как в списке мышц, только те, где есть записи
    final present = [for (final e in c.muscles.entries) if (ids.contains(e.key)) e];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip('all', 'Все', filter),
          for (final e in present) _chip(e.key, e.value.name, filter),
        ],
      ),
    );
  }

  Widget _chip(String key, String label, String filter) {
    final active = filter == key;
    return GestureDetector(
      onTap: () => setState(() {
        _muscleFilter = key;
        _shown = 40;
      }),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.green.withValues(alpha: 0.18) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? AppColors.green : Colors.white12),
        ),
        child: Text(label, style: TextStyle(color: active ? AppColors.green : Colors.white60, fontSize: 11, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  Widget _statTile(String title, String value, String sub, Color subColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          const SizedBox(height: 2),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: subColor, fontSize: 9)),
        ],
      ),
    );
  }

  Widget _volumeCard(List<WorkoutSet> sets, DateTime now) {
    final values = _weekly ? volumeLastWeeks(sets, now, 8) : volumeLastDays(sets, now, 7);
    final labels = _weekly
        ? weekLabels(now, 8)
        : List.generate(7, (i) => dayNames[now.subtract(Duration(days: 6 - i)).weekday - 1]);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ОБЪЁМ НАГРУЗКИ (вес × повторы, кг)', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
              Container(
                decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [_seg('7 дн', !_weekly, () => setState(() => _weekly = false)), _seg('8 нед', _weekly, () => setState(() => _weekly = true))]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 130,
            width: double.infinity,
            child: CustomPaint(painter: VolumeBarsPainter(values: values, labels: labels, color: AppColors.green)),
          ),
        ],
      ),
    );
  }

  Widget _seg(String text, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: active ? AppColors.green : Colors.transparent, borderRadius: BorderRadius.circular(14)),
        child: Text(text, style: TextStyle(color: active ? Colors.black : Colors.white60, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _distributionCard(List<WorkoutSet> sets, DateTime now) {
    final byMuscle = volumeByMuscle(sets, now, 7).take(6).toList();
    final total = byMuscle.fold(0.0, (a, e) => a + e.value);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('РАСПРЕДЕЛЕНИЕ ОБЪЁМА ЗА 7 ДНЕЙ', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (byMuscle.isEmpty)
            const Text('За последние 7 дней подходов нет', style: TextStyle(color: Colors.white38, fontSize: 12))
          else
            for (final e in byMuscle)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(width: 110, child: Text(c.muscles[e.key]?.name ?? e.key, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: total <= 0 ? 0 : e.value / byMuscle.first.value,
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                        backgroundColor: const Color(0xFF222834),
                        valueColor: const AlwaysStoppedAnimation(AppColors.green),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 54, child: Text('${fmtVolume(e.value)} кг', textAlign: TextAlign.right, style: const TextStyle(color: Colors.white54, fontSize: 10))),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _progressionCard(String muscleId, List<WorkoutSet> sets) {
    final m = c.muscles[muscleId];
    final series = c.progression(muscleId);
    final days = dailyStats(sets);
    final bestDay = days.isEmpty ? null : days.reduce((a, b) => a.volume >= b.volume ? a : b);
    final delta = series.length > 1 ? series.last - series.first : 0.0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ПРОГРЕССИЯ 1RM • ${(m?.name ?? '').toUpperCase()}', style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
              Text('${delta >= 0 ? '+' : '−'}${trimNum(round1(delta.abs()))} кг', style: TextStyle(color: delta >= 0 ? AppColors.green : AppColors.red, fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(height: 70, width: double.infinity, child: CustomPaint(painter: MiniSparklinePainter(data: series, color: m?.color ?? AppColors.green))),
          const SizedBox(height: 8),
          Text(
            'Рекорд 1RM: ${trimNum(m?.maxWeight ?? 0)} кг'
            '${bestDay == null ? '' : '  •  лучший день по объёму: ${fmtVolume(bestDay.volume)} кг (${shortDate(bestDay.day)})'}',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  List<Widget> _history(List<WorkoutSet> sets) {
    if (sets.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('Пока нет записей.\nНажмите «+ Подход», чтобы начать журнал.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 12))),
        ),
      ];
    }
    final statsByDay = {for (final d in dailyStats(sets)) dayIndex(d.day): d};
    final recent = sets.reversed.take(_shown).toList();

    final out = <Widget>[];
    int? currentDay;
    for (final s in recent) {
      final di = dayIndex(s.at);
      if (di != currentDay) {
        currentDay = di;
        final st = statsByDay[di]!;
        out.add(Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(shortDate(st.day), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              Text('${st.sets} подх. • ${fmtVolume(st.volume)} кг', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ));
      }
      out.add(_setTile(s));
    }
    if (sets.length > _shown) {
      out.add(TextButton(onPressed: () => setState(() => _shown += 40), child: Text('Показать ещё (${sets.length - _shown})')));
    }
    return out;
  }

  Widget _setTile(WorkoutSet s) {
    final m = c.muscles[s.muscleId];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          CircleAvatar(radius: 4, backgroundColor: m?.color ?? Colors.white24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m?.name ?? s.muscleId, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  '${trimNum(s.weight)} кг × ${s.reps}  •  объём ${fmtVolume(s.volume)}  •  1RM ${trimNum(s.estimated1RM)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 18),
            tooltip: 'Удалить подход',
            onPressed: () {
              final removed = c.deleteSet(s.id);
              if (removed == null) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: const Text('Подход удалён'),
                  action: SnackBarAction(label: 'Отменить', onPressed: () => c.restoreSet(removed)),
                ));
            },
          ),
        ],
      ),
    );
  }
}
