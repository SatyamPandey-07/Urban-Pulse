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
}
