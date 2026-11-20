import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Плитка показателя: «ЗАГОЛОВОК», число, подпись. Итоги месяца в деньгах, сводка журнала тренировок.
class StatTile extends StatelessWidget {
  final String title;
  final String value;
  final String sub;
  final Color valueColor;
  final Color subColor;

  const StatTile(this.title, this.value, {super.key, this.sub = '', this.valueColor = AppColors.text, this.subColor = AppColors.muted});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: tileDecoration(radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 9, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: valueColor))),
            const SizedBox(height: 2),
            // пустая подпись — пробел: плитки в ряд остаются одной высоты
            Text(sub.isEmpty ? ' ' : sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: subColor, fontSize: 9)),
          ],
        ),
      );
}
