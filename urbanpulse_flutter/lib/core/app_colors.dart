import 'package:flutter/material.dart';

/// Direct port of `res/values/colors.xml`. The screens that deliberately paint a
/// fixed semantic colour (the green/red dual-route cards, ranked-option badges,
/// the SOS button) reference these rather than the theme, exactly as the
/// original layouts did.
abstract final class AppColors {
  // Signature Emerald Palette (Greenish Premium Look).
  static const primaryGreen = Color(0xFF059669); // Rich emerald green
  static const primaryGreenAccent = Color(0xFF10B981); // Radiant emerald
  static const primaryGreenDark = Color(0xFF047857); // Deep forest green
  static const primaryGreenForest = Color(0xFF064E3B); // Obsidian forest
  static const primaryGreenMint = Color(0xFF34D399); // Soft mint glow
  static const primaryGreenLight = Color(0xFFE6F7F0); // Soft mint pill background
  static const primaryGreenGlow = Color(0x3310B981); // Emerald shadow glow

  // Legacy accents kept for backward compatibility (all anchored to green harmony).
  static const primaryBlue = Color(0xFF2563EB);
  static const primaryIndigo = Color(0xFF6366F1);
  static const primaryPurple = Color(0xFF8B5CF6);
  static const primaryOrange = Color(0xFFF97316);
  static const primaryPink = Color(0xFFEC4899);
  static const primaryTeal = Color(0xFF0D9488);

  // Light surface hierarchy (Clean pearl & sage).
  static const bgLight = Color(0xFFF8FAFC);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceLightBorder = Color(0xFFE2E8F0);
  static const textPrimaryLight = Color(0xFF0F172A);
  static const textSecondaryLight = Color(0xFF64748B);

  // Dark surface hierarchy (obsidian slate with subtle emerald undertone).
  static const bgDark = Color(0xFF0A0F14);
  static const surfaceDark = Color(0xFF111822);
  static const surfaceCard = Color(0xFF16202C);
  static const surfaceBorder = Color(0xFF233242);
  static const surfaceElevated = Color(0xFF1D2A3A);

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
  static const sosRed = Color(0xFFFF4B4B);
  static const sosDeepRed = Color(0xFFDC2626);
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
