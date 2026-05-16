import 'package:flutter/material.dart';

/// Central color palette for the app.
/// Change these two constants to retheme bars and primary buttons everywhere.
class AppColors {
  AppColors._();

  /// App bar / playback bar
  static const Color barColor = Color(0xFF1B1464);

  /// Primary interactive color
  static const Color primaryColor = Color(0xFF5B7FFF);

  /// Main titles / branding
  static const Color titleColor = Color(0xFFE8EFFF);

  /// Secondary readable text
  static const Color bodyColor = Color(0xFFD7DCF7);

  /// Foreground on dark surfaces
  static const Color onBar = Colors.white;

  /// Background (dark mode)
  static const Color backgroundDark = Color(0xFF090B18);

  /// Surface cards
  static const Color surfaceDark = Color(0xFF12152A);

  /// Reader background
  static const Color readerBackground = Color(0xFF0D1020);

  /// Accent highlight
  static const Color accent = Color(0xFF7A5CFF);
}

class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primaryColor,
      brightness: brightness,
    ).copyWith(primary: AppColors.primaryColor);

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.barColor,
        titleTextStyle: TextStyle(
          color: AppColors.onBar,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(color: AppColors.onBar),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.barColor,
        foregroundColor: AppColors.onBar,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        iconTheme: IconThemeData(color: AppColors.onBar),
        actionsIconTheme: IconThemeData(color: AppColors.onBar),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: AppColors.onBar,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: AppColors.onBar,
        ),
      ),
    );
  }
}
