import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:urbanpulse/agents/planner/trip_plan_handoff_agent.dart';
import 'package:urbanpulse/agents/receptionist/receptionist_agent.dart';
import 'package:urbanpulse/core/app_colors.dart';
import 'package:urbanpulse/core/app_theme.dart';
import 'package:urbanpulse/domain/route_path.dart';
import 'package:urbanpulse/domain/trip_brief/question_catalog.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/models/yatri_question.dart';
import 'package:urbanpulse/repositories/trip_brief_repository.dart';
import 'package:urbanpulse/repositories/trip_repository.dart';
import 'package:urbanpulse/services/place_geocoder.dart';
import 'package:urbanpulse/state/yatri_controller.dart';
import 'package:urbanpulse/widgets/yatri/answer_view.dart';
import 'package:urbanpulse/widgets/yatri/route_map_card.dart';

import 'receptionist_flow_test.dart' show FakeLlm;
import 'test_support.dart';

const _phone = Size(360, 740);
const _tablet = Size(820, 1180);

Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(AccentColor.green),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('options are a vertical list', () {
    for (final (name, size) in [('phone', _phone), ('tablet', _tablet)]) {
      testWidgets('single choice stacks every option in one column on a $name', (tester) async {
        final q = QuestionCatalog.build('accessibility', TripBrief.empty(testNow), now: testNow);
        await pumpAt(tester, size, buildAnswerView(q, onSubmit: (_) {}));

        final rows = [
          for (final o in q.options) tester.getTopLeft(find.text(o.label).first),
        ];
        // Same left edge, strictly increasing top: a single vertical column.
        expect(rows.map((p) => p.dx).toSet(), hasLength(1));
        for (var i = 1; i < rows.length; i++) {
          expect(rows[i].dy, greaterThan(rows[i - 1].dy));
        }
      });
    }

    testWidgets('destination suggestions are a list too, not pills', (tester) async {
      final q = QuestionCatalog.build('destination', TripBrief.empty(testNow), now: testNow);
      await pumpAt(tester, _tablet, buildAnswerView(q, onSubmit: (_) {}));
      final tops = [
        for (final o in q.options) tester.getTopLeft(find.text(o.label).first).dy,
      ];
      expect(tops.toSet(), hasLength(q.options.length), reason: 'no two on the same row');
    });
  });

  group('agent-chosen widgets', () {
    testWidgets('dates default to the inline calendar', (tester) async {
      final q = QuestionCatalog.build('dates', TripBrief.empty(testNow), now: testNow);
      await pumpAt(tester, _phone, buildAnswerView(q, onSubmit: (_) {}));
      expect(find.byType(TableCalendar<void>), findsOneWidget);
      expect(find.text('Pick dates'), findsNothing);
    });

    testWidgets('the presets flavour hides the calendar behind “Pick dates”', (tester) async {
      final q = QuestionCatalog.build('dates', TripBrief.empty(testNow), now: testNow)
          .copyWith(variant: 'presets');
      await pumpAt(tester, _phone, buildAnswerView(q, onSubmit: (_) {}));
      expect(find.byType(TableCalendar<void>), findsNothing);
      expect(find.text('Pick dates'), findsOneWidget);
    });

    testWidgets('tapping two calendar days selects a range and enables Confirm', (tester) async {
      YatriAnswer? submitted;
      final q = QuestionCatalog.build('dates', TripBrief.empty(testNow), now: testNow);
      await pumpAt(tester, _tablet, buildAnswerView(q, onSubmit: (a) => submitted = a));

      FilledButton confirm() =>
          tester.widget(find.widgetWithText(FilledButton, 'Confirm dates'));
      expect(confirm().onPressed, isNull);

      // testNow is Fri 2 Oct 2026, so the 12th and 15th are in the future.
      await tester.tap(find.text('12').first);
      await tester.pump();
      await tester.tap(find.text('15').first);
      await tester.pump();

      expect(confirm().onPressed, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm dates'));
      final a = submitted! as DateRangeAnswer;
      expect((a.start.day, a.end.day), (12, 15));
    });

    testWidgets('a single tap makes a one-day trip', (tester) async {
      YatriAnswer? submitted;
      final q = QuestionCatalog.build('dates', TripBrief.empty(testNow), now: testNow);
      await pumpAt(tester, _tablet, buildAnswerView(q, onSubmit: (a) => submitted = a));
      await tester.tap(find.text('12').first);
      await tester.pump();
      await tester.tap(find.text('12').first);
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm dates'));
      final a = submitted! as DateRangeAnswer;
      expect(a.start.day, a.end.day);
    });

    testWidgets('the traveller stepper flavour counts up and answers', (tester) async {
      YatriAnswer? submitted;
      final q = QuestionCatalog.build('travellers', TripBrief.empty(testNow), now: testNow)
          .copyWith(variant: 'stepper');
      await pumpAt(tester, _phone, buildAnswerView(q, onSubmit: (a) => submitted = a));
      await tester.tap(find.byTooltip('More travellers'));
      await tester.tap(find.byTooltip('More travellers'));
      await tester.pump();
      await tester.tap(find.text('Confirm 4 travellers'));
      expect((submitted! as ChoiceAnswer).optionId, '4');
    });

    testWidgets('the budget slider flavour opens with the custom range ready', (tester) async {
      final q = QuestionCatalog.build('budget', completeBrief().copyWith(budgetMinInr: null), now: testNow)
          .copyWith(variant: 'slider', prefill: {'people': 4, 'days': 3, 'min': null, 'max': null});
      await pumpAt(tester, _phone, buildAnswerView(q, onSubmit: (_) {}));
      expect(find.byType(RangeSlider), findsOneWidget);
    });

    testWidgets('child ages: one row per child, answers with all ages', (tester) async {
      YatriAnswer? submitted;
      final b = completeBrief().copyWith(children: 2, childAges: const []);
      final q = QuestionCatalog.build('childAges', b, now: testNow);
      await pumpAt(tester, _phone, buildAnswerView(q, onSubmit: (a) => submitted = a));
      expect(find.text('Child 1'), findsOneWidget);
      expect(find.text('Child 2'), findsOneWidget);
      await tester.tap(find.text('Confirm ages'));
      expect((submitted! as AgesAnswer).ages, [8, 8]);
    });
  });

  group('route maths', () {
    final pune = LatLng(18.52, 73.86);
    final munnar = LatLng(10.09, 77.06);

    test('paths start and end at the two places for every style', () {
      for (final style in RouteStyle.values) {
        final path = routePath(pune, munnar, style);
        expect(path.first, pune);
        expect(path.last.latitude, closeTo(munnar.latitude, 1e-9));
        expect(path.last.longitude, closeTo(munnar.longitude, 1e-9));
        expect(path, hasLength(65));
      }
    });

    test('a flight arc bows further off the straight line than a road', () {
      double maxOffset(RouteStyle s) {
        final path = routePath(pune, munnar, s);
        // Distance of each point from the straight a-b line (in degrees).
        final dx = munnar.longitude - pune.longitude;
        final dy = munnar.latitude - pune.latitude;
        final len = (dx * dx + dy * dy);
        return [
          for (final p in path)
            ((p.longitude - pune.longitude) * dy - (p.latitude - pune.latitude) * dx).abs() /
                (len == 0 ? 1 : len),
        ].reduce((a, b) => a > b ? a : b);
      }

      expect(maxOffset(RouteStyle.arc), greaterThan(maxOffset(RouteStyle.solid)));
      expect(maxOffset(RouteStyle.solid), greaterThan(0));
    });

    test('bearing is compass-correct', () {
      expect(bearingDegrees(LatLng(0, 0), LatLng(1, 0)), closeTo(0, 0.5));
      expect(bearingDegrees(LatLng(0, 0), LatLng(0, 1)), closeTo(90, 0.5));
      expect(bearingDegrees(LatLng(1, 0), LatLng(0, 0)), closeTo(180, 0.5));
      expect(bearingDegrees(LatLng(0, 1), LatLng(0, 0)), closeTo(270, 0.5));
    });

    test('mode styles: flights arc, rail is dashed, cabs and buses are solid', () {
      expect(RouteStyles.styleFor(TripTransportMode.flight), RouteStyle.arc);
      expect(RouteStyles.styleFor(TripTransportMode.train), RouteStyle.dashed);
      expect(RouteStyles.styleFor(TripTransportMode.carTaxi), RouteStyle.solid);
      expect(RouteStyles.styleFor(TripTransportMode.eBus), RouteStyle.solid);
      expect(RouteStyles.styleFor(null), RouteStyle.solid);
    });

    test('the preview prefers a flight, then a train, then menu order', () {
      expect(
        RouteStyles.preferred({TripTransportMode.carTaxi, TripTransportMode.flight, TripTransportMode.train}),
        TripTransportMode.flight,
      );
      expect(
        RouteStyles.preferred({TripTransportMode.bus, TripTransportMode.train}),
        TripTransportMode.train,
      );
      expect(
        RouteStyles.preferred({TripTransportMode.carTaxi, TripTransportMode.eBus}),
        TripTransportMode.eBus,
      );
      expect(RouteStyles.preferred(const {}), isNull);
    });
  });

  group('geocoder', () {
    test('parses the first Open-Meteo result', () {
      final p = PlaceGeocoder.parse(
        '{"results":[{"name":"Munnar","latitude":10.0892,"longitude":77.0595},{"name":"x","latitude":1,"longitude":2}]}',
      );
      expect((p!.latitude, p.longitude), (10.0892, 77.0595));
    });

    test('no results or garbage is just null', () {
      expect(PlaceGeocoder.parse('{}'), isNull);
      expect(PlaceGeocoder.parse('{"results":[]}'), isNull);
      expect(PlaceGeocoder.parse('not json'), isNull);
      expect(PlaceGeocoder.parse('{"results":[{"name":"x"}]}'), isNull);
    });
  });

  group('route map card', () {
    for (final (name, size) in [('phone', _phone), ('tablet', _tablet)]) {
      testWidgets('draws for every mode on a $name and switches on chip tap', (tester) async {
        TripTransportMode? shown = TripTransportMode.flight;
        late StateSetter setOuter;
        await pumpAt(
          tester,
          size,
          StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return RouteMapCard(
                origin: LatLng(18.52, 73.86),
                destination: LatLng(10.09, 77.06),
                originName: 'Pune',
                destinationName: 'Munnar',
                modes: const [TripTransportMode.train, TripTransportMode.flight, TripTransportMode.carTaxi],
                shown: shown,
                onShow: (m) => setOuter(() => shown = m),
                tileLayer: const SizedBox.shrink(),
              );
            },
          ),
        );
        expect(find.text('Pune to Munnar'), findsOneWidget);
        expect(find.byIcon(Icons.flight), findsWidgets);

        // Let the draw animation run to the end without errors.
        await tester.pump(const Duration(seconds: 4));
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Train'));
        await tester.pump();
        expect(shown, TripTransportMode.train);
        await tester.pump(const Duration(seconds: 4));
        expect(find.byIcon(Icons.train), findsWidgets);

        await tester.tap(find.text('Car / taxi'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 4));
        expect(find.byIcon(Icons.local_taxi), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('with no mode chosen it draws a plain route with no vehicle', (tester) async {
      await pumpAt(
        tester,
        _phone,
        RouteMapCard(
          origin: LatLng(18.52, 73.86),
          destination: LatLng(10.09, 77.06),
          originName: 'Pune',
          destinationName: 'Munnar',
          modes: const [],
          shown: null,
          onShow: (_) {},
          tileLayer: const SizedBox.shrink(),
        ),
      );
      await tester.pump(const Duration(seconds: 4));
      expect(find.byIcon(Icons.flight), findsNothing);
      expect(find.byIcon(Icons.train), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('map entry in the conversation', () {
    Future<(YatriController, FakeLlm, List<String>)> build({
      Map<String, LatLng?> places = const {},
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final llm = FakeLlm();
      final looked = <String>[];
      final c = YatriController(
        receptionist: ReceptionistAgent(llm, clock: () => testNow),
        handoff: TripPlanHandoffAgent(),
        briefs: TripBriefRepository(prefs),
        trips: TripRepository(prefs),
        hasKey: () => true,
        clock: () => testNow,
        geocode: (place) async {
          looked.add(place);
          return places[place];
        },
      );
      return (c, llm, looked);
    }

    final places = {'Pune': LatLng(18.52, 73.86), 'Munnar': LatLng(10.09, 77.06)};

    test('appears once both places are fixed, then follows the selected transport', () async {
      final (c, llm, looked) = await build(places: places);
      c.start();
      llm.extractions.add('{"updates": {"destination": "Munnar"}}');
      await c.sendText('Munnar');
      expect(c.entries.whereType<RouteMapEntry>(), isEmpty, reason: 'origin still unknown');
      expect(looked, isEmpty);

      await c.answer(c.activeQuestion!.question, const ChoiceAnswer('Pune', 'Pune'));
      await Future<void>.delayed(Duration.zero);
      final map = c.entries.whereType<RouteMapEntry>().single;
      expect(looked, unorderedEquals(['Pune', 'Munnar']));
      expect(map.ready, isTrue);
      expect(map.shown, isNull, reason: 'no transport chosen yet');

      // Fast-forward: answer everything up to transport.
      for (var i = 0; i < 12 && c.activeQuestion?.question.id != 'transport'; i++) {
        final q = c.activeQuestion!.question;
        await c.answer(
          q,
          switch (q.id) {
            'dates' => DateRangeAnswer(DateTime(2026, 10, 10, 9), DateTime(2026, 10, 12, 18)),
            'travellers' => const ChoiceAnswer('2', '2 people'),
            'group' => const GroupAnswer(adults: 2, seniors: 0, children: 0, women: 0, childAges: []),
            'accessibility' => const MultiChoiceAnswer({'none'}, ['None']),
            _ => throw StateError('unexpected ${q.id}'),
          },
        );
      }
      await c.answer(
        c.activeQuestion!.question,
        const MultiChoiceAnswer({'train', 'flight'}, ['Train', 'Flight']),
      );

      expect(c.entries.whereType<RouteMapEntry>(), hasLength(1), reason: 'one map, updated in place');
      expect(map.modes, [TripTransportMode.train, TripTransportMode.flight]);
      expect(map.shown, TripTransportMode.flight, reason: 'flights are previewed first');

      c.showMode(map, TripTransportMode.train);
      expect(map.shown, TripTransportMode.train);
      c.showMode(map, TripTransportMode.carTaxi);
      expect(map.shown, TripTransportMode.train, reason: 'not a selected mode');
    });

    test('an unknown place quietly drops the map instead of showing an error', () async {
      final (c, llm, _) = await build(places: {'Pune': LatLng(18.52, 73.86)});
      c.start();
      llm.extractions.add('{"updates": {"destination": "Nowhereville", "originCity": "Pune"}}');
      await c.sendText('Pune to Nowhereville');
      await Future<void>.delayed(Duration.zero);
      expect(c.entries.whereType<RouteMapEntry>(), isEmpty);
      expect(c.activeQuestion, isNotNull, reason: 'the conversation carries on');
    });

    test('without a geocoder there is no map', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final llm = FakeLlm();
      final c = YatriController(
        receptionist: ReceptionistAgent(llm, clock: () => testNow),
        handoff: TripPlanHandoffAgent(),
        briefs: TripBriefRepository(prefs),
        trips: TripRepository(prefs),
        hasKey: () => true,
        clock: () => testNow,
      )..start();
      llm.extractions.add('{"updates": {"destination": "Munnar", "originCity": "Pune"}}');
      await c.sendText('Pune to Munnar');
      expect(c.entries.whereType<RouteMapEntry>(), isEmpty);
    });
  });
}
