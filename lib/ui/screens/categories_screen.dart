import 'package:flutter/material.dart';

import '../../core/finance_categories.dart';
import '../../core/theme.dart';
import '../../models/finance_rules.dart';
import '../../state/app_controller.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/form_dialog.dart';
import '../widgets/toast.dart';

const _iconNames = {
  'tag': 'Метка',
  'school': 'Учёба',
  'child': 'Дети',
  'pets': 'Животные',
  'gift': 'Подарки',
  'travel': 'Поездки',
  'cafe': 'Кафе',
  'sport': 'Спорт',
  'book': 'Книги',
  'phone': 'Связь',
  'beauty': 'Уход',
  'work': 'Работа',
};

/// Свои категории операций и правила разбора выписки.
class CategoriesScreen extends StatelessWidget {
  final AppController controller;
  const CategoriesScreen({super.key, required this.controller});

  AppController get c => controller;

  static Map<String, String> _categoryOptions() => {for (final x in pickableFinCategories()) x.id: '${x.isIncome ? 'Доход' : 'Расход'} • ${x.name}'};

  Future<void> _editCategory(BuildContext context, [CustomCategory? cat]) async {
    final r = await showFormDialog(
      context,
      title: cat == null ? 'Новая категория' : 'Категория',
      actionLabel: 'Сохранить',
      accent: AppColors.accent,
      fields: [
        FieldSpec('n', 'Название', initial: cat?.name ?? ''),
        if (cat == null) const FieldSpec('t', 'Тип', initial: 'exp', options: {'exp': 'Расход', 'inc': 'Доход'}),
        FieldSpec('i', 'Значок', initial: cat?.icon ?? 'tag', options: _iconNames),
      ],
      validate: (v) => v['n']!.trim().isNotEmpty && v['n']!.trim().length <= CustomCategory.maxName,
    );
    if (r == null || !context.mounted) return;
    final ok = cat == null ? c.addCategory(r['n']!, isIncome: r['t'] == 'inc', icon: r['i']!) != null : c.updateCategory(cat.id, name: r['n']!, icon: r['i']);
    if (!ok) showToast(context, 'Не сохранено: такая категория уже есть');
  }

  Future<void> _addRule(BuildContext context) async {
    final r = await showFormDialog(
      context,
      title: 'Правило разбора',
      actionLabel: 'Сохранить',
      accent: AppColors.accent,
      fields: [
        const FieldSpec('p', 'Если описание содержит (например, «Пятёрочка»)'),
        FieldSpec('c', 'Категория', initial: 'food', options: _categoryOptions()),
      ],
      validate: (v) => v['p']!.trim().length >= 2,
    );
    if (r == null || !context.mounted) return;
    if (c.addImportRule(r['p']!, r['c']!) == null) showToast(context, 'Правило не сохранено');
  }

  Future<void> _apply(BuildContext context, int n) async {
    final ok = await confirmDialog(context,
        title: 'Применить правила?',
        message: 'Категория изменится у $n операций из выписки, которые сейчас в «Прочем». Операции, где категорию вы выбрали сами, не меняются.',
        confirmLabel: 'Применить');
    if (!ok || !context.mounted) return;
    showToast(context, 'Изменено операций: ${c.applyRulesToImported()}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Категории и правила'), backgroundColor: AppColors.panel, elevation: 0),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final cats = c.customCategories;
          final rules = c.importRules;
          final pending = c.rulesWouldRecategorize().length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Row(
                children: [
                  const Expanded(child: Text('СВОИ КАТЕГОРИИ', style: _caption)),
                  TextButton.icon(
                      key: const ValueKey('add_category'),
                      onPressed: () => _editCategory(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Добавить')),
                ],
              ),
              if (cats.isEmpty)
                const Text('Встроенных категорий не хватает? Добавьте свои: «Образование», «Дети», «Животные».',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
              for (final x in cats) _categoryTile(context, x),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: Text('ПРАВИЛА РАЗБОРА ВЫПИСКИ', style: _caption)),
                  TextButton.icon(
                      key: const ValueKey('add_rule'),
                      onPressed: () => _addRule(context),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Добавить')),
                ],
              ),
              const Text(
                'При импорте выписки описание сверяется с правилами по порядку: первое подходящее задаёт категорию. '
                'Не подошло ни одно — операция идёт в категорию по умолчанию.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              for (final r in rules)
                Container(
                  key: ValueKey('rule_${r.id}'),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                  decoration: tileDecoration(radius: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('«${r.pattern}» → ${finCategory(r.categoryId)?.name ?? 'категория удалена'}',
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                      ),
                      IconButton(
                        tooltip: 'Удалить правило',
                        icon: const Icon(Icons.close, size: 18, color: AppColors.muted),
                        onPressed: () => c.removeImportRule(r.id),
                      ),
                    ],
                  ),
                ),
              if (pending > 0) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const ValueKey('apply_rules'),
                  onPressed: () => _apply(context, pending),
                  child: Text('Применить к загруженным: $pending'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _categoryTile(BuildContext context, CustomCategory x) {
    final n = c.transactionsInCategory(x.id);
    final archived = x.archivedAt != null;
    return Padding(
      key: ValueKey('category_${x.id}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(customCategoryIcons[x.icon] ?? Icons.sell_outlined, color: archived ? AppColors.muted : AppColors.text),
          title: Text(x.name, style: TextStyle(color: archived ? AppColors.muted : AppColors.text)),
          subtitle: Text('${x.isIncome ? 'доход' : 'расход'} · операций $n${archived ? ' · в архиве' : ''}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          onTap: () => _editCategory(context, x),
          trailing: TextButton(
            onPressed: () => c.archiveCategory(x.id, archived: !archived),
            child: Text(archived ? 'Вернуть' : 'В архив'),
          ),
        ),
      ),
    );
  }
}

const _caption = TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.8);
