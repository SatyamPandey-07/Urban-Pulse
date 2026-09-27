import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/core/app_colors.dart';
import 'package:urbanpulse/core/app_theme.dart';
import 'package:urbanpulse/models/map_route.dart';
import 'package:urbanpulse/screens/tabs/live_map_tab.dart';
import 'package:urbanpulse/services/live_location.dart';
import 'package:urbanpulse/state/live_map_controller.dart';

import '../services/map_route_test.dart' show northRoute;
import '../state/live_map_controller_test.dart' show ScriptedLocation, ScriptedMapData, poi;

Future<(LiveMapController, ScriptedMapData, ScriptedLocation)> pumpMap(WidgetTester tester, {Size size = const Size(390, 780), ThemeMode mode = ThemeMode.light, LocationResult? location}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final data = ScriptedMapData()
    ..searchResults = [poi('Amber Fort', 10.02, 77.01, d: 2400), poi('Amber Palace Cafe', 10.021, 77.012, d: 2500)]
    ..nearbyResults = [poi('City Hospital', 10.01, 77.005, d: 800), poi('Care Clinic', 10.012, 77.0, d: 1400)]
    ..routeResults = [northRoute()]
    ..traffic = 'https://tiles/{z}/{x}/{y}.png';
  final loc = ScriptedLocation();
  if (location != null) loc.result = location;
  final c = LiveMapController(data: data, location: loc, searchDelay: const Duration(milliseconds: 10));
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(AccentColor.green),
      darkTheme: AppTheme.dark(AccentColor.green),
      themeMode: mode,
      home: Scaffold(body: LiveMapTab(controller: c, tileLayer: const SizedBox.shrink(), trafficLayer: const SizedBox.shrink())),
    ),
  );
  await c.start();
  await tester.pumpAndSettle();
  return (c, data, loc);
}

void main() {
  for (final (name, size) in [('phone', const Size(360, 700)), ('tablet', const Size(820, 1100)), ('desktop', const Size(1280, 800))]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the map, search and controls render on a $name (${mode.name})', (tester) async {
        await pumpMap(tester, size: size, mode: mode);
        expect(find.text('Search places or addresses'), findsOneWidget);
        expect(find.text('Food'), findsOneWidget);
        expect(find.byTooltip('Zoom in'), findsOneWidget);
        expect(find.byTooltip('My location'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a category shows real places as cards, and choosing one shows the place', (tester) async {
    final (c, _, _) = await pumpMap(tester);
    await tester.scrollUntilVisible(find.text('Hospitals'), 100, scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)));
    await tester.ensureVisible(find.text('Hospitals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hospitals'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Hospitals nearby · 2'), findsOneWidget);
    expect(find.text('City Hospital'), findsOneWidget);
    expect(find.text('800 m'), findsOneWidget);

    await tester.tap(find.text('City Hospital'));
    await tester.pumpAndSettle();
    expect(c.selected!.name, 'City Hospital');
    expect(find.text('Directions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('searching lists results, and directions lead to a route you can start', (tester) async {
    final (c, _, loc) = await pumpMap(tester);
    await tester.enterText(find.byType(TextField), 'amber');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('Amber Fort'), findsOneWidget);
    expect(find.text('2.4 km'), findsOneWidget);

    await tester.tap(find.text('Amber Fort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Directions'));
    await tester.pumpAndSettle();
    expect(find.text('To Amber Fort'), findsOneWidget);
    expect(find.text('10 min'), findsOneWidget);
    expect(find.textContaining('Measured by'), findsOneWidget);
    expect(find.text('Fastest'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(c.navigating, isTrue);
    expect(find.text('End'), findsOneWidget);

    loc.positions.add(const UserFix(point: LatLng(10.005, 77)));
    await tester.pumpAndSettle();
    expect(find.text('Turn left onto Park Road'), findsOneWidget);
    expect(find.textContaining('in '), findsWidgets);

    loc.positions.add(const UserFix(point: LatLng(10.0199, 77)));
    await tester.pumpAndSettle();
    expect(find.textContaining('You have arrived'), findsWidgets);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(c.navigating, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search with no matches says so', (tester) async {
    final (c, data, _) = await pumpMap(tester);
    data.searchResults = [];
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.textContaining('No places matched'), findsOneWidget);
    expect(c.results, isEmpty);
  });

  testWidgets('with location off the map says why and offers the way to fix it', (tester) async {
    await pumpMap(tester, location: const LocationResult(LocationStatus.serviceOff));
    expect(find.textContaining('switched off'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);
  });

  testWidgets('directions without a position explain instead of guessing', (tester) async {
    final (c, _, _) = await pumpMap(tester, location: const LocationResult(LocationStatus.denied));
    c.select(poi('Amber Fort', 10.02, 77.01));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Directions'));
    await tester.pumpAndSettle();
    expect(find.textContaining('permission'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('no route measured is said, with a way to retry', (tester) async {
    final (c, data, _) = await pumpMap(tester);
    data.routeResults = [];
    c.select(poi('Amber Fort', 10.02, 77.01));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Directions'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No route could be measured'), findsOneWidget);
    data.routeResults = [northRoute()];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('the layers sheet changes the map type and explains traffic', (tester) async {
    final (c, _, _) = await pumpMap(tester);
    await tester.tap(find.byTooltip('Map layers'));
    await tester.pumpAndSettle();
    expect(find.text('Map type'), findsOneWidget);
    await tester.tap(find.text('Satellite'));
    await tester.pumpAndSettle();
    expect(c.style, MapStyle.satellite);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(c.traffic, isTrue);
  });

  testWidgets('pressing on the map drops a pin you can get directions to', (tester) async {
    final (c, data, _) = await pumpMap(tester);
    data.describeResult = 'Park Road, Indiranagar';
    await tester.longPressAt(tester.getCenter(find.byType(LiveMapTab)) + const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(c.selected, isNotNull);
    expect(find.text('Park Road'), findsOneWidget);
    expect(find.text('Directions'), findsOneWidget);
  });

  testWidgets('closing a place goes back to the plain map', (tester) async {
    final (c, _, _) = await pumpMap(tester);
    c.select(poi('Amber Fort', 10.02, 77.01));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(c.selected, isNull);
    expect(find.text('Directions'), findsNothing);
  });

  testWidgets('a walking route is one card, and driving can offer two', (tester) async {
    final (c, data, _) = await pumpMap(tester);
    final a = northRoute();
    data.routeResults = [a, MapRoute(id: 'eco', label: 'Eco', mode: NavMode.drive, points: a.points, distanceM: a.distanceM * 1.15, durationS: 780, source: 'TomTom')];
    c.select(poi('Amber Fort', 10.02, 77.01));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Directions'));
    await tester.pumpAndSettle();
    expect(find.text('Fastest'), findsOneWidget);
    expect(find.text('Eco'), findsOneWidget);
    await tester.tap(find.text('Eco'));
    await tester.pumpAndSettle();
    expect(c.selectedRoute!.id, 'eco');
  });
}
