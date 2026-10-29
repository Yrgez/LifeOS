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

FinCategory? finCategory(String id) {
  for (final c in kFinCategories) {
    if (c.id == id) return c;
  }
  return null;
}
