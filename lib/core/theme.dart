import 'package:flutter/material.dart';

/// Палитра: практичный минимализм — чёрный фон, тёмно-серые плитки, белые акценты.
/// Цвет остаётся только там, где несёт смысл: измерения жизни, доход/расход, предупреждения.
class AppColors {
  // смысловые цвета (не для украшения)
  static const green = Color(0xFF00E676);
  static const violet = Color(0xFF7C4DFF);
  static const violetText = Color(0xFFA78BFF); // фиолетовый для текста: контраст на плитке 6.8:1 (violet — лишь 3.8:1)
  static const gold = Color(0xFFFFD700);
  static const red = Color(0xFFFF3D71);
  static const amber = Color(0xFFFFB300);

  // поверхности
  static const background = Color(0xFF000000);
  static const card = Color(0xFF141416); // плитки
  static const panel = Color(0xFF000000); // шапки экранов сливаются с фоном
  static const raised = Color(0xFF1C1C1E); // плавающая панель, меню, тосты
  static const field = Color(0xFF0B0B0C); // поля ввода
  static const border = Color(0x14FFFFFF); // 8% белого — тонкая рамка плиток

  // текст и акцент
  static const text = Color(0xFFF2F2F2);
  static const muted = Color(0xFF9A9AA0); // второстепенный текст (контраст на #141416 > 4.5:1)
  static const accent = Color(0xFFF2F2F2); // главное действие — белое
}

/// Радиусы: плитки 28, поля 18, панели снизу 36.
class AppRadii {
  static const tile = 28.0;
  static const field = 18.0;
  static const sheet = 36.0;
}

/// Плитка в стиле макета: тёмно-серая, скруглённая, с тонкой рамкой.
BoxDecoration tileDecoration({double radius = AppRadii.tile, Color color = AppColors.card}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.border),
    );

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.black,
    secondary: AppColors.violet,
    surface: AppColors.card,
    onSurface: AppColors.text,
    error: AppColors.red,
  );
  const pill = StadiumBorder();
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadii.field),
    borderSide: const BorderSide(color: Color(0x1FFFFFFF)),
  );
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    cardColor: AppColors.card,
    primaryColor: AppColors.accent,
    dividerColor: const Color(0x1AFFFFFF),
    // Волна нажатия без шейдера. InkSparkle (по умолчанию в Material 3 на Android) рисуется фрагментным шейдером
    // с «зерном»; на части GPU (Mali, Galaxy S10) он оставляет полосы шума и битые буквы до перерисовки экрана.
    splashFactory: InkRipple.splashFactory,
    textTheme: base.textTheme.apply(fontFamily: 'Inter', bodyColor: AppColors.text, displayColor: AppColors.text),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Inter'),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        shape: pill,
        elevation: 0,
        minimumSize: const Size(0, 48),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: Color(0x1FFFFFFF)),
        shape: pill,
        minimumSize: const Size(0, 48),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.text)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.black,
      shape: pill,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.field,
      labelStyle: const TextStyle(color: AppColors.muted),
      hintStyle: const TextStyle(color: AppColors.muted),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(borderSide: const BorderSide(color: AppColors.text)),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: pill,
      side: const BorderSide(color: Color(0x1FFFFFFF)),
      backgroundColor: Colors.transparent,
      selectedColor: const Color(0xFF3A3A3E),
      checkmarkColor: AppColors.text,
      labelStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.text),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadii.tile))),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Color(0xFF3A3A3E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet))),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.raised,
      contentTextStyle: TextStyle(fontFamily: 'Inter', color: AppColors.text),
      actionTextColor: AppColors.text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent, linearTrackColor: Color(0xFF2A2A2E)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.black : AppColors.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.accent : const Color(0xFF2A2A2E)),
    ),
  );
}
