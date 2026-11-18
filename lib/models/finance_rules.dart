// Свои категории операций и правила разбора выписки. Чистый Dart, без Flutter.

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;
DateTime? _time(Object? v) => v is num && v.isFinite && v == v.roundToDouble() ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

/// Категория, заведённая человеком («Образование», «Дети», «Животные»). Удалить категорию с операциями нельзя —
/// только убрать в архив: она пропадает из выбора, но старые операции и итоги по ней остаются.
class CustomCategory {
  static const maxName = 40;
  static const idPrefix = 'u_';

  final String id;
  String name;
  final bool isIncome;
  String icon; // ключ из набора значков (finance_categories.dart)
  DateTime? archivedAt;

  CustomCategory({required this.id, required this.name, required this.isIncome, this.icon = 'tag', this.archivedAt});

  bool get isValid => id.startsWith(idPrefix) && id.length > idPrefix.length && name.trim().isNotEmpty && name.length <= maxName && icon.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'in': isIncome,
        'icon': icon,
        if (archivedAt != null) 'arch': archivedAt!.millisecondsSinceEpoch,
      };

  factory CustomCategory.fromJson(Map<String, dynamic> j) => tryFromJson(j) ?? (throw const FormatException('CustomCategory'));

  static CustomCategory? tryFromJson(Map<String, dynamic> j) {
    final id = _str(j['id']), name = j['name'], inc = j['in'], icon = _str(j['icon']);
    if (id == null || name is! String || inc is! bool || icon == null) return null;
    if (j['arch'] != null && _time(j['arch']) == null) return null;
    final c = CustomCategory(id: id, name: name, isIncome: inc, icon: icon, archivedAt: _time(j['arch']));
    return c.isValid ? c : null;
  }
}

/// Правило разбора выписки: если описание операции содержит [pattern] (без учёта регистра) — категория [categoryId].
/// Правило задаёт человек; приложение само правил не придумывает.
class ImportRule {
  static const maxPattern = 60;

  final String id;
  final String pattern;
  final String categoryId;
  final DateTime createdAt;

  const ImportRule({required this.id, required this.pattern, required this.categoryId, required this.createdAt});

  bool get isValid => id.trim().isNotEmpty && pattern.trim().length >= 2 && pattern.length <= maxPattern && categoryId.isNotEmpty;

  Map<String, dynamic> toJson() => {'id': id, 'p': pattern, 'c': categoryId, 't': createdAt.millisecondsSinceEpoch};

  factory ImportRule.fromJson(Map<String, dynamic> j) => tryFromJson(j) ?? (throw const FormatException('ImportRule'));

  static ImportRule? tryFromJson(Map<String, dynamic> j) {
    final id = _str(j['id']), p = j['p'], c = _str(j['c']), t = _time(j['t']);
    if (id == null || p is! String || c == null || t == null) return null;
    final r = ImportRule(id: id, pattern: p, categoryId: c, createdAt: t);
    return r.isValid ? r : null;
  }
}
