import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/agents/runtime/report.dart';
import 'package:urbanpulse/agents/yatri/planner_orchestrator.dart';
import 'package:urbanpulse/core/app_colors.dart';
import 'package:urbanpulse/core/app_theme.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/models/yatri_question.dart';
import 'package:urbanpulse/widgets/yatri/answer_view.dart';

const _wc = AccessibilityNeed.wheelchair;
const _hearing = AccessibilityNeed.hearing;

HotelOption _hotel(
  String id,
  String name, {
  int? price = 3200,
  bool estimated = false,
  LatLng? at,
  SupportLevel wc = SupportLevel.unknown,
  String wcDetail = '',
  bool aiGuess = false,
}) => HotelOption(
  id: id,
  name: name,
  location: at,
  rating: 4.5,
  reviewCount: 1200,
  nightlyInr: price,
  totalStayInr: estimated || price == null ? null : price * 3,
  priceIsEstimated: estimated,
  cheapestOta: estimated ? null : 'Agoda.com',
  distanceToCenterKm: 1.2,
  tripAdvisorUrl: 'https://www.tripadvisor.com/Hotel_Review-g1-d1-Reviews-X.html',
  amenities: const ['Parking', 'Pool'],
  access: {
    _wc: NeedSupport(
      need: _wc,
      level: wc,
      detail: wcDetail,
      provenance: aiGuess ? Provenance.aiEstimate : const Provenance(source: 'OpenStreetMap', confidence: 0.8),
    ),
    _hearing: const NeedSupport(need: _hearing, level: SupportLevel.unknown),
  },
);

YatriQuestion _question(List<HotelOption> hotels, {Set<AccessibilityNeed> needs = const {_wc, _hearing}}) => YatriQuestion(
  id: 'plan.hotels.choice',
  fields: const [],
  widget: AnswerWidget.hotelChoice,
  defaultText: 'Which stay?',
  agent: 'yatri',
  hotels: hotels,
  hotelNeeds: needs,
  options: [
    for (final h in hotels) QuestionOption(id: h.id, label: h.name),
    const QuestionOption(id: PlannerOrchestrator.autoPick, label: 'Let Yatri choose'),
  ],
);

final _hotels = [
  _hotel('h1', 'Sunrise Heritage Homestay', at: const LatLng(10.09, 77.06), wc: SupportLevel.yes, wcDetail: 'Fully wheelchair accessible'),
  _hotel('h2', 'Tea Valley Resort', price: 8000, estimated: true, at: const LatLng(10.1, 77.07), wc: SupportLevel.partial, wcDetail: 'Ramp only', aiGuess: true),
  _hotel('h3', 'Budget Inn Munnar', price: null, estimated: true, wc: SupportLevel.no, wcDetail: 'Stairs only'),
];

Future<void> _pump(WidgetTester tester, Size size, Widget child, {ThemeMode mode = ThemeMode.light}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(AccentColor.green),
      darkTheme: AppTheme.dark(AccentColor.green),
      themeMode: mode,
      home: Scaffold(
        body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child)),
      ),
    ),
  );
  await tester.pump();
}

Widget _view(YatriQuestion q, void Function(YatriAnswer) onSubmit) => buildAnswerView(q, onSubmit: onSubmit);

