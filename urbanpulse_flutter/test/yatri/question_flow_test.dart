import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/receptionist/receptionist_agent.dart';
import 'package:urbanpulse/domain/trip_brief/answer_applier.dart';
import 'package:urbanpulse/domain/trip_brief/brief_merger.dart';
import 'package:urbanpulse/domain/trip_brief/brief_validator.dart';
import 'package:urbanpulse/domain/trip_brief/extraction.dart';
import 'package:urbanpulse/domain/trip_brief/next_best.dart';
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

  group('smart group dynamics', () {
    TripBrief mergeText(String json, [TripBrief? from]) => BriefMerger.apply(
      from ?? TripBrief.empty(testNow),
      ExtractionParser.parse(json),
    ).brief;

    test('“4 men” fills the whole breakdown, so the group form is never asked', () {
      final b = mergeText(
        '{"updates": {"destination": "Goa", "travellerCount": 4, "adults": 4, "seniors": 0, "children": 0, "women": 0}}',
      );
      expect(b.hasGroupBreakdown, isTrue);
      expect(BriefValidator.validate(b, testNow).hasIssueFor(BriefField.group), isFalse);
    });

    test('adults that make up the whole party imply no seniors or children', () {
      // The model only stated adults; the rest follows from the total.
      final b = mergeText('{"updates": {"travellerCount": 4, "adults": 4, "women": 0}}');
      expect((b.adults, b.seniors, b.children), (4, 0, 0));
      expect(BriefValidator.validate(b, testNow).hasIssueFor(BriefField.group), isFalse);
    });

    test('“3 friends” asks only how many are women', () {
      final b = mergeText(
        '{"updates": {"travellerCount": 3, "adults": 3, "seniors": 0, "children": 0}}',
      );
      final issues = BriefValidator.validate(b, testNow).forField(BriefField.group);
      expect(issues.map((i) => i.questionId), ['women']);
      final q = QuestionCatalog.build('women', b, now: testNow);
      expect(q.options.map((o) => o.id), ['0', '1', '2', '3']);
      expect(q.options.last.label, 'All 3 are women');
    });

    test('children without ages ask only for the ages', () {
      final b = mergeText(
        '{"updates": {"travellerCount": 4, "adults": 2, "seniors": 0, "children": 2, "women": 1}}',
      );
      final issues = BriefValidator.validate(b, testNow).forField(BriefField.group);
      expect(issues.map((i) => i.questionId), ['childAges']);

      final q = QuestionCatalog.build('childAges', b, now: testNow);
      final res = AnswerApplier.apply(b, q, const AgesAnswer([4, 9]), testNow);
      expect(res.brief!.childAges, [4, 9]);
      expect(
        AnswerApplier.apply(b, q, const AgesAnswer([4]), testNow).isOk,
        isFalse,
        reason: 'one age for two children',
      );
    });

    test('“family of 4” is still ambiguous and asks the group question', () {
      final b = mergeText('{"updates": {"travellerCount": 4}}');
      final issues = BriefValidator.validate(b, testNow).forField(BriefField.group);
      expect(issues.map((i) => i.questionId), ['group']);
    });

    test('a partial breakdown that does not fill the party stays ambiguous', () {
      final b = mergeText('{"updates": {"travellerCount": 4, "adults": 2}}');
      expect(b.hasPartsBreakdown, isFalse);
      final q = QuestionCatalog.build('group', b, now: testNow);
      expect(q.prefill['adults'], 2);
    });

    test('answering the women question completes the group', () {
      final b = mergeText(
        '{"updates": {"travellerCount": 3, "adults": 3, "seniors": 0, "children": 0}}',
      );
      final q = QuestionCatalog.build('women', b, now: testNow);
      final res = AnswerApplier.apply(b, q, const ChoiceAnswer('1', '1 woman'), testNow);
      expect(BriefValidator.validate(res.brief!, testNow).hasIssueFor(BriefField.group), isFalse);
      expect(res.brief!.women, 1);
    });
  });

  group('next best question', () {
    test('candidates are the optional topics not yet answered', () {
      expect(NextBestQuestion.candidates(TripBrief.empty(testNow)),
          ['style', 'pace', 'stay', 'dietary']);
      final b = TripBrief.empty(testNow).copyWith(style: TripStyle.family, pace: TripPace.relaxed);
      expect(NextBestQuestion.candidates(b), ['stay', 'dietary']);
    });

    test('a rich brief is not worth a model call', () {
      final rich = TripBrief.empty(testNow).copyWith(
        style: TripStyle.family,
        pace: TripPace.relaxed,
        stayTypes: {StayType.homestay},
      );
      expect(NextBestQuestion.worthConsulting(rich), isFalse);
      expect(NextBestQuestion.worthConsulting(TripBrief.empty(testNow)), isTrue);
    });

    test('parse keeps valid, unique candidates and caps the count at two', () {
      const candidates = ['style', 'pace', 'stay', 'dietary'];
      expect(
        NextBestQuestion.parse('{"ask": ["pace", "bogus", "pace", "stay", "dietary"]}', candidates),
        ['pace', 'stay'],
      );
      expect(NextBestQuestion.parse('```json\n{"ask": ["style"]}\n```', candidates), ['style']);
      expect(NextBestQuestion.parse('{"ask": []}', candidates), isEmpty);
      expect(NextBestQuestion.parse('nonsense', candidates), isEmpty);
      expect(NextBestQuestion.parse('{"ask": ["style"]}', ['pace']), isEmpty);
    });
  });

  group('widget choice allow-list', () {
    test('only listed flavours are accepted', () {
      expect(QuestionCatalog.validVariant('dates', 'presets'), 'presets');
      expect(QuestionCatalog.validVariant('dates', 'holographic'), isNull);
      expect(QuestionCatalog.validVariant('destination', 'calendar'), isNull);
      expect(QuestionCatalog.validVariant('budget', null), isNull);
    });

    test('phrasing keeps the message and a valid widget, drops an invalid one', () {
      final ok = ReceptionistAgent.parsePhrasing(
        '{"message": "When are you heading out?", "widget": "presets"}',
        'dates',
      )!;
      expect((ok.message, ok.widget), ('When are you heading out?', 'presets'));
      final bad = ReceptionistAgent.parsePhrasing(
        '{"message": "How many?", "widget": "presets"}',
        'travellers',
      )!;
      expect(bad.widget, isNull);
      expect(ReceptionistAgent.parsePhrasing('{"widget": "list"}', 'travellers'), isNull);
    });

    test('every question that allows a choice defaults to its first flavour', () {
      for (final id in ['dates', 'budget', 'travellers']) {
        final q = QuestionCatalog.build(id, TripBrief.empty(testNow), now: testNow);
        expect(q.variant, QuestionCatalog.variantsFor(id).first, reason: id);
      }
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

    test('a complete brief has nothing left to ask until the model picks optional questions', () {
      expect(nextQuestion(completeBrief(), PlannerState()), isNull);
    });

    test('questions the next-best step chose are asked in order', () {
      final state = PlannerState()..nbaQueue.addAll(['pace', 'stay']);
      final q = nextQuestion(completeBrief(), state)!;
      expect(q.id, 'pace');
      expect(q.skippable, isTrue);
      expect(q.reason, IssueKind.optional);
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
