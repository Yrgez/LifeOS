// Тело: замеры веса, рост и цель по весу. Чистый Dart, без Flutter.

const int _maxMs = 8640000000000000;

/// Цель по весу. Это намерение человека, а не оценка: приложение лишь показывает факты рядом с ней.
class BodyGoal {
  static const lose = 'lose';
  static const maintain = 'maintain';
  static const gain = 'gain';

  static const all = [lose, maintain, gain];
  static const labels = {lose: 'Похудение', maintain: 'Поддержание', gain: 'Набор'};
  static bool isValid(String g) => labels.containsKey(g);
}

/// Замер веса. Источник — вручную (Health Connect может добавиться позже).
class WeightEntry {
  static const minKg = 20.0;
  static const maxKg = 400.0;

  final String id;
  final DateTime at;
  final double kg;
  final String source; // 'manual' — введено вручную, 'health' — Health Connect

  const WeightEntry({required this.id, required this.at, required this.kg, this.source = 'manual'});

  bool get isValid => id.trim().isNotEmpty && kg.isFinite && kg >= minKg && kg <= maxKg && (source == 'manual' || source == 'health');

  Map<String, dynamic> toJson() => {'id': id, 't': at.millisecondsSinceEpoch, 'kg': kg, if (source != 'manual') 'src': source};

  factory WeightEntry.fromJson(Map<String, dynamic> j) => tryFromJson(j) ?? (throw const FormatException('WeightEntry'));

  /// null — нет id, даты или вес вне допустимых границ.
  static WeightEntry? tryFromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final t = j['t'];
    final kg = j['kg'];
    if (id is! String || t is! num || !t.isFinite || t != t.roundToDouble() || t.abs() > _maxMs || kg is! num) return null;
    final src = j['src'] ?? 'manual';
    if (src is! String) return null;
    final e = WeightEntry(id: id, at: DateTime.fromMillisecondsSinceEpoch(t.toInt()), kg: kg.toDouble(), source: src);
    return e.isValid ? e : null;
  }
}
