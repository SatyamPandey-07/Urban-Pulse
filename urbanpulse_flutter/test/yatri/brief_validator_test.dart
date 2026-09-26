import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/domain/trip_brief/brief_validator.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/models/yatri_question.dart';

import 'test_support.dart';

ValidationReport validate(TripBrief b) => BriefValidator.validate(b, testNow);

void main() {
  test('a complete brief has no issues and counts every required field', () {
    final report = validate(completeBrief());
    expect(report.issues, isEmpty);
    expect(report.isComplete, isTrue);
    expect(report.satisfied, report.required);
  });

  test('an empty brief is missing every mandatory field', () {
    final report = validate(TripBrief.empty(testNow));
    final ids = report.issues.map((i) => i.questionId).toSet();
    expect(
      ids,
      containsAll([
        'destination', 'origin', 'dates', 'travellers', 'group', //
        'accessibility', 'transport', 'budget', //
      ]),
    );
    expect(report.satisfied, 0);
  });

  group('dates', () {
    test('a start in the past is invalid', () {
      final b = completeBrief().copyWith(start: DateTime(2026, 10, 1, 9));
      expect(validate(b).forField(BriefField.dates).single.kind, IssueKind.invalid);
    });

    test('an end before the start is invalid', () {
      final b = completeBrief().copyWith(
        start: DateTime(2026, 10, 12, 9),
        end: DateTime(2026, 10, 10, 18),
      );
      expect(validate(b).hasIssueFor(BriefField.dates), isTrue);
    });

    test('more than 60 days is invalid', () {
      final b = completeBrief().copyWith(end: DateTime(2026, 12, 30, 18));
      expect(validate(b).hasIssueFor(BriefField.dates), isTrue);
    });

    test('a flagged-uncertain date asks for confirmation', () {
      final b = completeBrief().copyWith(uncertain: {BriefField.dates});
      final issue = validate(b).forField(BriefField.dates).single;
      expect(issue.kind, IssueKind.unconfirmed);
      expect(issue.questionId, 'confirm.dates');
    });

    test('days and nights are inclusive calendar days', () {
      final b = completeBrief();
      expect(b.days, 4);
      expect(b.nights, 3);
    });
  });

  group('group breakdown', () {
    test('a total that no longer matches the parts is a conflict', () {
      final b = completeBrief().copyWith(travellerCount: 5);
      final issue = validate(b).forField(BriefField.group).single;
      expect(issue.kind, IssueKind.conflict);
      expect(issue.message, contains('5'));
    });

    test('children without an adult or senior are invalid', () {
      final b = completeBrief().copyWith(
        adults: 0,
        seniors: 0,
        children: 4,
        childAges: const [1, 2, 3, 4],
      );
      expect(validate(b).forField(BriefField.group).single.kind, IssueKind.invalid);
    });

    test('each child needs an age between 0 and 17', () {
      expect(
        validate(completeBrief().copyWith(childAges: const [6])).hasIssueFor(BriefField.group),
        isTrue,
      );
      expect(
        validate(completeBrief().copyWith(childAges: const [6, 21])).hasIssueFor(BriefField.group),
        isTrue,
      );
    });

    test('more women than travellers is invalid', () {
      final b = completeBrief().copyWith(women: 9);
      expect(validate(b).hasIssueFor(BriefField.group), isTrue);
    });
  });

  group('women safety', () {
    test('is only required when women are travelling', () {
      final none = completeBrief().copyWith(women: 0, womenSafety: const {});
      expect(validate(none).hasIssueFor(BriefField.womenSafety), isFalse);

      final some = completeBrief().copyWith(womenSafety: const {});
      expect(validate(some).hasIssueFor(BriefField.womenSafety), isTrue);
    });
  });

  group('accessibility', () {
    test('unconfirmed needs (e.g. pre-ticked from settings) still count as missing', () {
      final b = completeBrief().copyWith(accessibilityConfirmed: false);
      expect(validate(b).hasIssueFor(BriefField.accessibility), isTrue);
    });

    test('“none” cannot be combined with other needs', () {
      final b = completeBrief().copyWith(
        accessibilityNeeds: {AccessibilityNeed.none, AccessibilityNeed.visual},
      );
      expect(validate(b).forField(BriefField.accessibility).first.kind, IssueKind.invalid);
    });

    test('every selected need requires its own follow-up', () {
      final b = completeBrief().copyWith(
        accessibilityNeeds: {AccessibilityNeed.wheelchair, AccessibilityNeed.visual},
      );
      final ids = validate(b).issues.map((i) => i.questionId).toSet();
      expect(ids, containsAll([
        'a11y.wheelchair.type',
        'a11y.wheelchair.facilities',
        'a11y.visual.support',
      ]));
    });

    test('sensory/cognitive and other special needs get their own follow-ups', () {
      final b = completeBrief().copyWith(
        accessibilityNeeds: {AccessibilityNeed.cognitiveSensory, AccessibilityNeed.otherSpecial},
      );
      final ids = validate(b).issues.map((i) => i.questionId).toSet();
      expect(ids, containsAll(['a11y.cognitive.support', 'a11y.otherSpecial.support']));

      final done = b.copyWith(accessibilityDetails: {
        'a11y.cognitive.support': {'quiet_low_crowd'},
        'a11y.otherSpecial.support': {'rest_breaks'},
      });
      expect(validate(done).isComplete, isTrue);
    });

    test('answering a follow-up removes its issue', () {
      var b = completeBrief().copyWith(
        accessibilityNeeds: {AccessibilityNeed.serviceAnimal},
      );
      expect(validate(b).hasIssueFor(BriefField.accessibilityDetails), isTrue);
      b = b.copyWith(accessibilityDetails: {'a11y.serviceAnimal.type': {'guide_dog'}});
      expect(validate(b).hasIssueFor(BriefField.accessibilityDetails), isFalse);
    });
  });

  group('budget & other fields', () {
    test('min above max is invalid', () {
      final b = completeBrief().copyWith(budgetMinInr: 50000, budgetMaxInr: 40000);
      expect(validate(b).hasIssueFor(BriefField.budget), isTrue);
    });

    test('destination equal to origin is a conflict', () {
      final b = completeBrief().copyWith(destination: 'pune');
      expect(validate(b).forField(BriefField.destination).single.kind, IssueKind.conflict);
    });

    test('a tight budget and flights only warn — they never block', () {
      final b = completeBrief().copyWith(
        budgetMinInr: 0,
        budgetMaxInr: 5000,
        transportModes: const {TripTransportMode.flight},
      );
      final report = validate(b);
      expect(report.isComplete, isTrue);
      expect(report.warnings, hasLength(2));
    });
  });

  test('TripBrief survives a JSON round trip', () {
    final original = completeBrief().copyWith(
      accessibilityNeeds: {AccessibilityNeed.wheelchair},
      accessibilityDetails: {'a11y.wheelchair.type': {'manual'}},
      stayTypes: {StayType.ecoStay},
      style: TripStyle.family,
      uncertain: {BriefField.dates},
      notes: 'Window seat please',
    );
    final copy = TripBrief.fromJson(original.toJson());
    expect(copy.toJson(), original.toJson());
  });
}
