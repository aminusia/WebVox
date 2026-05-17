import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  static const Color surfaceDark = Color(0xFF111320);

  /// Reader background
  static const Color readerBackground = Color(0xFF0D1020);

  /// Accent highlight
  static const Color accent = Color(0xFF7A5CFF);
}

/// Consistent radius scale used across the app.
class AppRadius {
  AppRadius._();

  static const double card = 24;
  static const double button = 20;
  static const double input = 24;
  static const double dialog = 28;
  static const double playbackBar = 24;
}

class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primaryColor,
      brightness: brightness,
    ).copyWith(primary: AppColors.primaryColor);

    const inputRadius = BorderRadius.all(Radius.circular(AppRadius.input));
    final manropeFontFamily = GoogleFonts.manrope().fontFamily;

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      fontFamily: manropeFontFamily,
      textTheme:
          isDark
              ? GoogleFonts.manropeTextTheme(
                ThemeData.dark().textTheme,
              ).copyWith(
                bodyLarge: GoogleFonts.manrope(
                  textStyle: const TextStyle(
                    color: Color(0xFFE7E9F4),
                    height: 1.7,
                  ),
                ),
                bodyMedium: GoogleFonts.manrope(
                  textStyle: const TextStyle(color: Color(0xFFD7DCF7)),
                ),
              )
              : GoogleFonts.manropeTextTheme(ThemeData.light().textTheme),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(18),
        thickness: 1,
        space: 1,
      ),
      cardTheme: const CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.barColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.dialog)),
        ),
        titleTextStyle: GoogleFonts.manrope(
          textStyle: const TextStyle(
            color: AppColors.onBar,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        contentTextStyle: GoogleFonts.manrope(
          textStyle: const TextStyle(color: AppColors.onBar),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.barColor,
        foregroundColor: AppColors.onBar,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        toolbarHeight: 64,
        titleSpacing: 16,
        iconTheme: IconThemeData(color: AppColors.onBar, size: 22),
        actionsIconTheme: IconThemeData(color: AppColors.onBar, size: 22),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: AppColors.onBar,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: AppColors.onBar,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.button)),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1A1D33) : base.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(
            color:
                isDark
                    ? Colors.white.withAlpha(20)
                    : Colors.black.withAlpha(20),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(
            color:
                isDark
                    ? Colors.white.withAlpha(20)
                    : Colors.black.withAlpha(20),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: base.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: base.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: inputRadius,
          borderSide: BorderSide(color: base.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      sliderTheme: const SliderThemeData(trackHeight: 4),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primaryColor;
          }
          return null;
        }),
      ),
    );
  }
}
