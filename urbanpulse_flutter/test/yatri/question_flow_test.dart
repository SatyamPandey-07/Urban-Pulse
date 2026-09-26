import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/domain/trip_brief/answer_applier.dart';
import 'package:urbanpulse/domain/trip_brief/brief_merger.dart';
import 'package:urbanpulse/domain/trip_brief/brief_validator.dart';
import 'package:urbanpulse/domain/trip_brief/extraction.dart';
import 'package:urbanpulse/domain/trip_brief/question_catalog.dart';
import 'package:urbanpulse/domain/trip_brief/question_planner.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/models/yatri_question.dart';

import 'test_support.dart';

YatriQuestion? nextQuestion(TripBrief b, [PlannerState? state]) =>
    QuestionPlanner.next(
      b,
      BriefValidator.validate(b, testNow),
      state ?? PlannerState(),
      now: testNow,
    );

void main() {
  group('extraction parser', () {
    test('parses fenced JSON wrapped in prose and coerces types', () {
      const raw = '''
Sure! Here you go:
```json
{"updates": {
  "destination": {"value": "Munnar", "confidence": 0.95},
  "travellerCount": "4",
  "transportModes": ["train", "hovercraft"],
  "start": {"value": "2026-10-10T09:00", "confidence": 0.8, "timeAssumed": true}
 },
 "ack": "Munnar with family — lovely!"}
```''';
      final ex = ExtractionParser.parse(raw);
      expect(ex.updates['destination']!.value, 'Munnar');
      expect(ex.updates['travellerCount']!.value, 4);
      expect(ex.updates['transportModes']!.value, {TripTransportMode.train});
      expect(ex.updates['start']!.timeAssumed, isTrue);
      expect(ex.ack, contains('Munnar'));
    });

    test('drops bad dates, unknown enums and garbage', () {
      final ex = ExtractionParser.parse(
        '{"updates": {"start": "next-ish", "style": "chaotic", "adults": {"value": null}}}',
      );
      expect(ex.updates, isEmpty);
      expect(ExtractionParser.parse('not json at all').isEmpty, isTrue);
      expect(ExtractionParser.parse('').isEmpty, isTrue);
    });

    test('reads the answer to the pending question', () {
      final ex = ExtractionParser.parse('{"pendingAnswer": {"optionIds": ["o2"]}}');
      expect(ex.pendingOptionIds, {'o2'});
      expect(ExtractionParser.parse('{"pendingAnswer": {"bool": true}}').pendingBool, isTrue);
    });
  });

  group('merger', () {
    test('“family of 4 to Munnar” fills destination and total, not the breakdown', () {
      final ex = ExtractionParser.parse(
        '{"updates": {"destination": "Munnar", "travellerCount": 4}}',
      );
      final b = BriefMerger.apply(TripBrief.empty(testNow), ex).brief;
      expect(b.destination, 'Munnar');
      expect(b.travellerCount, 4);
      expect(b.hasGroupBreakdown, isFalse);
    });

    test('“actually make it 5 people” records a change and re-raises the group', () {
      final ex = ExtractionParser.parse('{"updates": {"travellerCount": 5}}');
      final result = BriefMerger.apply(completeBrief(), ex);
      expect(result.changes.single.toString(), 'Travellers: 4 → 5');

      final q = nextQuestion(result.brief)!;
      expect(q.id, 'group');
      expect(q.reason, IssueKind.conflict);
      expect(q.hint, contains('5'));
      expect(q.prefill['total'], 5);
    });

    test('low confidence or an assumed time asks for confirmation', () {
      final ex = ExtractionParser.parse('''
{"updates": {
  "destination": {"value": "Coorg", "confidence": 0.4},
  "start": {"value": "2026-10-10T09:00", "timeAssumed": true},
  "end": {"value": "2026-10-12T18:00", "timeAssumed": true}
}}''');
      final b = BriefMerger.apply(TripBrief.empty(testNow), ex).brief;
      expect(b.uncertain, {BriefField.destination, BriefField.dates});
    });

    test('extracted accessibility needs never count as confirmed', () {
      final ex = ExtractionParser.parse(
        '{"updates": {"accessibilityNeeds": ["wheelchair", "none"]}}',
      );
      final b = BriefMerger.apply(completeBrief(), ex).brief;
      expect(b.accessibilityNeeds, {AccessibilityNeed.wheelchair});
      expect(b.accessibilityConfirmed, isFalse);
    });

    test('a breakdown with no total derives the total', () {
      final ex = ExtractionParser.parse(
        '{"updates": {"adults": 2, "seniors": 1, "children": 0}}',
      );
      final b = BriefMerger.apply(TripBrief.empty(testNow), ex).brief;
      expect(b.travellerCount, 3);
    });
  });

  group('planner', () {
    test('asks mandatory questions one at a time in registry order', () {
      var b = TripBrief.empty(testNow);
      final order = <String>[];
      // Answer each with a valid value until nothing is left but the offer.
      final answers = <String, YatriAnswer>{
        'destination': const ChoiceAnswer('Munnar', 'Munnar'),
        'origin': const ChoiceAnswer('Pune', 'Pune'),
        'dates': DateRangeAnswer(DateTime(2026, 10, 10, 9), DateTime(2026, 10, 13, 18)),
        'travellers': const ChoiceAnswer('4', '4 people'),
        'group': const GroupAnswer(adults: 2, seniors: 0, children: 2, women: 1, childAges: [6, 9]),
        'womenSafety': const MultiChoiceAnswer({'none'}, ['None']),
        'accessibility': const MultiChoiceAnswer({'wheelchair'}, ['Wheelchair']),
        'a11y.wheelchair.type': const ChoiceAnswer('manual', 'Manual'),
        'a11y.wheelchair.facilities': const MultiChoiceAnswer({'lift'}, ['Lift']),
        'transport': const MultiChoiceAnswer({'train'}, ['Train']),
        'budget': const BudgetAnswer(20000, 40000),
      };
      for (var i = 0; i < 20; i++) {
        final q = nextQuestion(b);
        if (q == null || q.id == 'optionalOffer') break;
        order.add(q.id);
        final res = AnswerApplier.apply(b, q, answers[q.id]!, testNow);
        expect(res.error, isNull, reason: q.id);
        b = res.brief!;
      }
      expect(order, [
        'destination', 'origin', 'dates', 'travellers', 'group',
        'womenSafety', 'accessibility', 'a11y.wheelchair.type',
        'a11y.wheelchair.facilities', 'transport', 'budget', //
      ]);
      expect(BriefValidator.validate(b, testNow).isComplete, isTrue);
    });

    test('conflicts and invalid answers come before missing fields', () {
      final b = TripBrief.empty(testNow).copyWith(
        destination: 'Pune',
        originCity: 'Pune',
      );
      expect(nextQuestion(b)!.id, 'destination');
      expect(nextQuestion(b)!.reason, IssueKind.conflict);
    });

    test('several accessibility needs get follow-ups for each, in order', () {
      final b = completeBrief().copyWith(
        accessibilityNeeds: {AccessibilityNeed.visual, AccessibilityNeed.hearing},
      );
      final state = PlannerState();
      final first = nextQuestion(b, state)!;
      expect(first.id, 'a11y.visual.support');
      final b2 = b.copyWith(accessibilityDetails: {'a11y.visual.support': {'audio'}});
      expect(nextQuestion(b2, state)!.id, 'a11y.hearing.support');
    });

    test('offers optional preferences exactly once after the mandatory ones', () {
      final state = PlannerState();
      expect(nextQuestion(completeBrief(), state)!.id, 'optionalOffer');
      expect(nextQuestion(completeBrief(), state), isNull);
    });

    test('a queued optional question is asked after a “yes”', () {
      final state = PlannerState()
        ..optionalOffered = true
        ..optionalQueue.addAll(QuestionCatalog.optionalIds);
      final q = nextQuestion(completeBrief(), state)!;
      expect(q.id, 'style');
      expect(q.skippable, isTrue);
    });

    test('accessibility is asked even when Settings pre-ticks some needs', () {
      final b = completeBrief().copyWith(accessibilityConfirmed: false);
      final q = QuestionPlanner.next(
        b,
        BriefValidator.validate(b, testNow),
        PlannerState(),
        now: testNow,
        settingsNeeds: {AccessibilityNeed.visual},
      )!;
      expect(q.id, 'accessibility');
      expect(q.preselected, contains('visual'));
    });
  });

  group('answer applier', () {
    test('rejects a group that does not add up', () {
      final b = completeBrief();
      final q = QuestionCatalog.build('group', b, now: testNow);
      final res = AnswerApplier.apply(
        b,
        q,
        const GroupAnswer(adults: 2, seniors: 0, children: 1, women: 0, childAges: [5]),
        testNow,
      );
      expect(res.isOk, isFalse);
      expect(res.error, contains('adds up'));
    });

    test('rejects dates in the past', () {
      final b = completeBrief();
      final q = QuestionCatalog.build('dates', b, now: testNow);
      final res = AnswerApplier.apply(
        b,
        q,
        DateRangeAnswer(DateTime(2026, 9, 1, 9), DateTime(2026, 9, 3, 9)),
        testNow,
      );
      expect(res.error, contains('past'));
    });

    test('“No” to a confirmation clears the value so it is asked properly', () {
      final b = completeBrief().copyWith(uncertain: {BriefField.dates});
      final q = QuestionCatalog.build('confirm.dates', b, now: testNow);
      final res = AnswerApplier.apply(b, q, const BoolAnswer(false), testNow);
      expect(res.brief!.start, isNull);
      expect(res.brief!.uncertain, isEmpty);
      expect(nextQuestion(res.brief!)!.id, 'dates');
    });

    test('selecting a new need drops follow-ups for a need that was removed', () {
      final b = completeBrief().copyWith(
        accessibilityNeeds: {AccessibilityNeed.wheelchair},
        accessibilityDetails: {'a11y.wheelchair.type': {'manual'}},
      );
      final q = QuestionCatalog.build('accessibility', b, now: testNow);
      final res = AnswerApplier.apply(
        b,
        q,
        const MultiChoiceAnswer({'hearing'}, ['Hearing']),
        testNow,
      );
      expect(res.brief!.accessibilityDetails, isEmpty);
    });

    test('skip leaves the brief untouched', () {
      final b = completeBrief();
      final q = QuestionCatalog.build('style', b, now: testNow);
      final res = AnswerApplier.apply(
        b,
        q,
        const ChoiceAnswer(QuestionCatalog.skipId, 'Skip'),
        testNow,
      );
      expect(res.brief!.style, isNull);
    });
  });
}
