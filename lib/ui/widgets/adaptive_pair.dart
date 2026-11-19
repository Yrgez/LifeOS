import 'package:flutter/material.dart';

/// С какого системного масштаба шрифта плитки и кнопки «в ряд» встают друг под другом.
const double kStackTextScale = 1.3;

/// Крупный ли системный шрифт: тогда в узкой колонке слова рвались бы посередине («Груд-ные мыш-цы»).
bool largeText(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) / 10 >= kStackTextScale;

/// Плитки или кнопки в ряд равной высоты; при крупном системном шрифте ([largeText]) — друг под другом
/// на всю ширину, чтобы текст не дробился в узкой колонке.
class AdaptivePair extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  const AdaptivePair({super.key, required this.children, this.spacing = 12});

  @override
  Widget build(BuildContext context) {
    if (largeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, w) in children.indexed) ...[
            if (i > 0) SizedBox(height: spacing),
            // IntrinsicHeight — для плиток со Spacer внутри: без него в столбце высота не ограничена
            IntrinsicHeight(child: w),
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, w) in children.indexed) ...[
            if (i > 0) SizedBox(width: spacing),
            Expanded(child: w),
          ],
        ],
      ),
    );
  }
}

/// Строка «описание слева — значение справа» (как плитка ресурсов). При крупном шрифте значение уходит под описание:
/// иначе крупные цифры выдавливают текст за край.
class LeadTrailing extends StatelessWidget {
  final Widget lead;
  final Widget trailing;
  final double gap;
  const LeadTrailing({super.key, required this.lead, required this.trailing, this.gap = 8});

  @override
  Widget build(BuildContext context) {
    if (largeText(context)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [lead, SizedBox(height: gap), trailing]);
    }
    return Row(children: [Expanded(child: lead), SizedBox(width: gap), trailing]);
  }
}

/// Строка с переключателем. При крупном шрифте переключатель — под текстом, а не справа:
/// иначе длинные слова названия («Эксперименты») рвутся посередине. Для программы чтения экрана — одна строка.
Widget adaptiveSwitchTile(
  BuildContext context, {
  Key? key,
  required Widget title,
  Widget? subtitle,
  Widget? secondary,
  required bool value,
  required ValueChanged<bool>? onChanged,
  Color? activeThumbColor,
}) {
  if (!largeText(context)) {
    return SwitchListTile(key: key, secondary: secondary, title: title, subtitle: subtitle, value: value, activeThumbColor: activeThumbColor, onChanged: onChanged);
  }
  return MergeSemantics(
    child: ListTile(
      key: key,
      title: title,
      onTap: onChanged == null ? null : () => onChanged(!value),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null) subtitle,
          Switch(value: value, activeThumbColor: activeThumbColor, onChanged: onChanged),
        ],
      ),
    ),
  );
}
