import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Session state for the login / sign-up / demo flows.
///
/// The Kotlin app kept the same three `app_prefs` keys and gated navigation on
/// them; a Firebase `AuthManager` existed alongside but every screen treated it
/// as best-effort and fell back to these local values, so the *observable*
/// behaviour lived here. See the migration notes in README for what a real
/// Firebase backend would need.
class AuthController extends ChangeNotifier {
  AuthController(this._prefs);

  static const _keyEmail = 'app_prefs.user_email';
  static const _keyName = 'app_prefs.user_name';
  static const _keyLoggedIn = 'app_prefs.is_logged_in';

  /// The demo identity used by the 1-tap judge/guest access buttons.
  static const demoEmail = 'demo.traveler@urbanpulse.ai';
  static const demoPassword = 'urbanpulse2026';

  final SharedPreferences _prefs;

  bool get isLoggedIn => _prefs.getBool(_keyLoggedIn) ?? false;

  String get userEmail => _prefs.getString(_keyEmail) ?? '';

  String get userName => _prefs.getString(_keyName) ?? '';

  /// Mirrors `LoginActivity`'s validation: the seeded admin account, a
  /// previously registered email, or any well-formed email with a 6+ character
  /// password.
  bool validateCredentials(String email, String password) {
    final savedEmail = userEmail;
    return (email == 'admin@123.com' && password == 'password') ||
        (savedEmail.isNotEmpty && email == savedEmail) ||
        (email.contains('@') && password.length >= 6);
  }

  Future<void> signIn(String email) async {
    await _prefs.setString(_keyEmail, email);
    await _prefs.setBool(_keyLoggedIn, true);
    notifyListeners();
  }

  Future<void> signUp({required String fullName, required String email}) async {
    await _prefs.setString(_keyName, fullName);
    await _prefs.setString(_keyEmail, email);
    await _prefs.setBool(_keyLoggedIn, true);
    notifyListeners();
  }

  Future<void> signOut() async {
    await _prefs.setBool(_keyLoggedIn, false);
    notifyListeners();
  }

  /// A stable per-device traveler name for real bookings — no server-side login
  /// system exists, so this is a persisted pseudonymous identifier (not a
  /// fabricated one-off), reused across sessions.
  Future<String> getOrCreateTravelerName() async {
    const key = 'urbanpulse_traveler.traveler_name';
    final existing = _prefs.getString(key);
    if (existing != null) return existing;
    final shortId = DateTime.now().microsecondsSinceEpoch
        .toRadixString(36)
        .toUpperCase();
    final name = 'Traveler-${shortId.substring(shortId.length - 6)}';
    await _prefs.setString(key, name);
    return name;
  }
}
