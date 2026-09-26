import '../../models/trip_brief.dart';
import '../../models/yatri_question.dart';
import 'accessibility_followups.dart';

/// A problem with the brief that means a question has to be (re-)asked.
class BriefIssue {
  const BriefIssue({
    required this.field,
    required this.questionId,
    required this.kind,
    required this.message,
  });

  final BriefField field;
  final String questionId;
  final IssueKind kind;
  final String message;

  @override
  String toString() => '$questionId/${kind.name}: $message';
}

class ValidationReport {
  const ValidationReport({
    required this.issues,
    required this.warnings,
    required this.satisfied,
    required this.required,
  });

  final List<BriefIssue> issues;
  final List<String> warnings;

  /// How many of the [required] mandatory answers are currently valid.
  final int satisfied;
  final int required;

  bool get isComplete => issues.isEmpty;

  bool hasIssueFor(BriefField field) => issues.any((i) => i.field == field);

  Iterable<BriefIssue> forField(BriefField field) =>
      issues.where((i) => i.field == field);
}

/// Pure, deterministic validation of a [TripBrief]. This — not the language
/// model — decides what is missing, invalid or in conflict, so the intake loop
/// always terminates and is unit-testable.
abstract final class BriefValidator {
  static const minLead = Duration(hours: 2);
  static const maxDays = 60;
  static const maxTravellers = 50;

  static ValidationReport validate(TripBrief b, DateTime now) {
    final issues = <BriefIssue>[];
    final warnings = <String>[];
    var required = 0;
    var satisfied = 0;

    void check(BriefField field, String qid, List<BriefIssue> found) {
      required++;
      if (found.isEmpty) {
        satisfied++;
      } else {
        issues.addAll(found);
      }
    }

    BriefIssue issue(
      BriefField f,
      String qid,
      IssueKind k,
      String message,
    ) => BriefIssue(field: f, questionId: qid, kind: k, message: message);

    // --- destination -------------------------------------------------------
    final dest = b.destination?.trim();
    final origin = b.originCity?.trim();
    check(BriefField.destination, 'destination', [
      if (dest == null || dest.isEmpty)
        issue(BriefField.destination, 'destination', IssueKind.missing,
            'Where would you like to go?')
      else if (dest.length < 2 || dest.length > 60)
        issue(BriefField.destination, 'destination', IssueKind.invalid,
            'That destination doesn’t look right — try a place name.')
      else if (origin != null &&
          origin.isNotEmpty &&
          origin.toLowerCase() == dest.toLowerCase())
        issue(BriefField.destination, 'destination', IssueKind.conflict,
            'Your destination and starting city are both $dest.')
      else if (b.uncertain.contains(BriefField.destination))
        issue(BriefField.destination, 'confirm.destination',
            IssueKind.unconfirmed, 'Please confirm the destination.'),
    ]);

    // --- origin ------------------------------------------------------------
    check(BriefField.origin, 'origin', [
      if (origin == null || origin.isEmpty)
        issue(BriefField.origin, 'origin', IssueKind.missing,
            'Where will you start from?')
      else if (origin.length < 2 || origin.length > 60)
        issue(BriefField.origin, 'origin', IssueKind.invalid,
            'That city doesn’t look right — try a city name.')
      else if (b.uncertain.contains(BriefField.origin))
        issue(BriefField.origin, 'confirm.origin', IssueKind.unconfirmed,
            'Please confirm the starting city.'),
    ]);

    // --- dates -------------------------------------------------------------
    check(BriefField.dates, 'dates', _dateIssues(b, now));

    // --- travellers --------------------------------------------------------
    final total = b.travellerCount;
    check(BriefField.travellers, 'travellers', [
      if (total == null)
        issue(BriefField.travellers, 'travellers', IssueKind.missing,
            'How many people are travelling?')
      else if (total < 1 || total > maxTravellers)
        issue(BriefField.travellers, 'travellers', IssueKind.invalid,
            'Group size must be between 1 and $maxTravellers.')
      else if (b.uncertain.contains(BriefField.travellers))
        issue(BriefField.travellers, 'confirm.travellers',
            IssueKind.unconfirmed, 'Please confirm the group size.'),
    ]);

    // --- group breakdown ---------------------------------------------------
    check(BriefField.group, 'group', groupIssues(b));

    // --- women's safety (only when women are travelling) -------------------
    if ((b.women ?? 0) > 0) {
      check(BriefField.womenSafety, 'womenSafety', [
        if (b.womenSafety.isEmpty)
          issue(BriefField.womenSafety, 'womenSafety', IssueKind.missing,
              'Any safety preferences for the women travelling?')
        else if (b.womenSafety.contains(WomenSafetyPref.none) &&
            b.womenSafety.length > 1)
          issue(BriefField.womenSafety, 'womenSafety', IssueKind.invalid,
              '“No specific preferences” can’t be combined with others.'),
      ]);
    }

    // --- accessibility (always asked) -------------------------------------
    check(BriefField.accessibility, 'accessibility', [
      if (!b.accessibilityConfirmed || b.accessibilityNeeds.isEmpty)
        issue(BriefField.accessibility, 'accessibility', IssueKind.missing,
            'Does anyone in the group have accessibility needs?')
      else if (b.accessibilityNeeds.contains(AccessibilityNeed.none) &&
          b.accessibilityNeeds.length > 1)
        issue(BriefField.accessibility, 'accessibility', IssueKind.invalid,
            '“No accessibility needs” can’t be combined with other needs.'),
    ]);

    // --- per-need follow-ups ----------------------------------------------
    if (b.accessibilityConfirmed) {
      for (final f in AccessibilityFollowUps.forNeeds(b.accessibilityNeeds)) {
        final chosen = b.accessibilityDetails[f.id];
        check(BriefField.accessibilityDetails, f.id, [
          if (chosen == null || chosen.isEmpty)
            issue(BriefField.accessibilityDetails, f.id, IssueKind.missing,
                f.text),
        ]);
      }
    }

    // --- transport ---------------------------------------------------------
    check(BriefField.transport, 'transport', [
      if (b.transportModes.isEmpty)
        issue(BriefField.transport, 'transport', IssueKind.missing,
            'How would you like to travel?')
      else if (b.uncertain.contains(BriefField.transport))
        issue(BriefField.transport, 'confirm.transport', IssueKind.unconfirmed,
            'Please confirm the transport modes.'),
    ]);

    // --- budget ------------------------------------------------------------
    final bMin = b.budgetMinInr;
    final bMax = b.budgetMaxInr;
    check(BriefField.budget, 'budget', [
      if (bMax == null)
        issue(BriefField.budget, 'budget', IssueKind.missing,
            'What’s your budget for the whole trip?')
      else if (bMax < 500)
        issue(BriefField.budget, 'budget', IssueKind.invalid,
            'Budget must be at least ₹500.')
      else if (bMin != null && bMin > bMax)
        issue(BriefField.budget, 'budget', IssueKind.invalid,
            'The minimum budget can’t be higher than the maximum.')
      else if (b.uncertain.contains(BriefField.budget))
        issue(BriefField.budget, 'confirm.budget', IssueKind.unconfirmed,
            'Please confirm the budget.'),
    ]);

    // --- non-blocking warnings --------------------------------------------
    if (bMax != null && total != null && b.days > 0) {
      final floor = total * b.days * 800;
      if (bMax < floor) {
        warnings.add(
          'That budget is tight for $total travellers over ${b.days} days.',
        );
      }
    }
    if (b.transportModes.contains(TripTransportMode.flight)) {
      warnings.add('Flights emit far more CO₂ per passenger than trains.');
    }

    return ValidationReport(
      issues: issues,
      warnings: warnings,
      satisfied: satisfied,
      required: required,
    );
  }

