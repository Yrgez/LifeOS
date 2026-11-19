/// Текстовое описание графиков для программы чтения экрана (TalkBack).
///
/// График нарисован на холсте и сам по себе для неё пуст. Описание — только сами данные:
/// значения, а для длинного ряда — первое, последнее, наименьшее и наибольшее. Без «тренда»
/// и оценок: выводы человек делает сам.
library;

import 'utils.dart';

/// Число для озвучки: целые — с разрядами («12 500»), дробные — с одним знаком через запятую.
String speakNum(num v) {
  final d = v.toDouble();
  if (d == d.roundToDouble()) return '${d < 0 ? '−' : ''}${fmtMoney(d.round().abs())}';
  return trimNum(d).replaceAll('.', ',');
}

/// «пн 5 200, вт 6 100, …» для короткого ряда (не длиннее [maxListed]);
/// «точек: 30; первое 82, последнее 80,5, наименьшее 79, наибольшее 83» — для длинного.
/// [labels] — подписи точек (дни, месяцы), той же длины, что [values]; [fmt] — формат значения.
String describeSeries(List<num> values, {List<String>? labels, String Function(num)? fmt, int maxListed = 12}) {
  if (values.isEmpty) return 'нет данных';
  final f = fmt ?? speakNum;
  final named = labels != null && labels.length == values.length;
  if (values.length <= maxListed) {
    return [for (var i = 0; i < values.length; i++) named ? '${labels[i]} ${f(values[i])}' : f(values[i])].join(', ');
  }
  var lo = values.first, hi = values.first;
  for (final v in values) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  return 'точек: ${values.length}; первое ${f(values.first)}, последнее ${f(values.last)}, наименьшее ${f(lo)}, наибольшее ${f(hi)}';
}
