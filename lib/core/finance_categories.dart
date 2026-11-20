import 'package:flutter/material.dart';

import 'theme.dart';

/// Категория операции. Набор фиксированный: тип операции (доход/расход) определяется категорией.
class FinCategory {
  final String id;
  final String name;
  final bool isIncome;
  final IconData icon;
  const FinCategory(this.id, this.name, this.isIncome, this.icon);

  /// Деньги — измерение «Материальное»: у всех категорий его охра, различаются они значком и названием
  /// (двенадцать разных цветов по всему кругу спорили бы с цветами измерений).
  Color get color => AppColors.material;
}

const List<FinCategory> kFinCategories = [
  // расходы
  FinCategory('housing', 'Жильё', false, Icons.home),
  FinCategory('food', 'Еда', false, Icons.restaurant),
  FinCategory('transport', 'Транспорт', false, Icons.directions_car),
  FinCategory('health', 'Здоровье', false, Icons.favorite),
  FinCategory('fun', 'Развлечения', false, Icons.sports_esports),
  FinCategory('shopping', 'Покупки', false, Icons.shopping_bag),
  FinCategory('subs', 'Подписки', false, Icons.autorenew),
  FinCategory('other_exp', 'Прочее', false, Icons.more_horiz),
  // доходы
  FinCategory('salary', 'Зарплата', true, Icons.work),
  FinCategory('side', 'Подработка', true, Icons.handyman),
  FinCategory('invest', 'Проценты и инвестиции', true, Icons.trending_up),
  FinCategory('other_inc', 'Прочее', true, Icons.more_horiz),
];

/// Значки для своих категорий: ключ хранится в данных, значок — только в интерфейсе.
const Map<String, IconData> customCategoryIcons = {
  'tag': Icons.sell_outlined,
  'school': Icons.school_outlined,
  'child': Icons.child_care,
  'pets': Icons.pets,
  'gift': Icons.card_giftcard,
  'travel': Icons.flight_takeoff,
  'cafe': Icons.local_cafe_outlined,
  'sport': Icons.fitness_center,
  'book': Icons.menu_book_outlined,
  'phone': Icons.smartphone,
  'beauty': Icons.spa_outlined,
  'work': Icons.work_outline,
};

/// Свои категории человека — регистрируются контроллером после загрузки и изменений (как текущая валюта).
List<FinCategory> _custom = const [];
Set<String> _archived = const {};

void setCustomFinCategories(List<FinCategory> categories, {Set<String> archived = const {}}) {
  _custom = List.unmodifiable(categories);
  _archived = Set.unmodifiable(archived);
}

FinCategory customFinCategory(String id, String name, bool isIncome, String icon) =>
    FinCategory(id, name, isIncome, customCategoryIcons[icon] ?? Icons.sell_outlined);

/// Все категории: встроенные и свои (включая архивные — по ним ищутся старые операции).
List<FinCategory> get allFinCategories => [...kFinCategories, ..._custom];

/// Категории для выбора: встроенные и свои без архивных. [keep] — оставить архивную, если её выбрала уже существующая запись.
List<FinCategory> pickableFinCategories({bool? income, String? keep}) => [
      for (final c in allFinCategories)
        if ((income == null || c.isIncome == income) && (!_archived.contains(c.id) || c.id == keep)) c,
    ];

FinCategory? finCategory(String id) {
  for (final c in kFinCategories) {
    if (c.id == id) return c;
  }
  for (final c in _custom) {
    if (c.id == id) return c;
  }
  return null;
}
