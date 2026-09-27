import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'responsive.dart';

/// Material 3 day/night themes with a signature Emerald Greenish luxury look,
/// powered by Plus Jakarta Sans typography and refined surface hierarchies.
abstract final class AppTheme {
  static ThemeData light([AccentColor accent = AccentColor.green]) =>
      _build(accent, Brightness.light);

  static ThemeData dark([AccentColor accent = AccentColor.green]) =>
      _build(accent, Brightness.dark);

  static ThemeData _build(AccentColor accent, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    const emeraldPrimary = AppColors.primaryGreenAccent; // #10B981
    const emeraldDark = AppColors.primaryGreenDark; // #047857

    var scheme = ColorScheme.fromSeed(
      seedColor: emeraldPrimary,
      brightness: brightness,
    );

    if (isDark) {
      scheme = scheme.copyWith(
        primary: emeraldPrimary,
        onPrimary: const Color(0xFF042F22),
        primaryContainer: const Color(0xFF064E3B),
        onPrimaryContainer: const Color(0xFFA7F3D0),
        secondary: AppColors.primaryGreenMint,
        onSecondary: const Color(0xFF064E3B),
        secondaryContainer: const Color(0xFF065F46),
        onSecondaryContainer: const Color(0xFFD1FAE5),
        surface: AppColors.bgDark,
        surfaceContainerLowest: AppColors.bgDark,
        surfaceContainerLow: AppColors.surfaceDark,
        surfaceContainer: AppColors.surfaceCard,
        surfaceContainerHigh: AppColors.surfaceElevated,
        surfaceContainerHighest: const Color(0xFF223244),
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        outline: const Color(0xFF334155),
        outlineVariant: AppColors.surfaceBorder,
        error: AppColors.solidError,
      );
    } else {
      scheme = scheme.copyWith(
        primary: emeraldDark,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFD1FAE5),
        onPrimaryContainer: const Color(0xFF064E3B),
        secondary: const Color(0xFF0D9488),
        onSecondary: Colors.white,
        secondaryContainer: const Color(0xFFCCFBF1),
        onSecondaryContainer: const Color(0xFF115E59),
        surface: AppColors.bgLight,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.white,
        surfaceContainer: Colors.white,
        surfaceContainerHigh: const Color(0xFFF1F5F9),
        surfaceContainerHighest: const Color(0xFFE2E8F0),
        onSurface: AppColors.textPrimaryLight,
        onSurfaceVariant: AppColors.textSecondaryLight,
        outline: const Color(0xFFCBD5E1),
        outlineVariant: AppColors.surfaceLightBorder,
        error: AppColors.solidError,
      );
    }

    // Google Fonts Plus Jakarta Sans typography base
    final baseTextTheme = isDark
        ? ThemeData.dark(useMaterial3: true).textTheme
        : ThemeData.light(useMaterial3: true).textTheme;
    final textTheme = GoogleFonts.plusJakartaSansTextTheme(baseTextTheme).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: textTheme.copyWith(
        displayLarge: textTheme.displayLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.0),
        displayMedium: textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
        displaySmall: textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        headlineLarge: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        headlineMedium: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        headlineSmall: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
        titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        titleSmall: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: textTheme.bodyLarge?.copyWith(letterSpacing: 0.1),
        bodyMedium: textTheme.bodyMedium?.copyWith(letterSpacing: 0.1),
        bodySmall: textTheme.bodySmall?.copyWith(letterSpacing: 0.1),
        labelLarge: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
        labelMedium: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
        labelSmall: textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.3),
      ),
      pageTransitionsTheme: WidePageTransitionsBuilder.theme(),
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.surfaceCard : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark
                ? AppColors.surfaceBorder.withValues(alpha: 0.85)
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
              fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
              color: scheme.primary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            );
          }
          return TextStyle(
            fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
            color: isDark ? AppColors.textSecondary : const Color(0xFF64748B),
            fontWeight: FontWeight.w600,
            fontSize: 11,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : scheme.surfaceContainerLow,
        selectedColor: scheme.primary.withValues(alpha: 0.18),
        side: BorderSide(
          color: isDark
              ? AppColors.surfaceBorder.withValues(alpha: 0.85)
              : scheme.outlineVariant.withValues(alpha: 0.7),
          width: 1,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: TextStyle(
          fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
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
          textStyle: TextStyle(
            fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        highlightElevation: 5,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.surfaceCard : Colors.white,
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
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.surfaceCard : Colors.white,
        modalBackgroundColor: isDark ? AppColors.surfaceCard : Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        elevation: 12,
      ),
      dividerTheme: DividerThemeData(
        color: isDark
            ? AppColors.surfaceBorder.withValues(alpha: 0.6)
            : scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.surfaceElevated : const Color(0xFF0F172A),
        contentTextStyle: TextStyle(
          fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
