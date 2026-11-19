part of '../app_controller.dart';

/// Свои категории операций и правила разбора выписки.
/// Расширение того же library: работает с состоянием контроллера напрямую, мутации — только через `_commit`.
extension CategoryOps on AppController {
  static const maxCategories = 200;
  static const maxRules = 1000;

  List<CustomCategory> get customCategories => List.unmodifiable(_d.categories);
  List<ImportRule> get importRules => List.unmodifiable(_d.importRules);

  /// Сколько операций в категории — чтобы показать, что архивная категория не пустая.
  int transactionsInCategory(String id) => _d.transactions.where((t) => t.categoryId == id).length;

  /// Новая своя категория. Название не должно совпадать с уже существующей того же типа. Возвращает id.
  String? addCategory(String name, {required bool isIncome, String icon = 'tag'}) {
    final n = name.trim();
    if (n.isEmpty || n.length > CustomCategory.maxName || !customCategoryIcons.containsKey(icon) || _d.categories.length >= maxCategories) {
      return null;
    }
    final taken = allFinCategories.any((c) => c.isIncome == isIncome && c.name.toLowerCase() == n.toLowerCase());
    if (taken) return null;
    final now = _clock();
    final c = CustomCategory(id: '${CustomCategory.idPrefix}${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}', name: n, isIncome: isIncome, icon: icon);
    _commit(() => _d.categories.add(c));
    return c.id;
  }

  /// Переименование и смена значка. Операции хранят id категории — история не меняется.
  bool updateCategory(String id, {required String name, String? icon}) {
    final c = _d.categories.where((x) => x.id == id).firstOrNull;
    final n = name.trim();
    if (c == null || n.isEmpty || n.length > CustomCategory.maxName || (icon != null && !customCategoryIcons.containsKey(icon))) return false;
    final taken = allFinCategories.any((x) => x.id != id && x.isIncome == c.isIncome && x.name.toLowerCase() == n.toLowerCase());
    if (taken) return false;
    _commit(() {
      c.name = n;
      if (icon != null) c.icon = icon;
    });
    return true;
  }

  /// В архив: категория пропадает из выбора, но операции и итоги по ней остаются. [archived] = false — вернуть.
  bool archiveCategory(String id, {bool archived = true}) {
    final c = _d.categories.where((x) => x.id == id).firstOrNull;
    if (c == null) return false;
    _commit(() => c.archivedAt = archived ? _clock() : null);
    return true;
  }

  /// Новое правило разбора: описание содержит [pattern] → категория. Тот же образец заменяет прежнюю категорию.
  String? addImportRule(String pattern, String categoryId) {
    final p = pattern.trim();
    if (finCategory(categoryId) == null || p.length < 2 || p.length > ImportRule.maxPattern) return null;
    final now = _clock();
    final existing = _d.importRules.indexWhere((r) => r.pattern.toLowerCase() == p.toLowerCase() && finCategory(r.categoryId)?.isIncome == finCategory(categoryId)!.isIncome);
    final rule = ImportRule(id: 'rule_${now.microsecondsSinceEpoch}_${_random.nextInt(1 << 20)}', pattern: p, categoryId: categoryId, createdAt: now);
    if (existing < 0 && _d.importRules.length >= maxRules) return null;
    _commit(() {
      if (existing >= 0) {
        _d.importRules[existing] = rule;
      } else {
        _d.importRules.add(rule);
      }
    });
    return rule.id;
  }

  bool removeImportRule(String id) {
    final i = _d.importRules.indexWhere((r) => r.id == id);
    if (i < 0) return false;
    _commit(() => _d.importRules.removeAt(i));
    return true;
  }

  /// Импортированные операции, которые правила отнесут в другую категорию. Трогаются только операции
  /// из выписки, оставшиеся в «Прочем»: выбор, сделанный человеком вручную, правила не перезаписывают.
  List<(MoneyTx, String)> rulesWouldRecategorize() => [
        for (final t in _d.transactions)
          if (t.importId != null && (t.categoryId == 'other_exp' || t.categoryId == 'other_inc'))
            if (categoryByRules(t.note, t.isIncome, _d.importRules) case final cat? when cat != t.categoryId) (t, cat),
      ];

  /// Применяет правила к уже загруженным операциям из выписки (см. [rulesWouldRecategorize]). Возвращает сколько изменено.
  int applyRulesToImported() {
    final changes = rulesWouldRecategorize();
    if (changes.isEmpty) return 0;
    _commit(() {
      for (final (t, cat) in changes) {
        final i = _d.transactions.indexWhere((x) => x.id == t.id);
        if (i < 0) continue;
        final updated = MoneyTx(
          id: t.id,
          at: t.at,
          isIncome: t.isIncome,
          amount: t.amount,
          categoryId: cat,
          note: t.note,
          affectsNetWorth: t.affectsNetWorth,
          recurringId: t.recurringId,
          importId: t.importId,
        );
        _d.transactions[i] = updated;
        _pending.upsertTx(updated);
      }
    });
    return changes.length;
  }
}
