import '../models/body.dart';
import 'utils.dart';

/// Индекс массы тела = вес / рост². Грубый ориентир: не различает мышцы и жир, не учитывает возраст и пол.
double? bmi(double? kg, int? heightCm) {
  if (kg == null || heightCm == null || heightCm <= 0) return null;
  final m = heightCm / 100;
  return kg / (m * m);
}

/// Категории ВОЗ для взрослых.
String bmiCategory(double v) {
  if (v < 18.5) return 'ниже нормы';
  if (v < 25) return 'норма';
  if (v < 30) return 'выше нормы';
  return 'ожирение';
}

/// Последний замер (по времени).
WeightEntry? latestWeight(List<WeightEntry> sorted) => sorted.isEmpty ? null : sorted.last;

/// Изменение веса за [days] дней: последний замер минус последний замер не позже начала окна.
/// null — нет замера до начала окна (сравнивать не с чем).
({double delta, WeightEntry from, WeightEntry to})? weightChange(List<WeightEntry> sorted, DateTime now, int days) {
  if (sorted.length < 2) return null;
  final start = now.subtract(Duration(days: days));
  WeightEntry? base;
  for (final e in sorted) {
    if (e.at.isAfter(start)) break;
    base = e;
  }
  final last = sorted.last;
  if (base == null || identical(base, last)) return null;
  return (delta: round1(last.kg - base.kg), from: base, to: last);
}
