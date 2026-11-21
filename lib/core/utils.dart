double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Поддержка запятой как десятичного разделителя (русская клавиатура).
double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.').replaceAll(' ', ''));
int? parseInt(String s) => int.tryParse(s.trim().replaceAll(' ', ''));
double round1(double v) => (v * 10).round() / 10;
String trimNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

String fmtMoney(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('\u00A0');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}$b';
}

/// Короткая запись числа для подписей на графиках и узлах: 850, «1,5к», «380к», «1,25М».
/// Меньше тысячи — как есть (не «0к»); дробная часть — через запятую, без лишних нулей.
String fmtCompact(num v) {
  final a = v.abs();
  final sign = v < 0 ? '−' : '';
  String dec(double x, int digits) {
    var s = x.toStringAsFixed(digits);
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return s.replaceAll('.', ',');
  }

  if (a.round() < 1000) return '$sign${a.round()}';
  final k = a / 1000;
  final kText = k < 10 ? dec(k, 1) : '${k.round()}';
  // 999 600 → не «1000к», а «1М»
  if (k.round() < 1000 && kText != '1000') return '$sign$kTextк';
  final m = a / 1000000;
  return '$sign${dec(m, m < 10 ? 2 : (m < 100 ? 1 : 0))}М';
}

const monthNames = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
const dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
String monthYear(DateTime d) => '${monthNames[d.month - 1]} ${d.year}';

/// «21 ноября» — день и месяц в родительном падеже.
String dayMonth(DateTime d) =>
    '${d.day} ${const ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'][d.month - 1]}';
String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Формула 1RM: Бжицки до 10 повторов, Эпли дальше (Бжицки при больших повторах неточна).
double oneRM(double weight, int reps) {
  if (reps <= 1) return weight;
  if (reps <= 10) return weight * (36 / (37 - reps));
  return weight * (1 + reps / 30.0);
}

/// Объём нагрузки для подписей: 850 → «850», 12 400 → «12.4 т».
String fmtVolume(double v) => v >= 10000 ? '${(v / 1000).toStringAsFixed(1)} т' : fmtMoney(v.round());

const _monthShort = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];

/// «Сб, 24 окт»
String shortDate(DateTime d) => '${dayNames[d.weekday - 1]}, ${d.day} ${_monthShort[d.month - 1]}';

/// «24.10.2026»
String fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

/// Разбор «дд.мм.гггг» (допустимы также «/», «-», «,»). null — не удалось или такой даты нет (31.02).
DateTime? parseDate(String s) {
  final m = RegExp(r'^\s*(\d{1,2})[./\-,](\d{1,2})[./\-,](\d{4})\s*$').firstMatch(s);
  if (m == null) return null;
  final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
  final dt = DateTime(y, mo, d);
  return (dt.year == y && dt.month == mo && dt.day == d) ? dt : null;
}

/// «окт» для месяца 1..12.
String monthShortName(int month) => _monthShort[month - 1];

/// «14:05»
String fmtTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Ограничение целого числа без неоднозначной типизации `num.clamp`.
int clampI(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
