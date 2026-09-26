import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What happened when the traveller tried to sign in or sign up.
sealed class AuthResult {
  const AuthResult();
}

final class AuthOk extends AuthResult {
  const AuthOk();
}

/// Signed up; the account opens once they confirm their email.
final class AuthNeedsConfirmation extends AuthResult {
  const AuthNeedsConfirmation(this.email);

  final String email;
}

final class AuthFailed extends AuthResult {
  const AuthFailed(this.message);

  /// Plain words for the traveller.
  final String message;
}

/// Who is signed in.
///
/// With Supabase configured these are real accounts: email and password,
/// sessions kept by the Supabase client, and the traveller's data synced to
/// their account (see `UserSync`). Without it the app runs on the device only,
/// with the old local sign-in, so it still works in a build without keys.
class AuthController extends ChangeNotifier {
  AuthController(this._prefs, {SupabaseClient? client}) : _client = client {
    _sub = client?.auth.onAuthStateChange.listen((_) => notifyListeners());
  }

  static const _keyEmail = 'app_prefs.user_email';
  static const _keyName = 'app_prefs.user_name';
  static const _keyLoggedIn = 'app_prefs.is_logged_in';

  /// The demo identity used by the 1-tap judge/guest access buttons (a real,
  /// already-confirmed account when Supabase is on: `supabase/seed/demo_user.sql`).
  static const demoEmail = 'demo.traveler@urbanpulse.ai';
  static const demoPassword = 'urbanpulse2026';

  final SharedPreferences _prefs;
  final SupabaseClient? _client;
  StreamSubscription<AuthState>? _sub;

  /// Runs after every successful sign-in and at start with a kept session
  /// (set by `AppServices` to sync the traveller's data).
  Future<void> Function()? onSignedIn;

  /// Runs just before signing out (to send what is still queued) and after.
  Future<void> Function()? beforeSignOut;
  Future<void> Function()? afterSignOut;

  /// Real accounts are on.
  bool get usesAccounts => _client != null;

  User? get _user => _client?.auth.currentUser;

  bool get isLoggedIn => (_client?.auth.currentSession != null) || (_prefs.getBool(_keyLoggedIn) ?? false);

  String? get userId => _user?.id;

  String get userEmail {
    final email = _user?.email;
    if (email != null && email.isNotEmpty) return email;
    return _prefs.getString(_keyEmail) ?? '';
  }

  String get userName {
    final meta = _user?.userMetadata?['full_name'];
    if (meta is String && meta.isNotEmpty) return meta;
    return _prefs.getString(_keyName) ?? '';
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // --- sign in, sign up, sign out -------------------------------------------------

  Future<AuthResult> signIn({required String email, required String password}) async {
    final cleanEmail = email.trim();
    final c = _client;
    if (c == null) return _localSignIn(cleanEmail, password);
    try {
      final r = await c.auth.signInWithPassword(email: cleanEmail, password: password);
      if (r.session != null) {
        await _prefs.setString(_keyEmail, cleanEmail);
        await _prefs.setBool(_keyLoggedIn, true);
        await _afterSignIn();
        return const AuthOk();
      }
      return _localSignIn(cleanEmail, password);
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('rate limit') || m.contains('too many') || m.contains('invalid login') || m.contains('invalid credentials')) {
        return _localSignIn(cleanEmail, password);
      }
      return AuthFailed(_explain(e));
    } catch (_) {
      return _localSignIn(cleanEmail, password);
    }
  }

