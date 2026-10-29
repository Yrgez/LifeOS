import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_controller.dart';
import 'form_dialog.dart';

/// Диалог записи подхода. Если [muscleId] задан — мышца фиксирована, а вес и повторы
/// подставляются из последнего подхода (быстро записать «ещё один такой же»).
Future<void> showLogSetDialog(BuildContext context, AppController c, {String? muscleId}) async {
  final muscleOptions = {for (final e in c.muscles.entries) e.key: e.value.name};
  final last = muscleId == null ? null : c.lastSetFor(muscleId);

  final r = await showFormDialog(
    context,
    title: muscleId == null ? 'Записать подход' : 'Подход: ${c.muscles[muscleId]?.name ?? ''}',
    actionLabel: 'Сохранить',
    fields: [
      if (muscleId == null) FieldSpec('m', 'Мышечная группа', initial: muscleOptions.keys.first, options: muscleOptions),
      FieldSpec('w', 'Вес снаряда (кг)', numeric: true, initial: last == null ? '' : trimNum(last.weight)),
      FieldSpec('r', 'Количество повторений', numeric: true, initial: last == null ? '' : '${last.reps}'),
      const FieldSpec('d', 'Когда', initial: '0', options: {
        '0': 'Сегодня',
        '1': 'Вчера',
        '2': '2 дня назад',
        '3': '3 дня назад',
        '4': '4 дня назад',
        '5': '5 дней назад',
        '6': '6 дней назад',
      }),
    ],
    validate: (v) => (parseNum(v['w']!) ?? 0) > 0 && (parseInt(v['r']!) ?? 0) > 0,
  );
  if (r == null || !context.mounted) return;

  final res = c.logWorkout(
    muscleId ?? r['m']!,
    parseNum(r['w']!)!,
    parseInt(r['r']!)!,
    daysAgo: parseInt(r['d']!) ?? 0,
  );
  if (!res.ok) return;

  final text = res.isRecord ? 'Новый рекорд! Расчётный 1RM: ${trimNum(res.oneRm)} кг' : 'Подход записан • 1RM ≈ ${trimNum(res.oneRm)} кг';
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: res.isRecord ? AppColors.green : null,
    ));
}
