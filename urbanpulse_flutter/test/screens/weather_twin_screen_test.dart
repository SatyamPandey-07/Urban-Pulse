import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:urbanpulse/agents/travel_risk/travel_risk_rules.dart';
import 'package:urbanpulse/agents/twin/social_signals.dart';
import 'package:urbanpulse/agents/twin/twin_calibration.dart';
import 'package:urbanpulse/agents/twin/twin_controller.dart';
import 'package:urbanpulse/agents/twin/twin_demo.dart';
import 'package:urbanpulse/agents/twin/weather_twin.dart';
import 'package:urbanpulse/screens/weather_twin_screen.dart';
import 'package:urbanpulse/services/data/forecast_client.dart';

void main() {
  testWidgets('the twin screen runs at phone size: presets, a typed report, every section', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // No network: the forecast and the feeds fail, the twin runs on its defaults.
    final offline = MockClient((_) async => http.Response('unavailable', 503));
    final it = TwinDemo.jaipur(start: DateTime(2026, 10, 12));
    final c = TwinController(
      itinerary: it,
      risk: const RuleTravelRisk(),
      forecast: ForecastClient(client: offline),
      calibration: TwinCalibration.memory(),
      feed: SocialSignalFeed(client: offline),
      clock: () => DateTime(2026, 9, 27, 9),
    );

    await tester.pumpWidget(MaterialApp(home: WeatherTwinScreen(itinerary: it, controller: c, tileLayer: const SizedBox())));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    final list = find.descendant(of: find.byKey(const Key('weather-twin-list')), matching: find.byType(Scrollable)).first;
    expect(find.text('What if…'), findsOneWidget);
    expect(c.state, isNotNull);
    await tester.scrollUntilVisible(find.text('Your trip under the live forecast'), 300, scrollable: list);
    expect(c.state!.visitsKept, c.state!.visitsTotal);

    // A preset re-simulates the trip.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Monsoon downpour'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Monsoon downpour'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(c.state!.scenario.id, 'downpour');
    await tester.scrollUntilVisible(find.text('Your trip under “Monsoon downpour”'), 300, scrollable: list);
    expect(c.state!.disrupted, greaterThan(0));

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Flooding near the hotel'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Flooding near the hotel'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(c.state!.hotelAtRisk, isTrue);

    // Every section is laid out without overflow.
    for (final title in ['How the weather propagates', 'What people are reporting', 'What the twin has learned', 'Twin updates']) {
      await tester.scrollUntilVisible(find.text(title), 400, scrollable: list);
      expect(find.text(title), findsOneWidget);
    }

    // A typed report is read and closes the place it names.
    c.setScenario(const TwinScenario());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byType(TextField));
    await tester.pump();
    // Reports apply to the scenario's first day when the trip has not started.
    await tester.enterText(find.byType(TextField), 'Hawa Mahal closed today due to heavy rain, officials say');
    await tester.ensureVisible(find.byIcon(Icons.send_rounded));
    await tester.tap(find.byIcon(Icons.send_rounded));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(c.signals, hasLength(1));
    expect(c.state!.visits.firstWhere((v) => v.name == 'Hawa Mahal').state, VisitState.closed);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
