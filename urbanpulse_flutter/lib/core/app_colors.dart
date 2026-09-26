import 'package:flutter/material.dart';

/// Direct port of `res/values/colors.xml`. The screens that deliberately paint a
/// fixed semantic colour (the green/red dual-route cards, ranked-option badges,
/// the SOS button) reference these rather than the theme, exactly as the
/// original layouts did.
abstract final class AppColors {
  // Base solid palette (accent options).
  static const primaryGreen = Color(0xFF10B981);
  static const primaryGreenDark = Color(0xFF059669);
  static const primaryBlue = Color(0xFF38BDF8);
  static const primaryIndigo = Color(0xFF6366F1);
  static const primaryPurple = Color(0xFF8B5CF6);
  static const primaryOrange = Color(0xFFF97316);
  static const primaryPink = Color(0xFFEC4899);
  static const primaryTeal = Color(0xFF14B8A6);

  // Dark surface hierarchy (solid slate palette).
  static const bgDark = Color(0xFF0F172A);
  static const surfaceDark = Color(0xFF1E293B);
  static const surfaceCard = Color(0xFF1E293B);
  static const surfaceBorder = Color(0xFF334155);
  static const surfaceElevated = Color(0xFF334155);

  // Status & semantic solids.
  static const solidError = Color(0xFFEF4444);
  static const solidWarning = Color(0xFFF59E0B);
  static const solidSuccess = Color(0xFF10B981);
  static const solidInfo = Color(0xFF38BDF8);

  // High-legibility typography.
  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFF94A3B8);
  static const textTertiary = Color(0xFF64748B);

  /// SOS button gradient (`bg_sos_gradient.xml`).
  static const sosRed = Color(0xFFFF5252);
  static const sosDeepRed = Color(0xFFD32F2F);
}

/// The six accent themes from `styles.xml` (`Theme.Urbanpulse.<Accent>`).
enum AccentColor {
  green('green', AppColors.primaryGreen),
  blue('blue', AppColors.primaryBlue),
  purple('purple', AppColors.primaryPurple),
  orange('orange', AppColors.primaryOrange),
  pink('pink', AppColors.primaryPink),
  teal('teal', AppColors.primaryTeal);

  const AccentColor(this.key, this.seed);

  final String key;
  final Color seed;

  static AccentColor fromKey(String? key) => AccentColor.values.firstWhere(
    (a) => a.key == key,
    orElse: () => AccentColor.green,
  );
}
