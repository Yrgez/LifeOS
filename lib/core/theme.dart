import 'package:flutter/material.dart';

class AppColors {
  static const green = Color(0xFF00E676);
  static const violet = Color(0xFF7C4DFF);
  static const gold = Color(0xFFFFD700);
  static const red = Color(0xFFFF3D71);
  static const amber = Color(0xFFFFB300);
  static const card = Color(0xFF14181F);
  static const panel = Color(0xFF0D1015);
  static const field = Color(0xFF1E242E);
}

ThemeData buildAppTheme() {
  return ThemeData.dark().copyWith(
    scaffoldBackgroundColor: const Color(0xFF090B0E),
    cardColor: AppColors.card,
    primaryColor: AppColors.green,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.green,
      secondary: AppColors.violet,
      surface: AppColors.card,
    ),
  );
}
