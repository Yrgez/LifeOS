import 'package:flutter/widgets.dart';

/// Обёртка нарисованного графика: программа чтения экрана слышит [label] — название и данные графика
/// (см. `describeSeries` в `core/chart_text.dart`), а не пустое место.
class ChartSemantics extends StatelessWidget {
  final String label;
  final Widget child;
  const ChartSemantics({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Semantics(container: true, image: true, label: label, child: ExcludeSemantics(child: child));
}
