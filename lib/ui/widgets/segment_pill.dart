import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Переключатель-«таблетка» из нескольких сегментов («Спереди | Сзади», «7 дн | 8 нед»).
/// Выглядит компактно, но область нажатия каждого сегмента — не меньше 48 px в высоту (рекомендация Android),
/// а программа чтения экрана слышит кнопку, её название и выбран ли сегмент.
class SegmentPill<T> extends StatelessWidget {
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Color activeColor;
  final double fontSize;
  final EdgeInsets segmentPadding;

  /// Ключ сегмента для тестов: `<keyPrefix><значение>`.
  final String? keyPrefix;

  const SegmentPill({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.activeColor = AppColors.accent,
    this.fontSize = 13,
    this.segmentPadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    this.keyPrefix,
  });

  static const double _inset = 3;
  static const double _minTap = 48;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(fontSize) / fontSize;
    // видимая высота таблетки: строка текста + поля сегмента + отступ таблетки
    final visual = fontSize * 1.25 * scale + segmentPadding.vertical + _inset * 2;
    final height = visual < _minTap ? _minTap : visual;
    return SizedBox(
      height: height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Center(
              child: Container(
                height: visual,
                decoration: BoxDecoration(
                  color: AppColors.field,
                  borderRadius: BorderRadius.circular(visual / 2),
                  border: Border.all(color: AppColors.border),
                ),
              ),
            ),
          ),
          // если даже на своей строке не помещается (огромный шрифт, узкий экран) — сжимается, а не вылезает за край
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _inset),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final e in options.entries) _segment(e.key, e.value, visual - _inset * 2),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(T v, String label, double h) {
    final active = v == value;
    return Semantics(
      button: true,
      selected: active,
      inMutuallyExclusiveGroup: true,
      label: label,
      // своё действие нажатия: excludeSemantics прячет и жест вложенного GestureDetector
      onTap: () => onChanged(v),
      excludeSemantics: true,
      child: GestureDetector(
        key: keyPrefix == null ? null : ValueKey('$keyPrefix$v'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(v),
        child: SizedBox(
          height: double.infinity,
          child: Center(
            child: Container(
              height: h,
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: segmentPadding.horizontal / 2),
              decoration: BoxDecoration(color: active ? activeColor : Colors.transparent, borderRadius: BorderRadius.circular(h / 2)),
              child: Text(
                label,
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500, color: active ? Colors.black : AppColors.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