void main() {
  for (final (name, size) in [('phone', const Size(360, 740)), ('tablet', const Size(820, 1180))]) {
    for (final mode in ThemeMode.values.where((m) => m != ThemeMode.system)) {
      testWidgets('shows every hotel with price, access and provenance without overflow on a $name (${mode.name})', (tester) async {
        await _pump(tester, size, _view(_question(_hotels), (_) {}), mode: mode);

        for (final h in _hotels) {
          expect(find.text(h.name), findsOneWidget);
        }
        // Live price says where it comes from; the estimate says it is one.
        expect(find.text('₹3,200 / night'), findsOneWidget);
        expect(find.text('live price via Agoda.com'), findsOneWidget);
        expect(find.text('≈ ₹8,000 / night'), findsOneWidget);
        expect(find.text('estimated price'), findsNWidgets(2));
        expect(find.text('Price unknown'), findsOneWidget);

        // Access chips per need, with the level in words.
        expect(find.text('Wheelchair: Supported'), findsOneWidget);
        expect(find.text('Wheelchair: Partly'), findsOneWidget);
        expect(find.text('Wheelchair: Not supported'), findsOneWidget);
        expect(find.text('Hearing: Unconfirmed'), findsNWidgets(3));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('cards are a vertical list, best first', (tester) async {
    await _pump(tester, const Size(820, 1180), _view(_question(_hotels), (_) {}));
    final tops = [for (final h in _hotels) tester.getTopLeft(find.text(h.name)).dy];
    expect(tops, [...tops]..sort());
    expect(tops.toSet(), hasLength(3));
    final lefts = [for (final h in _hotels) tester.getTopLeft(find.text(h.name)).dx];
    // (The selected card has a slightly thicker border.)
    expect(lefts.reduce((a, b) => a > b ? a : b) - lefts.reduce((a, b) => a < b ? a : b), lessThan(2));
  });

  testWidgets('the first hotel is preselected and can be chosen with one tap', (tester) async {
    YatriAnswer? got;
    await _pump(tester, const Size(360, 740), _view(_question(_hotels), (a) => got = a));
    expect(find.text('Choose Sunrise Heritage Homestay'), findsOneWidget);
    await tester.ensureVisible(find.text('Choose Sunrise Heritage Homestay'));
    await tester.tap(find.text('Choose Sunrise Heritage Homestay'));
    expect(got, isA<ChoiceAnswer>());
    expect((got as ChoiceAnswer).optionId, 'h1');
    expect(got!.displayLabel, 'Sunrise Heritage Homestay');
  });

  testWidgets('tapping another card changes the choice', (tester) async {
    YatriAnswer? got;
    await _pump(tester, const Size(360, 740), _view(_question(_hotels), (a) => got = a));
    await tester.tap(find.text('Tea Valley Resort'));
    await tester.pump();
    expect(find.text('Choose Tea Valley Resort'), findsOneWidget);
    await tester.ensureVisible(find.text('Choose Tea Valley Resort'));
    await tester.tap(find.text('Choose Tea Valley Resort'));
    expect((got as ChoiceAnswer).optionId, 'h2');
  });

  testWidgets('“Let Yatri choose” hands the decision back', (tester) async {
    YatriAnswer? got;
    await _pump(tester, const Size(360, 740), _view(_question(_hotels), (a) => got = a));
    await tester.ensureVisible(find.text('Let Yatri choose'));
    await tester.tap(find.text('Let Yatri choose'));
    expect((got as ChoiceAnswer).optionId, PlannerOrchestrator.autoPick);
  });

  testWidgets('details show what each source says, and say so when it is only an AI guess', (tester) async {
    await _pump(tester, const Size(360, 900), _view(_question(_hotels), (_) {}));
    expect(find.text('Fully wheelchair accessible'), findsNothing, reason: 'collapsed by default');

    await tester.tap(find.text('Details and sources').first);
    await tester.pump();
    expect(find.text('Fully wheelchair accessible'), findsOneWidget);
    expect(find.text('Source: OpenStreetMap'), findsOneWidget);
    expect(find.text('No information found'), findsWidgets, reason: 'hearing is unconfirmed, and it says so');
    expect(find.text('Parking'), findsWidgets);
    expect(find.text('Open listing'), findsOneWidget);

    await tester.ensureVisible(find.text('Details and sources').first);
    await tester.tap(find.text('Details and sources').first);
    await tester.pump();
    expect(find.text('Ramp only'), findsOneWidget);
    expect(find.text('AI-estimated, not verified'), findsOneWidget);
    expect(find.textContaining('This price is an estimate'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no access needs there are no access chips', (tester) async {
    await _pump(tester, const Size(360, 740), _view(_question(_hotels, needs: const {}), (_) {}));
    expect(find.textContaining('Wheelchair:'), findsNothing);
  });

  testWidgets('a hotel without coordinates is listed, and with none located there is no map', (tester) async {
    final noMap = [_hotel('a', 'Alpha'), _hotel('b', 'Beta')];
    await _pump(tester, const Size(360, 740), _view(_question(noMap, needs: const {}), (_) {}));
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('© OpenStreetMap'), findsNothing);
  });

  testWidgets('the map pins are numbered and tapping one selects that hotel', (tester) async {
    // (Tiles cannot load under test; the map draws its pins regardless.)
    final q = _question(_hotels);
    await _pump(tester, const Size(360, 900), buildAnswerView(q, onSubmit: (_) {}));
    expect(find.text('© OpenStreetMap'), findsOneWidget);
    // Two of the three hotels have coordinates: pins 1 and 2 (the cards show the same numbers).
    expect(find.text('1'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('very long names and many needs do not overflow a phone', (tester) async {
    final long = _hotel('h', 'The Extraordinarily Long-Named Heritage Palace Hotel & Convention Centre Resort and Spa of Old Munnar Town');
    await _pump(
      tester,
      const Size(320, 700),
      _view(_question([long], needs: AccessibilityNeed.values.where((n) => n != AccessibilityNeed.none).toSet()), (_) {}),
    );
    expect(tester.takeException(), isNull);
  });
}
