import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbanpulse/core/app_colors.dart';
import 'package:urbanpulse/core/app_theme.dart';
import 'package:urbanpulse/core/config.dart';
import 'package:urbanpulse/screens/tabs/settings_tab.dart';
import 'package:urbanpulse/state/app_scope.dart';

void main() {
  testWidgets('SettingsTab opens API key overrides sheet and saves custom key', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await AppConfig.loadOverrides(prefs);

    await tester.pumpWidget(
      AppScope(
        services: AppServices(prefs),
        child: MaterialApp(
          theme: AppTheme.dark(AccentColor.green),
          home: const Scaffold(body: SettingsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);

    final keySettingFinder = find.text('API Key & Provider Overrides');
    await tester.scrollUntilVisible(keySettingFinder, 100);
    expect(keySettingFinder, findsOneWidget);
    expect(find.textContaining('Using embedded build keys'), findsOneWidget);

    // Tap to open sheet. `scrollUntilVisible` only scrolls until the widget
    // exists; `ensureVisible` is what brings it fully inside the viewport, which
    // matters now that the Garmin row sits above it.
    await tester.ensureVisible(keySettingFinder);
    await tester.pumpAndSettle();
    await tester.tap(keySettingFinder);
    await tester.pumpAndSettle();

    // Verify sheet title and top fields
    expect(find.text('Groq Cloud API Key'), findsOneWidget);
    expect(find.text('Tavily Search API Key'), findsOneWidget);
    expect(find.text('TomTom Map API Key'), findsOneWidget);

    // Enter a custom Groq key
    final textFields = find.byType(TextField);
    expect(textFields, findsWidgets);

    await tester.enterText(textFields.first, 'gsk_test_widget_override_key_999');
    await tester.pumpAndSettle();

    // Tap Save & Apply Overrides
    final saveButton = find.text('Save & Apply Overrides');
    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // Verify AppConfig updated
    expect(AppConfig.hasAnyOverride, isTrue);
    expect(AppConfig.groqApiKey, equals('gsk_test_widget_override_key_999'));

    // Verify Settings tab subtitle reflects the override
    expect(find.text('Custom key overrides active'), findsOneWidget);

    // Verify What-if Weather Simulator option is present
    final simulatorFinder = find.text('What-if Weather Simulator');
    await tester.scrollUntilVisible(simulatorFinder, 100);
    expect(simulatorFinder, findsOneWidget);
    expect(find.textContaining('stress-test your trip against monsoon'), findsOneWidget);
  });
}
