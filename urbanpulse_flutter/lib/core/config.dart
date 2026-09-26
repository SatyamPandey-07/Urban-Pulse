/// Build-time configuration, the Flutter equivalent of the Android
/// `BuildConfig` fields that `app/build.gradle.kts` read out of the gitignored
/// `local.properties`.
///
/// Nothing here is a real key: values come from `--dart-define` (or
/// `--dart-define-from-file=config.json`, see `config.example.json`). The
/// placeholder defaults match the Android ones so the same "is this configured?"
/// checks keep working, and every caller degrades gracefully when a key is
/// absent instead of failing.
abstract final class AppConfig {
  static const tomtomApiKey = String.fromEnvironment(
    'TOMTOM_API_KEY',
    defaultValue: 'DEMO_TOMTOM_KEY',
  );

  static const groqApiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: 'DEMO_GROQ_KEY',
  );

  /// 10.0.2.2 is the Android emulator's alias for the host machine's localhost —
  /// it reaches `server/` running on the dev machine out of the box. A physical
  /// device needs the host's LAN IP instead.
  static const centralRegistryBaseUrl = String.fromEnvironment(
    'CENTRAL_REGISTRY_BASE_URL',
    defaultValue: 'http://10.0.2.2:3001',
  );

  static bool get hasTomTomKey =>
      tomtomApiKey.isNotEmpty && tomtomApiKey != 'DEMO_TOMTOM_KEY';

  static bool get hasGroqKey =>
      groqApiKey.isNotEmpty && groqApiKey != 'DEMO_GROQ_KEY';

  // --- Multi-agent planner (phase 2) -------------------------------------
  //
  // The agents share a small pool of Groq keys so parallel workers do not trip
  // one key's rate limit. Slot 1 is `GROQ_API_KEY`; slots 2-4 are optional
  // extras. The planner spreads agents across whichever slots are set (2-3
  // agents per key) and falls back to sharing when there are fewer keys.

  static const groqApiKey2 = String.fromEnvironment('GROQ_API_KEY_2');
  static const groqApiKey3 = String.fromEnvironment('GROQ_API_KEY_3');
  static const groqApiKey4 = String.fromEnvironment('GROQ_API_KEY_4');

  /// Tavily powers the shared `web_search` / `fetch_page` tools (free tier:
  /// 1,000 credits a month per key, so several keys can be listed).
  static const tavilyApiKey = String.fromEnvironment('TAVILY_API_KEY');
  static const tavilyApiKey2 = String.fromEnvironment('TAVILY_API_KEY_2');
  static const tavilyApiKey3 = String.fromEnvironment('TAVILY_API_KEY_3');

  /// Geoapify Places: hotels and attractions with coordinates and wheelchair
  /// tags (free tier: ~3,000 credits a day).
  static const geoapifyApiKey = String.fromEnvironment('GEOAPIFY_API_KEY');

  /// Optional. Only Xotelo's `/search` needs a key (through RapidAPI); the
  /// `/list`, `/rates` and `/heatmap` endpoints do not.
  static const xoteloRapidApiKey = String.fromEnvironment('XOTELO_RAPIDAPI_KEY');

  /// Every real Groq key, slot 1 first. Placeholders and blanks are dropped.
  static List<String> get groqKeys => realKeys([
    groqApiKey,
    groqApiKey2,
    groqApiKey3,
    groqApiKey4,
  ]);

  static List<String> get tavilyKeys =>
      realKeys([tavilyApiKey, tavilyApiKey2, tavilyApiKey3]);

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