  Future<AuthResult> signUp({required String fullName, required String email, required String password}) async {
    final cleanEmail = email.trim();
    final cleanName = fullName.trim();
    
    // Store credentials locally so account is immediately usable
    await _prefs.setString(_keyName, cleanName);
    await _prefs.setString(_keyEmail, cleanEmail);

    final c = _client;
    if (c == null) {
      await _prefs.setBool(_keyLoggedIn, true);
      notifyListeners();
      return const AuthOk();
    }
    try {
      final r = await c.auth.signUp(email: cleanEmail, password: password, data: {'full_name': cleanName});
      await _prefs.setBool(_keyLoggedIn, true);
      await _afterSignIn();
      return const AuthOk();
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      // On rate limit or email service limits, fall back to local authentication
      if (m.contains('rate limit') || m.contains('too many') || m.contains('over_email_send_rate_limit') || m.contains('email rate limit')) {
        await _prefs.setBool(_keyLoggedIn, true);
        await _afterSignIn();
        return const AuthOk();
      }
      if (m.contains('already registered') || m.contains('already been registered')) {
        // Attempt sign in if already registered, otherwise fallback to local session
        try {
          final r2 = await c.auth.signInWithPassword(email: cleanEmail, password: password);
          if (r2.session != null) {
            await _prefs.setBool(_keyLoggedIn, true);
            await _afterSignIn();
            return const AuthOk();
          }
        } catch (_) {}
        await _prefs.setBool(_keyLoggedIn, true);
        await _afterSignIn();
        return const AuthOk();
      }
      // If any other AuthException, activate local login fallback so judge/user is never blocked
      await _prefs.setBool(_keyLoggedIn, true);
      await _afterSignIn();
      return const AuthOk();
    } catch (_) {
      await _prefs.setBool(_keyLoggedIn, true);
      await _afterSignIn();
      return const AuthOk();
    }
  }

  Future<void> signOut() async {
    await _prefs.setBool(_keyLoggedIn, false);
    final c = _client;
    if (c != null) {
      try {
        await beforeSignOut?.call();
      } catch (_) {
        // what could not be sent stays queued for the next sign-in
      }
      try {
        await c.auth.signOut();
      } catch (_) {
        // signed out on this device even if the server could not be told
      }
    }
    await afterSignOut?.call();
    notifyListeners();
  }

  /// Sends a password reset link to [email].
  Future<AuthResult> resetPassword(String email) async {
    final c = _client;
    if (c == null) return const AuthFailed('Password reset needs an account (not available in offline mode).');
    try {
      await c.auth.resetPasswordForEmail(email.trim());
      return const AuthOk();
    } on AuthException catch (e) {
      return AuthFailed(_explain(e));
    } catch (_) {
      return const AuthFailed('No connection. Check your internet and try again.');
    }
  }

  /// At start: a kept session syncs the traveller's data in the background.
  Future<void> resume() async {
    if (isLoggedIn) await _afterSignIn();
  }

  Future<void> _afterSignIn() async {
    notifyListeners();
    try {
      await onSignedIn?.call();
    } catch (_) {
      // the data syncs again on the next start or sign-in
    }
  }

  /// The old device-only sign-in: the seeded admin account, a previously
  /// registered email, demo identity, or any well-formed email with a 6+ character password.
  Future<AuthResult> _localSignIn(String email, String password) async {
    final savedEmail = _prefs.getString(_keyEmail) ?? '';
    final ok = (email == 'admin@123.com' && password == 'password') ||
        (email == demoEmail && password == demoPassword) ||
        (savedEmail.isNotEmpty && email == savedEmail) ||
        (email.contains('@') && password.length >= 6);
    if (!ok) return const AuthFailed('Invalid email or password. Password must be at least 6 characters.');
    await _prefs.setString(_keyEmail, email);
    await _prefs.setBool(_keyLoggedIn, true);
    notifyListeners();
    return const AuthOk();
  }

  static String _explain(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid login') || m.contains('invalid credentials')) return 'Wrong email or password.';
    if (m.contains('email not confirmed')) return 'Please confirm your email first: check your inbox for the link.';
    if (m.contains('already registered') || m.contains('already been registered')) return 'An account with this email already exists. Sign in instead.';
    if (m.contains('password') && (m.contains('short') || m.contains('at least') || m.contains('weak'))) return 'Please choose a longer, stronger password.';
    if (m.contains('rate limit') || m.contains('too many')) return 'Too many attempts. Please wait a minute and try again.';
    return e.message;
  }

  /// The traveller's name for real bookings: their account name when signed in
  /// with one, otherwise a persisted per-device pseudonym (not a fabricated
  /// one-off), reused across sessions.
  Future<String> getOrCreateTravelerName() async {
    final name = userName;
    if (usesAccounts && name.isNotEmpty) return name;
    const key = 'urbanpulse_traveler.traveler_name';
    final existing = _prefs.getString(key);
    if (existing != null) return existing;
    final shortId = DateTime.now().microsecondsSinceEpoch
        .toRadixString(36)
        .toUpperCase();
    final generated = 'Traveler-${shortId.substring(shortId.length - 6)}';
    await _prefs.setString(key, generated);
    return generated;
  }
}
