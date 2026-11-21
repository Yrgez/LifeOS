import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'adaptive_pair.dart';

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
        decoration: tileDecoration(radius: AppRadii.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // заголовок в одну строку: иначе числа соседних плиток встают на разной высоте
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(title, maxLines: 1, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.bold))),
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: valueColor))),
            // пустая подпись — пробел: плитки в ряд остаются одной высоты; при крупном шрифте плитки стоят столбиком — не нужна
            if (sub.isNotEmpty || !largeText(context)) ...[
              const SizedBox(height: 2),
              Text(sub.isEmpty ? ' ' : sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: subColor, fontSize: 11)),
            ],
          ],
        ),
      );
}
