import 'package:flutter/material.dart';

/// Категория операции. Набор фиксированный: тип операции (доход/расход) определяется категорией.
class FinCategory {
  final String id;
  final String name;
  final bool isIncome;
  final IconData icon;
  final Color color;
  const FinCategory(this.id, this.name, this.isIncome, this.icon, this.color);
}

const List<FinCategory> kFinCategories = [
  // расходы
  FinCategory('housing', 'Жильё', false, Icons.home, Color(0xFF7C4DFF)),
  FinCategory('food', 'Еда', false, Icons.restaurant, Color(0xFFFFB300)),
  FinCategory('transport', 'Транспорт', false, Icons.directions_car, Color(0xFF18FFFF)),
  FinCategory('health', 'Здоровье', false, Icons.favorite, Color(0xFFFF3D71)),
  FinCategory('fun', 'Развлечения', false, Icons.sports_esports, Color(0xFFE040FB)),
  FinCategory('shopping', 'Покупки', false, Icons.shopping_bag, Color(0xFF448AFF)),
  FinCategory('subs', 'Подписки', false, Icons.autorenew, Color(0xFF64FFDA)),
  FinCategory('other_exp', 'Прочее', false, Icons.more_horiz, Color(0xFF90A4AE)),
  // доходы
  FinCategory('salary', 'Зарплата', true, Icons.work, Color(0xFF00E676)),
  FinCategory('side', 'Подработка', true, Icons.handyman, Color(0xFFB2FF59)),
  FinCategory('invest', 'Проценты и инвестиции', true, Icons.trending_up, Color(0xFFFFD700)),
  FinCategory('other_inc', 'Прочее', true, Icons.more_horiz, Color(0xFF90A4AE)),
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

/// Цвет своих категорий — нейтральный: цвет в интерфейсе только со смыслом, а «своя категория» смысла цвета не несёт.
const _customColor = Color(0xFF90A4AE);

/// Свои категории человека — регистрируются контроллером после загрузки и изменений (как текущая валюта).
List<FinCategory> _custom = const [];
Set<String> _archived = const {};

void setCustomFinCategories(List<FinCategory> categories, {Set<String> archived = const {}}) {
  _custom = List.unmodifiable(categories);
  _archived = Set.unmodifiable(archived);
}

FinCategory customFinCategory(String id, String name, bool isIncome, String icon) =>
    FinCategory(id, name, isIncome, customCategoryIcons[icon] ?? Icons.sell_outlined, _customColor);

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
