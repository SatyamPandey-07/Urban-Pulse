import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/core/app_colors.dart';
import 'package:urbanpulse/core/app_theme.dart';
import 'package:urbanpulse/domain/trip_brief/question_catalog.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/models/yatri_question.dart';
import 'package:urbanpulse/screens/trip_brief_form_screen.dart';
import 'package:urbanpulse/widgets/yatri/answer_view.dart';
import 'package:urbanpulse/widgets/yatri/chat_entry_view.dart';

import 'test_support.dart';

const _phone = Size(360, 740);
const _tablet = Size(820, 1180);
const _wide = Size(1280, 800);

Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(AccentColor.green),
      darkTheme: AppTheme.dark(AccentColor.green),
      home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
    ),
  );
  await tester.pump();
}

void main() {
  group('interaction', () {
    testWidgets('group Confirm stays disabled until the parts add up to the total', (tester) async {
      YatriAnswer? submitted;
      final q = QuestionCatalog.build(
        'group',
        completeBrief().copyWith(adults: 4, seniors: 0, children: 0, women: 0, childAges: const []),
        now: testNow,
      );
      await pumpAt(tester, _phone, buildAnswerView(q, onSubmit: (a) => submitted = a));

      FilledButton confirm() =>
          tester.widget(find.widgetWithText(FilledButton, 'Confirm group'));
      expect(confirm().onPressed, isNotNull);

      await tester.tap(find.byTooltip('More Children'));
      await tester.pump();
      expect(confirm().onPressed, isNull, reason: '5 people vs a total of 4');
      expect(find.textContaining('adds up to 5'), findsOneWidget);
      // A new child needs an age chip.
      expect(find.text('Child 1'), findsOneWidget);

      await tester.tap(find.byTooltip('Fewer Adults'));
      await tester.pump();
      expect(confirm().onPressed, isNotNull);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm group'));
      expect(submitted, isA<GroupAnswer>());
      final g = submitted! as GroupAnswer;
      expect((g.adults, g.children, g.childAges.length), (3, 1, 1));
    });

    testWidgets('“None” is exclusive in multi-select', (tester) async {
      YatriAnswer? submitted;
      final q = QuestionCatalog.build('accessibility', TripBrief.empty(testNow), now: testNow);
      await pumpAt(tester, _phone, buildAnswerView(q, onSubmit: (a) => submitted = a));

      await tester.tap(find.text('Wheelchair user'));
      await tester.tap(find.text('Hearing impairment'));
      await tester.pump();
      expect(find.text('Confirm (2)'), findsOneWidget);

      // The list is long enough now that later rows are below the fold.
      await tester.ensureVisible(find.text('No accessibility needs'));
      await tester.tap(find.text('No accessibility needs'));
      await tester.pump();
      expect(find.text('Confirm (1)'), findsOneWidget);

      await tester.ensureVisible(find.text('Wheelchair user'));
      await tester.tap(find.text('Wheelchair user'));
      await tester.pump();
      expect(find.text('Confirm (1)'), findsOneWidget, reason: '“None” cleared by another pick');

      await tester.ensureVisible(find.text('Confirm (1)'));
      await tester.tap(find.text('Confirm (1)'));
      expect((submitted! as MultiChoiceAnswer).optionIds, {'wheelchair'});
    });

    testWidgets('single choice answers on tap', (tester) async {
      YatriAnswer? submitted;
      final q = QuestionCatalog.build('travellers', TripBrief.empty(testNow), now: testNow);
      await pumpAt(tester, _phone, buildAnswerView(q, onSubmit: (a) => submitted = a));

      await tester.tap(find.text('4 people'));
      expect((submitted! as ChoiceAnswer).optionId, '4');
    });

    testWidgets('transport starts with the greener modes ticked and shows CO₂ badges', (tester) async {
      final q = QuestionCatalog.build('transport', TripBrief.empty(testNow), now: testNow);
      await pumpAt(tester, _phone, buildAnswerView(q, onSubmit: (_) {}));
      expect(find.text('Confirm (2)'), findsOneWidget);
      expect(find.textContaining('g CO₂/km'), findsWidgets);
    });

    testWidgets('a past date range disables Confirm', (tester) async {
      final q = QuestionCatalog.build('dates', TripBrief.empty(testNow), now: testNow)
          .copyWith(prefill: {
            'now': testNow,
            'start': DateTime(2026, 9, 1, 9),
            'end': DateTime(2026, 9, 2, 9),
          });
      await pumpAt(tester, _phone, buildAnswerView(q, onSubmit: (_) {}));
      expect(find.text('The start time is in the past.'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Confirm dates'));
      expect(confirm.onPressed, isNull);
    });
  });

  group('responsive — no overflow', () {
    const ids = [
      'destination', 'origin', 'dates', 'travellers', 'group', 'womenSafety',
      'accessibility', 'a11y.wheelchair.type', 'a11y.visual.support',
      'transport', 'budget', 'childAges', 'women', 'style', 'stay', 'confirm.dates', //
    ];

    for (final (name, size) in [('phone', _phone), ('tablet', _tablet), ('wide', _wide)]) {
      testWidgets('every answer card fits on a $name', (tester) async {
        final brief = completeBrief().copyWith(
          accessibilityNeeds: {AccessibilityNeed.wheelchair, AccessibilityNeed.visual},
          uncertain: {BriefField.dates},
        );
        await pumpAt(
          tester,
          size,
          Column(
            children: [
              for (final id in ids)
                AnswerCard(
                  entryId: id.hashCode,
                  question: QuestionCatalog.build(id, brief, now: testNow, detectedCity: 'Pune'),
                  onSubmit: (_) {},
                ),
            ],
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }

    for (final (name, size) in [('phone', _phone), ('tablet', _tablet), ('wide', _wide)]) {
      testWidgets('the review form fits on a $name and blocks an incomplete brief', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        TripBrief? popped;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AccentColor.green),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async => popped = await TripBriefFormScreen.open(
                      context,
                      initial: TripBrief.empty(testNow).copyWith(destination: 'Munnar'),
                      now: testNow,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Review your trip'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Confirm & plan trip'));
        await tester.pumpAndSettle();
        expect(popped, isNull, reason: 'origin, dates, budget… are still missing');
        expect(find.text('Review your trip'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a complete brief in the form confirms and pops', (tester) async {
      tester.view.physicalSize = _tablet;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      TripBrief? popped;
      final brief = completeBrief();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AccentColor.green),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async => popped = await TripBriefFormScreen.open(
                    context,
                    initial: brief,
                    now: testNow,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm & plan trip'));
      await tester.pumpAndSettle();
      expect(popped, isNotNull);
      expect(popped!.destination, 'Munnar');
      expect(popped!.travellerCount, 4);
    });
  });
}
