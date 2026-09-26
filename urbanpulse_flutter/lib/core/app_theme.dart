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
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primary.withValues(alpha: 0.22),
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primary.withValues(alpha: 0.22),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        labelStyle: TextStyle(color: scheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
