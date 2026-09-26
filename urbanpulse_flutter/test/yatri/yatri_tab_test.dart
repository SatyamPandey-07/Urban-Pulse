import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbanpulse/core/app_colors.dart';
import 'package:urbanpulse/core/app_theme.dart';
import 'package:urbanpulse/screens/tabs/yatri_ai_tab.dart';
import 'package:urbanpulse/state/app_scope.dart';

/// The real tab, with no Groq key configured (the test build has none): the
/// chat shows the key card and the form stays available. Also proves the
/// three layouts build without overflow.
void main() {
  for (final (name, size, hasPanel) in [
    ('phone', const Size(360, 740), false),
    ('tablet', const Size(820, 1180), false),
    ('wide', const Size(1280, 800), true),
  ]) {
    testWidgets('Yatri AI tab lays out on a $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        AppScope(
          services: AppServices(prefs),
          child: MaterialApp(
            theme: AppTheme.light(AccentColor.green),
            home: const Scaffold(body: YatriAiTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Yatri AI'), findsOneWidget);
      expect(find.text('Yatri chat needs a Groq API key'), findsOneWidget);
      expect(find.text('Use the form instead'), findsOneWidget);
      // Composer is disabled without a key.
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      // Progress strip on phone/tablet, side panel on wide screens.
      expect(find.text('Trip brief'), hasPanel ? findsOneWidget : findsNothing);
      expect(find.text('Destination'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
