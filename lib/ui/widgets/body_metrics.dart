import 'package:flutter/material.dart';

import '../../core/body_stats.dart';
import '../../core/chart_text.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/body.dart';
import '../../state/app_controller.dart';
import '../painters/chart_painters.dart';
import 'adaptive_pair.dart';
import 'chart_semantics.dart';
import 'form_dialog.dart';
import 'toast.dart';

String fmtKg(double v) => '${trimNum(round1(v)).replaceAll('.', ',')} кг';

/// Вес, ИМТ и цель по весу. Только факты: последний замер, изменение за 30 дней в килограммах,
/// ИМТ с категорией ВОЗ и оговоркой. Без оценок «хорошо/плохо» — цель задаёт человек.
class BodyMetrics extends StatelessWidget {
  final AppController controller;
  const BodyMetrics({super.key, required this.controller});

  AppController get c => controller;

  Future<void> _addWeight(BuildContext context) async {
    final last = c.latestWeightEntry;
    final r = await showFormDialog(
      context,
      title: 'Замер веса',
      actionLabel: 'Записать',
      fields: [
        FieldSpec('w', 'Вес, кг', numeric: true, initial: last == null ? '' : trimNum(last.kg)),
        const FieldSpec('d', 'Дата (дд.мм.гггг, пусто — сегодня)', initial: ''),
      ],
      validate: (v) {
        final kg = parseNum(v['w']!);
        final dOk = v['d']!.trim().isEmpty || parseDate(v['d']!) != null;
        return kg != null && kg >= WeightEntry.minKg && kg <= WeightEntry.maxKg && dOk;
      },
    );
    if (r == null || !context.mounted) return;
    final day = r['d']!.trim().isEmpty ? null : parseDate(r['d']!);
    final now = c.now;
    final at = day == null ? null : DateTime(day.year, day.month, day.day, now.hour, now.minute);
    final id = c.addWeight(parseNum(r['w']!)!, at: at);
    if (id == null) showToast(context, 'Замер не сохранён: проверьте вес и дату (не в будущем)');
  }

  Future<void> _editHeight(BuildContext context) async {
    final r = await showFormDialog(
      context,
      title: 'Рост',
      actionLabel: 'Сохранить',
      fields: [FieldSpec('h', 'Рост, см (пусто — не указан)', numeric: true, initial: c.heightCm?.toString() ?? '')],
      validate: (v) {
        if (v['h']!.trim().isEmpty) return true;
        final h = parseInt(v['h']!);
        return h != null && h >= 50 && h <= 272;
      },
    );
    if (r == null) return;
    c.setHeight(r['h']!.trim().isEmpty ? null : parseInt(r['h']!));
  }

  void _history(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => _WeightHistoryScreen(controller: c)));
  }

  @override
  Widget build(BuildContext context) {
    final last = c.latestWeightEntry;
    final change = weightChange(c.weights, c.now, 30);
    final index = c.bodyMassIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptivePair(
          children: [
            _Tile(
              key: const ValueKey('weight_tile'),
              onTap: last == null ? () => _addWeight(context) : () => _history(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Вес', style: _sub),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(last == null ? '—' : fmtKg(last.kg), style: _big),
                  ),
                  const SizedBox(height: 10),
                  if (c.weights.length >= 2)
                    Builder(builder: (context) {
                      final recent = [for (final w in c.weights.skip(c.weights.length > 30 ? c.weights.length - 30 : 0)) w.kg];
                      return ChartSemantics(
                        label: 'Вес, последние замеры, кг: ${describeSeries(recent)}',
                        child: SizedBox(
                          height: 28,
                          width: double.infinity,
                          child: CustomPaint(painter: MiniSparklinePainter(data: recent, color: AppColors.text)),
                        ),
                      );
                    }),
                  const Spacer(),
                  Text(
                    last == null
                        ? 'Нажмите, чтобы записать'
                        : change == null
                            ? 'Замер ${fmtDate(last.at)}'
                            : '30 дней: ${change.delta > 0 ? '+' : change.delta < 0 ? '−' : '±'}${fmtKg(change.delta.abs())}',
                    style: _sub,
                  ),
                ],
              ),
            ),
            _Tile(
              key: const ValueKey('bmi_tile'),
              onTap: () => _editHeight(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ИМТ', style: _sub),
                  const SizedBox(height: 6),
                  Text(index == null ? '—' : index.toStringAsFixed(1).replaceAll('.', ','), style: _big),
                  const SizedBox(height: 4),
                  Text(
                    index == null
                        ? (c.heightCm == null ? 'Укажите рост' : 'Нужен замер веса')
                        : '${bmiCategory(index)} · рост ${c.heightCm} см',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  const Text('Не учитывает мышцы и жир — грубый ориентир', style: _sub),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Tile(
          key: const ValueKey('body_goal_tile'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: Text('Цель по весу', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500))),
                  TextButton.icon(
                    key: const ValueKey('add_weight'),
                    onPressed: () => _addWeight(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Замер'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(AppRadii.pill), border: Border.all(color: AppColors.border)),
                child: Row(
                  children: [
                    for (final g in BodyGoal.all)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: c.bodyGoal == g,
                          label: BodyGoal.labels[g],
                          hint: c.bodyGoal == g ? 'нажмите ещё раз, чтобы снять цель' : null,
                          onTap: () => c.setBodyGoal(c.bodyGoal == g ? null : g),
                          excludeSemantics: true,
                          child: GestureDetector(
                            key: ValueKey('goal_$g'),
                            behavior: HitTestBehavior.opaque,
                            // повторное нажатие снимает цель
                            onTap: () => c.setBodyGoal(c.bodyGoal == g ? null : g),
                            // область нажатия 48 px, видимый сегмент — с отступом 3 px внутри таблетки
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Container(
                                height: 42,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: c.bodyGoal == g ? AppColors.accent : Colors.transparent, borderRadius: BorderRadius.circular(AppRadii.pill)),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    BodyGoal.labels[g]!,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.bodyGoal == g ? Colors.black : AppColors.muted),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (c.bodyGoal != null && change != null) ...[
                const SizedBox(height: 10),
                // факт рядом с целью — без оценки
                Text(
                  'За 30 дней вес ${change.delta == 0 ? 'не изменился' : '${change.delta > 0 ? 'вырос' : 'снизился'} на ${fmtKg(change.delta.abs())}'}',
                  style: _sub,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

const _sub = TextStyle(color: AppColors.muted, fontSize: 13);
const _big = TextStyle(fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -0.8);

class _Tile extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Tile({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.tile), side: const BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(18), child: child)),
      );
}

/// История замеров: новые сверху, удаление с «Отменить».
class _WeightHistoryScreen extends StatelessWidget {
  final AppController controller;
  const _WeightHistoryScreen({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Замеры веса')),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final list = c.weights.reversed.toList();
          if (list.isEmpty) {
            return const Center(child: Text('Замеров нет', style: _sub));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final w = list[i];
              return Container(
                padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
                decoration: tileDecoration(radius: AppRadii.card),
                child: Row(
                  children: [
                    Expanded(child: Text(fmtKg(w.kg), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                    Text('${fmtDate(w.at)}${w.source == 'health' ? ' · Health Connect' : ''}', style: _sub),
                    IconButton(
                      tooltip: 'Удалить замер',
                      icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
                      onPressed: () {
                        final removed = c.removeWeight(w.id);
                        if (removed == null) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: const Text('Замер удалён'),
                          action: SnackBarAction(label: 'Отменить', onPressed: () => c.restoreWeight(removed)),
                        ));
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
