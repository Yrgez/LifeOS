import 'dart:math';

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

const monthNames = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
const dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
String monthYear(DateTime d) => '${monthNames[d.month - 1]} ${d.year}';
String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Формула 1RM: Бжицки до 10 повторов, Эпли дальше (Бжицки при больших повторах неточна).
double oneRM(double weight, int reps) {
  if (reps <= 1) return weight;
  if (reps <= 10) return weight * (36 / (37 - reps));
  return weight * (1 + reps / 30.0);
}

/// Корреляция Пирсона по выровненным хвостам рядов.
double? pearson(List<double> a, List<double> b) {
  final n = min(a.length, b.length);
  if (n < 3) return null;
  final x = a.sublist(a.length - n);
  final y = b.sublist(b.length - n);
  final mx = x.reduce((p, c) => p + c) / n;
  final my = y.reduce((p, c) => p + c) / n;
  double sxy = 0, sxx = 0, syy = 0;
  for (int i = 0; i < n; i++) {
    sxy += (x[i] - mx) * (y[i] - my);
    sxx += (x[i] - mx) * (x[i] - mx);
    syy += (y[i] - my) * (y[i] - my);
  }
  if (sxx == 0 || syy == 0) return null;
  return sxy / sqrt(sxx * syy);
}

/// Приводит ряд к ровно 7 точкам (дополняет слева / обрезает слева).
List<double> fit7(List<double> l) {
  final r = List<double>.from(l);
  while (r.length < 7) {
    r.insert(0, r.isEmpty ? 0 : r.first);
  }
  return r.length > 7 ? r.sublist(r.length - 7) : r;
}

/// Добавляет точку в конец, держа длину ряда не больше 7.
void push7(List<double> l, double v) {
  l.add(v);
  while (l.length > 7) {
    l.removeAt(0);
  }
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
