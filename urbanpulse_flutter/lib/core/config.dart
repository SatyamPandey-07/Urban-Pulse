import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Build-time configuration, the Flutter equivalent of the Android
/// `BuildConfig` fields that `app/build.gradle.kts` read out of the gitignored
/// `local.properties`.
///
/// Supports runtime overrides saved in [SharedPreferences]. If a custom override
/// is present, it takes precedence; otherwise, the embedded compile-time value
/// is used.
abstract final class AppConfig {
  static const _embeddedTomTomApiKey = String.fromEnvironment(
    'TOMTOM_API_KEY',
    defaultValue: 'DEMO_TOMTOM_KEY',
  );

  static const _embeddedGroqApiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: 'DEMO_GROQ_KEY',
  );

  static const _centralRegistryFromBuild = String.fromEnvironment('CENTRAL_REGISTRY_BASE_URL');

  /// 10.0.2.2 is the Android emulator's name for the dev machine; a browser
  /// reaches the same server as localhost.
  static String get _embeddedCentralRegistryBaseUrl => _centralRegistryFromBuild.isNotEmpty
      ? _centralRegistryFromBuild
      : (kIsWeb ? 'http://localhost:3001' : 'http://10.0.2.2:3001');

  /// The website's relay for sources that refuse browser requests (the
  /// backend in `server/`). Empty: those sources are simply unavailable on the
  /// website, as when offline.
  static const _webRelayUrl = String.fromEnvironment('WEB_RELAY_URL');

  static String get webRelayUrl => _webRelayUrl.endsWith('/') ? _webRelayUrl.substring(0, _webRelayUrl.length - 1) : _webRelayUrl;

  static const _embeddedTavilyApiKey = String.fromEnvironment('TAVILY_API_KEY');
  static const _embeddedGeoapifyApiKey = String.fromEnvironment('GEOAPIFY_API_KEY');
  static const _embeddedXoteloRapidApiKey = String.fromEnvironment('XOTELO_RAPIDAPI_KEY');

  // --- Preference keys for overrides --------------------------------------
  static const keyOverrideGroq = 'override_groq_api_key';
  static const keyOverrideTomTom = 'override_tomtom_api_key';
  static const keyOverrideTavily = 'override_tavily_api_key';
  static const keyOverrideGeoapify = 'override_geoapify_api_key';
  static const keyOverrideXotelo = 'override_xotelo_rapidapi_key';
  static const keyOverrideCentralRegistry = 'override_central_registry_url';

  static String? _overrideGroqApiKey;
  static String? _overrideTomTomApiKey;
  static String? _overrideTavilyApiKey;
  static String? _overrideGeoapifyApiKey;
  static String? _overrideXoteloRapidApiKey;
  static String? _overrideCentralRegistryBaseUrl;

  /// Loads all stored overrides from [SharedPreferences].
  static Future<void> loadOverrides([SharedPreferences? existingPrefs]) async {
    final prefs = existingPrefs ?? await SharedPreferences.getInstance();
    _overrideGroqApiKey = prefs.getString(keyOverrideGroq);
    _overrideTomTomApiKey = prefs.getString(keyOverrideTomTom);
    _overrideTavilyApiKey = prefs.getString(keyOverrideTavily);
    _overrideGeoapifyApiKey = prefs.getString(keyOverrideGeoapify);
    _overrideXoteloRapidApiKey = prefs.getString(keyOverrideXotelo);
    _overrideCentralRegistryBaseUrl = prefs.getString(keyOverrideCentralRegistry);
  }

  /// Sets or clears an individual override in [SharedPreferences].
  static Future<void> setOverride(String prefKey, String? value) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = value?.trim();
    if (clean == null || clean.isEmpty) {
      await prefs.remove(prefKey);
    } else {
      await prefs.setString(prefKey, clean);
    }
    await loadOverrides(prefs);
  }

  /// Clears every configured override, reverting entirely to embedded keys.
  static Future<void> clearAllOverrides() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyOverrideGroq);
    await prefs.remove(keyOverrideTomTom);
    await prefs.remove(keyOverrideTavily);
    await prefs.remove(keyOverrideGeoapify);
    await prefs.remove(keyOverrideXotelo);
    await prefs.remove(keyOverrideCentralRegistry);
    await loadOverrides(prefs);
  }

  static bool hasOverride(String prefKey) {
    switch (prefKey) {
      case keyOverrideGroq:
        return _overrideGroqApiKey?.isNotEmpty == true;
      case keyOverrideTomTom:
        return _overrideTomTomApiKey?.isNotEmpty == true;
      case keyOverrideTavily:
        return _overrideTavilyApiKey?.isNotEmpty == true;
      case keyOverrideGeoapify:
        return _overrideGeoapifyApiKey?.isNotEmpty == true;
      case keyOverrideXotelo:
        return _overrideXoteloRapidApiKey?.isNotEmpty == true;
      case keyOverrideCentralRegistry:
        return _overrideCentralRegistryBaseUrl?.isNotEmpty == true;
      default:
        return false;
    }
  }

  static String? getOverride(String prefKey) {
    switch (prefKey) {
      case keyOverrideGroq:
        return _overrideGroqApiKey;
      case keyOverrideTomTom:
        return _overrideTomTomApiKey;
      case keyOverrideTavily:
        return _overrideTavilyApiKey;
      case keyOverrideGeoapify:
        return _overrideGeoapifyApiKey;
      case keyOverrideXotelo:
        return _overrideXoteloRapidApiKey;
      case keyOverrideCentralRegistry:
        return _overrideCentralRegistryBaseUrl;
      default:
        return null;
    }
  }

  static bool get hasAnyOverride =>
      (_overrideGroqApiKey?.isNotEmpty == true) ||
      (_overrideTomTomApiKey?.isNotEmpty == true) ||
      (_overrideTavilyApiKey?.isNotEmpty == true) ||
      (_overrideGeoapifyApiKey?.isNotEmpty == true) ||
      (_overrideXoteloRapidApiKey?.isNotEmpty == true) ||
      (_overrideCentralRegistryBaseUrl?.isNotEmpty == true);

  // --- Active key getters (override takes precedence over embedded) ---------

  static String get groqApiKey =>
      (_overrideGroqApiKey?.isNotEmpty == true)
          ? _overrideGroqApiKey!
          : _embeddedGroqApiKey;

  static String get tomtomApiKey =>
      (_overrideTomTomApiKey?.isNotEmpty == true)
          ? _overrideTomTomApiKey!
          : _embeddedTomTomApiKey;

  static String get tavilyApiKey =>
      (_overrideTavilyApiKey?.isNotEmpty == true)
          ? _overrideTavilyApiKey!
          : _embeddedTavilyApiKey;

  static String get geoapifyApiKey =>
      (_overrideGeoapifyApiKey?.isNotEmpty == true)
          ? _overrideGeoapifyApiKey!
          : _embeddedGeoapifyApiKey;

  static String get xoteloRapidApiKey =>
      (_overrideXoteloRapidApiKey?.isNotEmpty == true)
          ? _overrideXoteloRapidApiKey!
          : _embeddedXoteloRapidApiKey;

  static String get centralRegistryBaseUrl =>
      (_overrideCentralRegistryBaseUrl?.isNotEmpty == true)
          ? _overrideCentralRegistryBaseUrl!
          : _embeddedCentralRegistryBaseUrl;

  static String get embeddedGroqApiKey => _embeddedGroqApiKey;
  static String get embeddedTomTomApiKey => _embeddedTomTomApiKey;
  static String get embeddedTavilyApiKey => _embeddedTavilyApiKey;
  static String get embeddedGeoapifyApiKey => _embeddedGeoapifyApiKey;
  static String get embeddedXoteloRapidApiKey => _embeddedXoteloRapidApiKey;
  static String get embeddedCentralRegistryBaseUrl => _embeddedCentralRegistryBaseUrl;

  static bool get hasTomTomKey =>
      tomtomApiKey.isNotEmpty && tomtomApiKey != 'DEMO_TOMTOM_KEY';

  static bool get hasGroqKey =>
      groqApiKey.isNotEmpty && groqApiKey != 'DEMO_GROQ_KEY';

  // --- Multi-agent planner extra key slots -------------------------------
  static const groqApiKey2 = String.fromEnvironment('GROQ_API_KEY_2');
  static const groqApiKey3 = String.fromEnvironment('GROQ_API_KEY_3');
  static const groqApiKey4 = String.fromEnvironment('GROQ_API_KEY_4');

  static const tavilyApiKey2 = String.fromEnvironment('TAVILY_API_KEY_2');
  static const tavilyApiKey3 = String.fromEnvironment('TAVILY_API_KEY_3');

  /// Every real Groq key, active key first. Placeholders and blanks are dropped.
  static List<String> get groqKeys => realKeys([
    groqApiKey,
    groqApiKey2,
    groqApiKey3,
    groqApiKey4,
  ]);

  static List<String> get tavilyKeys =>
      realKeys([tavilyApiKey, tavilyApiKey2, tavilyApiKey3]);

  // --- Supabase: accounts and the traveller's data ---------------------------

  /// The project URL and its public anon (publishable) key. The key is meant
  /// to be shipped in the app: row level security keeps every traveller to
  /// their own rows. The database password never belongs here.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static String get supabaseKey => realKeys([_supabasePublishableKey, _supabaseAnonKey]).firstOrNull ?? '';

  /// Real accounts and cloud storage are on. Without them the app runs on the
  /// device only, as before.
  static bool get hasSupabase => realKeys([supabaseUrl]).isNotEmpty && supabaseKey.isNotEmpty;

  // --- Nugen: the aligned UrbanPulse Travel-Risk model -----------------------

  /// The Nugen API key and the id of the model aligned for UrbanPulse
  /// (`nugen/results/state.json` after `nugen/pipeline.py`). Without both, the
  /// Travel-Risk jobs run on the offline rules.
  static const nugenApiKey = String.fromEnvironment('NUGEN_API_KEY');
  static const nugenModelId = String.fromEnvironment('NUGEN_MODEL_ID');

  static bool get hasNugen => realKeys([nugenApiKey]).isNotEmpty && realKeys([nugenModelId]).isNotEmpty;

  static bool get hasGeoapifyKey => realKeys([geoapifyApiKey]).isNotEmpty;

  static bool get hasXoteloRapidApiKey =>
      realKeys([xoteloRapidApiKey]).isNotEmpty;

  /// Keeps only values that look like a real key: not blank and not one of
  /// the `DEMO_*` defaults or the `your-...-key` placeholders from
  /// `config.example.json`.
  static List<String> realKeys(Iterable<String> candidates) => [
    for (final k in candidates)
      if (k.trim().isNotEmpty &&
          !k.startsWith('DEMO_') &&
          !k.startsWith('your-'))
        k.trim(),
  ];
}
