import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Material 3 day/night themes, seeded from the selected accent — the Flutter
/// equivalent of `Theme.Material3.DayNight.NoActionBar` plus the six
/// `Theme.Urbanpulse.<Accent>` overlays.
abstract final class AppTheme {
  static ThemeData light(AccentColor accent) =>
      _build(accent, Brightness.light);

  static ThemeData dark(AccentColor accent) => _build(accent, Brightness.dark);

  static ThemeData _build(AccentColor accent, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    var scheme = ColorScheme.fromSeed(
      seedColor: accent.seed,
      brightness: brightness,
    );

    if (isDark) {
      // Pin the dark surfaces to the app's slate palette so the migrated screens
      // keep the exact backgrounds the XML layouts painted.
      scheme = scheme.copyWith(
        primary: accent.seed,
        surface: AppColors.bgDark,
        surfaceContainerLowest: AppColors.bgDark,
        surfaceContainerLow: AppColors.surfaceDark,
        surfaceContainer: AppColors.surfaceDark,
        surfaceContainerHigh: AppColors.surfaceElevated,
        surfaceContainerHighest: AppColors.surfaceElevated,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        outlineVariant: AppColors.surfaceBorder,
        error: AppColors.solidError,
      );
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.surfaceCard : scheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark
                ? AppColors.surfaceBorder.withValues(alpha: 0.8)
                : scheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : scheme.surfaceContainerLow,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : scheme.surfaceContainerLow,
        selectedColor: scheme.primary.withValues(alpha: 0.18),
        side: BorderSide(
          color: isDark
              ? AppColors.surfaceBorder.withValues(alpha: 0.8)
              : scheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? AppColors.surfaceDark
            : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark ? AppColors.surfaceBorder : scheme.outlineVariant,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: isDark
                ? AppColors.surfaceBorder
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        elevation: 8,
      ),
      dividerTheme: DividerThemeData(
        color: isDark
            ? AppColors.surfaceBorder.withValues(alpha: 0.6)
            : scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
