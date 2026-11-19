import '../models/finance_rules.dart';
import 'finance_categories.dart';

/// Применение правил разбора выписки. Чистая логика без Flutter.

String _norm(String s) => s.toLowerCase().replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Категория по первому подходящему правилу; правило подходит, если описание содержит образец и тип категории
/// (доход/расход) совпадает со знаком операции. null — ни одно правило не подошло.
String? categoryByRules(String note, bool isIncome, List<ImportRule> rules) {
  final n = _norm(note);
  if (n.isEmpty) return null;
  for (final r in rules) {
    final cat = finCategory(r.categoryId);
    if (cat == null || cat.isIncome != isIncome) continue;
    if (n.contains(_norm(r.pattern))) return r.categoryId;
  }
  return null;
}

/// Образец для правила из описания: текст до первой цифры или служебного знака — «Пятёрочка 1234 Москва» → «Пятёрочка».
/// null — описание не даёт осмысленного образца.
String? suggestPattern(String note) {
  final m = RegExp(r'^[^\d*#№/\\|]+').firstMatch(note.trim());
  var p = (m?.group(0) ?? '').trim();
  p = p.replaceAll(RegExp(r'[\s,.;:\-–—]+$'), '').trim();
  if (p.length < 2) return null;
  return p.length > ImportRule.maxPattern ? p.substring(0, ImportRule.maxPattern).trim() : p;
}

/// Частые описания без правила: образец → сколько строк, самые частые первыми.
List<(String, int)> unmatchedPatterns(Iterable<(String note, bool isIncome)> rows, List<ImportRule> rules, {int limit = 5}) {
  final counts = <String, int>{};
  final shown = <String, String>{};
  for (final (note, inc) in rows) {
    if (categoryByRules(note, inc, rules) != null) continue;
    final p = suggestPattern(note);
    if (p == null) continue;
    final k = _norm(p);
    counts[k] = (counts[k] ?? 0) + 1;
    shown.putIfAbsent(k, () => p);
  }
  final list = counts.entries.toList()..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));
  return [for (final e in list.take(limit)) (shown[e.key]!, e.value)];
}
