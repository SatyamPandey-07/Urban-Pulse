import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_colors.dart';

/// Persists the selected ThemeMode (Light / Dark / System) with the signature
/// Emerald Greenish premium look across the app.
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs)
      : _accent = AccentColor.fromKey(_prefs.getString(_keyThemeColor)),
        _themeMode = _parseThemeMode(_prefs.getString(_keyThemeMode));

  static const _keyThemeColor = 'app_prefs.theme_color';
  static const _keyThemeMode = 'app_prefs.theme_mode';

  final SharedPreferences _prefs;
  AccentColor _accent;
  ThemeMode _themeMode;

  AccentColor get accent => _accent;
  ThemeMode get themeMode => _themeMode;

  static ThemeMode _parseThemeMode(String? value) {
    if (value == 'light') return ThemeMode.light;
    if (value == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _prefs.setString(
      _keyThemeMode,
      mode == ThemeMode.light
          ? 'light'
          : mode == ThemeMode.dark
              ? 'dark'
              : 'system',
    );
    notifyListeners();
  }

  Future<void> setAccent(AccentColor accent) async {
    if (_accent == accent) return;
    _accent = accent;
    await _prefs.setString(_keyThemeColor, accent.key);
    notifyListeners();
  }
}
