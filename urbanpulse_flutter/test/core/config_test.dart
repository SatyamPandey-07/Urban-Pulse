import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbanpulse/core/config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.loadOverrides();
  });

  tearDown(() async {
    await AppConfig.clearAllOverrides();
  });

  group('AppConfig API key overrides', () {
    test('defaults to embedded build keys when no overrides are present', () {
      expect(AppConfig.hasAnyOverride, isFalse);
      expect(AppConfig.hasOverride(AppConfig.keyOverrideGroq), isFalse);
      expect(AppConfig.groqApiKey, equals(AppConfig.embeddedGroqApiKey));
      expect(AppConfig.tomtomApiKey, equals(AppConfig.embeddedTomTomApiKey));
      expect(AppConfig.tavilyApiKey, equals(AppConfig.embeddedTavilyApiKey));
      expect(AppConfig.geoapifyApiKey, equals(AppConfig.embeddedGeoapifyApiKey));
      expect(AppConfig.xoteloRapidApiKey, equals(AppConfig.embeddedXoteloRapidApiKey));
      expect(AppConfig.centralRegistryBaseUrl, equals(AppConfig.embeddedCentralRegistryBaseUrl));
    });

    test('prioritizes custom override when set and reverts when cleared', () async {
      const customGroq = 'gsk_custom_override_key_12345';
      await AppConfig.setOverride(AppConfig.keyOverrideGroq, customGroq);

      expect(AppConfig.hasAnyOverride, isTrue);
      expect(AppConfig.hasOverride(AppConfig.keyOverrideGroq), isTrue);
      expect(AppConfig.getOverride(AppConfig.keyOverrideGroq), equals(customGroq));
      expect(AppConfig.groqApiKey, equals(customGroq));
      expect(AppConfig.groqKeys.first, equals(customGroq));

      // Clearing override reverts back to embedded
      await AppConfig.setOverride(AppConfig.keyOverrideGroq, '');
      expect(AppConfig.hasOverride(AppConfig.keyOverrideGroq), isFalse);
      expect(AppConfig.groqApiKey, equals(AppConfig.embeddedGroqApiKey));
    });

    test('clearAllOverrides reverts all services to embedded keys', () async {
      await AppConfig.setOverride(AppConfig.keyOverrideGroq, 'gsk_override');
      await AppConfig.setOverride(AppConfig.keyOverrideTomTom, 'tomtom_override');
      await AppConfig.setOverride(AppConfig.keyOverrideTavily, 'tavily_override');
      await AppConfig.setOverride(AppConfig.keyOverrideGeoapify, 'geoapify_override');
      await AppConfig.setOverride(AppConfig.keyOverrideXotelo, 'xotelo_override');
      await AppConfig.setOverride(AppConfig.keyOverrideCentralRegistry, 'http://192.168.1.100:8080');

      expect(AppConfig.hasAnyOverride, isTrue);
      expect(AppConfig.groqApiKey, equals('gsk_override'));
      expect(AppConfig.tomtomApiKey, equals('tomtom_override'));
      expect(AppConfig.tavilyApiKey, equals('tavily_override'));
      expect(AppConfig.geoapifyApiKey, equals('geoapify_override'));
      expect(AppConfig.xoteloRapidApiKey, equals('xotelo_override'));
      expect(AppConfig.centralRegistryBaseUrl, equals('http://192.168.1.100:8080'));

      await AppConfig.clearAllOverrides();

      expect(AppConfig.hasAnyOverride, isFalse);
      expect(AppConfig.groqApiKey, equals(AppConfig.embeddedGroqApiKey));
      expect(AppConfig.tomtomApiKey, equals(AppConfig.embeddedTomTomApiKey));
      expect(AppConfig.tavilyApiKey, equals(AppConfig.embeddedTavilyApiKey));
      expect(AppConfig.geoapifyApiKey, equals(AppConfig.embeddedGeoapifyApiKey));
      expect(AppConfig.xoteloRapidApiKey, equals(AppConfig.embeddedXoteloRapidApiKey));
      expect(AppConfig.centralRegistryBaseUrl, equals(AppConfig.embeddedCentralRegistryBaseUrl));
    });
  });
}
