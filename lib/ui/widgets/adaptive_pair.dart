import 'package:flutter/widgets.dart';

/// С какого системного масштаба шрифта плитки и кнопки «в ряд» встают друг под другом.
const double kStackTextScale = 1.5;

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
