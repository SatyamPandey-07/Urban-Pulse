import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/core/app_colors.dart';
import 'package:urbanpulse/core/app_theme.dart';
import 'package:urbanpulse/core/safe_launch.dart';
import 'package:urbanpulse/models/itinerary/plan_snapshot.dart';
import 'package:urbanpulse/screens/plan_itinerary_screen.dart';

import '../models/itinerary_test.dart' show sampleItinerary;

Future<void> pump(WidgetTester tester, Size size, {ThemeMode mode = ThemeMode.light, Future<void> Function()? onSave}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(AccentColor.green),
      darkTheme: AppTheme.dark(AccentColor.green),
      themeMode: mode,
      home: PlanItineraryScreen(
        itinerary: sampleItinerary().copyWith(timings: {'Atithi': 12, 'Bhatkanti': 14, 'Khoji': 9, 'total': 41}),
        tileLayer: const SizedBox.shrink(),
        onSave: onSave,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final (name, size) in [('phone', const Size(360, 740)), ('tablet', const Size(820, 1180)), ('desktop', const Size(1280, 800))]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('every tab renders without overflow on a $name (${mode.name})', (tester) async {
        await pump(tester, size, mode: mode);
        expect(find.textContaining('Munnar'), findsWidgets);

        for (final tab in ['Budget', 'Access', 'Green', 'Trip', 'Days']) {
          await tester.tap(find.text(tab).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'tab $tab');
        }
      });
    }
  }

  testWidgets('the days tab shows the timeline and switches day', (tester) async {
    await pump(tester, const Size(360, 740));
    expect(find.text('Day 1'), findsWidgets);
    expect(find.text('Tea Museum'), findsWidgets);
    await tester.tap(find.text('Day 2').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the budget tab totals the lines and marks estimates', (tester) async {
    await pump(tester, const Size(360, 740));
    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();
    expect(find.text('₹24,000'), findsWidgets);
    expect(find.textContaining('estimate'), findsWidgets);
  });

  testWidgets('the trip tab shows how the plan was made', (tester) async {
    await pump(tester, const Size(360, 740));
    await tester.tap(find.text('Trip'));
    await tester.pumpAndSettle();
    expect(find.text('How this plan was made'), findsOneWidget);
    expect(find.text('Atithi 12s'), findsOneWidget);
  });

  testWidgets('the trip tab lists what was changed after the first plan', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AccentColor.green),
        home: PlanItineraryScreen(
          itinerary: sampleItinerary().copyWith(version: 3, edits: [
            EditRecord(at: DateTime(2026, 10, 1), request: 'More rest on day 2', summary: 'Day 2 is lighter.'),
            EditRecord(at: DateTime(2026, 10, 2), request: 'A cheaper hotel', summary: 'Changed the stay.'),
          ]),
          tileLayer: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Trip'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your changes (version 3)'), findsOneWidget);
    expect(find.textContaining('A cheaper hotel'), findsOneWidget);
    expect(find.textContaining('More rest on day 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving works once and then says saved', (tester) async {
    var saves = 0;
    await pump(tester, const Size(360, 740), onSave: () async => saves++);
    await tester.tap(find.byTooltip('Save to My Trips'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.byTooltip('Saved to My Trips'), findsOneWidget);
  });

  group('links from the web are only opened if they are plain http(s)', () {
    test('accepts web pages', () {
      expect(safeWebUri('https://www.tripadvisor.com/Hotel_Review-g1-d2'), isNotNull);
      expect(safeWebUri(' http://example.com/a?b=c '), isNotNull);
    });

    test('rejects everything else', () {
      for (final bad in [null, '', 'javascript:alert(1)', 'tel:+911234567890', 'file:///etc/passwd', 'intent://x#Intent;end', 'ftp://example.com', '//example.com', 'https://', 'not a url']) {
        expect(safeWebUri(bad), isNull, reason: '$bad');
      }
    });
  });
}
