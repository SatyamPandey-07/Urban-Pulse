import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'responsive.dart';

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
        onPrimary: const Color(0xFF0B1015),
        surface: AppColors.bgDark,
        surfaceContainerLowest: AppColors.bgDark,
        surfaceContainerLow: AppColors.surfaceDark,
        surfaceContainer: AppColors.surfaceCard,
        surfaceContainerHigh: AppColors.surfaceElevated,
        surfaceContainerHighest: AppColors.surfaceElevated,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        outlineVariant: AppColors.surfaceBorder,
        error: AppColors.solidError,
      );
    } else {
      scheme = scheme.copyWith(
        primary: accent.seed,
        onPrimary: Colors.white,
        surface: AppColors.bgLight,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: Colors.white,
        surfaceContainerHigh: const Color(0xFFF1F5F9),
        surfaceContainerHighest: const Color(0xFFE2E8F0),
        onSurface: AppColors.textPrimaryLight,
        onSurfaceVariant: AppColors.textSecondaryLight,
        outlineVariant: AppColors.surfaceLightBorder,
        error: AppColors.solidError,
      );
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Pushed screens sit centred at a readable width on wide windows.
      pageTransitionsTheme: WidePageTransitionsBuilder.theme(),
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
        color: isDark ? AppColors.surfaceCard : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark
                ? AppColors.surfaceBorder.withValues(alpha: 0.8)
                : AppColors.surfaceLightBorder,
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.20 : 0.12),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: scheme.primary, size: 24);
          }
          return IconThemeData(
            color: isDark ? AppColors.textSecondary : const Color(0xFF94A3B8),
            size: 22,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            );
          }
          return TextStyle(
            color: isDark ? AppColors.textSecondary : const Color(0xFF64748B),
            fontWeight: FontWeight.w500,
            fontSize: 11,
          );
        }),
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
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
