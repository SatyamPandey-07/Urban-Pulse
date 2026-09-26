import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_colors.dart';

/// Persists the selected accent, the way `ThemeUtils.saveThemeColor` /
/// `applyTheme` swapped between the six `Theme.Urbanpulse.<Accent>` styles.
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs)
    : _accent = AccentColor.fromKey(_prefs.getString(_keyThemeColor));

  static const _keyThemeColor = 'app_prefs.theme_color';

  final SharedPreferences _prefs;
  AccentColor _accent;

  AccentColor get accent => _accent;

  Future<void> setAccent(AccentColor accent) async {
    if (_accent == accent) return;
    _accent = accent;
    await _prefs.setString(_keyThemeColor, accent.key);
    notifyListeners();
  }
}