  static List<BriefIssue> _dateIssues(TripBrief b, DateTime now) {
    BriefIssue issue(IssueKind k, String message) => BriefIssue(
      field: BriefField.dates,
      questionId: k == IssueKind.unconfirmed ? 'confirm.dates' : 'dates',
      kind: k,
      message: message,
    );

    final s = b.start;
    final e = b.end;
    if (s == null || e == null) {
      return [issue(IssueKind.missing, 'When are you travelling?')];
    }
    if (s.isBefore(now)) {
      return [issue(IssueKind.invalid, 'The start time is in the past.')];
    }
    if (s.isAfter(now.add(const Duration(days: 365)))) {
      return [
        issue(IssueKind.invalid, 'Trips can be planned up to a year ahead.'),
      ];
    }
    if (e.isBefore(s.add(minLead))) {
      return [
        issue(IssueKind.invalid, 'The trip must end after it starts.'),
      ];
    }
    if (b.days > maxDays) {
      return [issue(IssueKind.invalid, 'Trips can be at most $maxDays days.')];
    }
    if (b.uncertain.contains(BriefField.dates)) {
      return [issue(IssueKind.unconfirmed, 'Please confirm the dates.')];
    }
    return const [];
  }

  /// Issues with the traveller breakdown. Each part is its own question so the
  /// agent only asks for what it could not work out: the adult / senior /
  /// child split (`group`), the children's ages (`childAges`) and how many
  /// travellers are women (`women`). Also used by the answer applier to reject
  /// a bad stepper submission.
  static List<BriefIssue> groupIssues(TripBrief b) {
    BriefIssue issue(String qid, IssueKind k, String message) => BriefIssue(
      field: BriefField.group,
      questionId: qid,
      kind: k,
      message: message,
    );

    if (!b.hasPartsBreakdown) {
      return [
        issue(
          'group',
          IssueKind.missing,
          'Who’s travelling — adults, seniors, children?',
        ),
      ];
    }
    final adults = b.adults!;
    final seniors = b.seniors!;
    final children = b.children!;
    final total = b.travellerCount;

    if (adults < 0 || seniors < 0 || children < 0 || (b.women ?? 0) < 0) {
      return [issue('group', IssueKind.invalid, 'Counts can’t be negative.')];
    }
    if (adults + seniors < 1) {
      return [
        issue(
          'group',
          IssueKind.invalid,
          'At least one adult or senior has to travel with the group.',
        ),
      ];
    }
    final sum = adults + seniors + children;
    if (total != null && sum != total) {
      return [
        issue(
          'group',
          IssueKind.conflict,
          'You now have $total travellers but the group adds up to $sum.',
        ),
      ];
    }
    if (b.childAges.any((a) => a < 0 || a > 17)) {
      return [
        issue('childAges', IssueKind.invalid, 'Child ages must be between 0 and 17.'),
      ];
    }
    if (b.childAges.length != children) {
      return [
        issue(
          'childAges',
          IssueKind.missing,
          children == 1
              ? 'How old is the child?'
              : 'How old are the children?',
        ),
      ];
    }
    final women = b.women;
    if (women == null) {
      return [
        issue('women', IssueKind.missing, 'Are any of the travellers women?'),
      ];
    }
    if (women > sum) {
      return [
        issue(
          'women',
          IssueKind.invalid,
          'Women can’t be more than the whole group.',
        ),
      ];
    }
    return const [];
  }
}
