import 'package:flutter/material.dart';

/// Central color palette for the app.
/// Change these two constants to retheme bars and primary buttons everywhere.
class AppColors {
  AppColors._();

  /// Background color for all app bars and the TTS control bar.
  static const Color barColor = Color(0xFF221177);

  /// Fill color for primary action buttons (FilledButton / ElevatedButton).
  static const Color primaryColor = Color(0xFF5577FF);

  /// Foreground color used on top of [barColor] and [primaryColor].
  static const Color onBar = Colors.white;
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
