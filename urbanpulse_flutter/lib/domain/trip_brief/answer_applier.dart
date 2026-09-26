import '../../models/trip_brief.dart';
import '../../models/yatri_question.dart';
import 'accessibility_followups.dart';
import 'brief_validator.dart';
import 'question_catalog.dart';

class ApplyResult {
  const ApplyResult.ok(TripBrief this.brief) : error = null;
  const ApplyResult.error(String this.error) : brief = null;

  final TripBrief? brief;
  final String? error;

  bool get isOk => brief != null;
}

/// Applies a structured card answer to the brief. Widget answers are trusted
/// as the traveler's explicit intent, so they clear any "unconfirmed" flag.
abstract final class AnswerApplier {
  static T? _byName<T extends Enum>(List<T> values, String id) {
    for (final v in values) {
      if (v.name == id) return v;
    }
    return null;
  }

  static Set<T> _enums<T extends Enum>(List<T> values, Set<String> ids) => {
    for (final id in ids)
      if (_byName(values, id) case final v?) v,
  };

  static TripBrief _confirmed(TripBrief b, BriefField f) =>
      b.copyWith(uncertain: {...b.uncertain}..remove(f));

  static ApplyResult apply(
    TripBrief brief,
    YatriQuestion q,
    YatriAnswer a,
    DateTime now,
  ) {
    // "Skip" on an optional question leaves the brief untouched.
    if (a is ChoiceAnswer && a.optionId == QuestionCatalog.skipId) {
      return ApplyResult.ok(brief);
    }

    if (q.id.startsWith('confirm.')) {
      final field = q.fields.first;
      if (a is! BoolAnswer) return const ApplyResult.error('Please answer yes or no.');
      return ApplyResult.ok(
        a.value ? _confirmed(brief, field) : _confirmed(brief.clearing(field), field),
      );
    }

    if (q.id.startsWith('a11y.')) return _followUp(brief, q, a);

    switch (q.id) {
      case 'destination':
        final v = _text(a);
        if (v == null) return const ApplyResult.error('Please pick or type a destination.');
        return ApplyResult.ok(
          _confirmed(brief.copyWith(destination: v), BriefField.destination),
        );

      case 'origin':
        final v = _text(a);
        if (v == null) return const ApplyResult.error('Please pick or type a city.');
        return ApplyResult.ok(
          _confirmed(brief.copyWith(originCity: v), BriefField.origin),
        );

      case 'dates':
        if (a is! DateRangeAnswer) return const ApplyResult.error('Please choose your dates.');
        final next = _confirmed(
          brief.copyWith(start: a.start, end: a.end),
          BriefField.dates,
        );
        final problem = BriefValidator.validate(next, now)
            .forField(BriefField.dates)
            .where((i) => i.kind == IssueKind.invalid)
            .firstOrNull;
        return problem == null
            ? ApplyResult.ok(next)
            : ApplyResult.error(problem.message);

      case 'travellers':
        final n = a is ChoiceAnswer ? int.tryParse(a.optionId) : null;
        if (n == null) return const ApplyResult.error('Please choose the group size.');
        return ApplyResult.ok(
          _confirmed(brief.copyWith(travellerCount: n), BriefField.travellers),
        );

      case 'group':
        if (a is! GroupAnswer) return const ApplyResult.error('Please fill in the group.');
        final next = brief.copyWith(
          adults: a.adults,
          seniors: a.seniors,
          children: a.children,
          women: a.women,
          childAges: a.childAges,
        );
        final problem = BriefValidator.groupIssues(next).firstOrNull;
        return problem == null
            ? ApplyResult.ok(next)
            : ApplyResult.error(problem.message);

      case 'womenSafety':
        if (a is! MultiChoiceAnswer || a.optionIds.isEmpty) {
          return const ApplyResult.error('Pick at least one option.');
        }
        final prefs = _enums(WomenSafetyPref.values, a.optionIds);
        if (prefs.contains(WomenSafetyPref.none) && prefs.length > 1) {
          return const ApplyResult.error(
            '“No specific preferences” can’t be combined with others.',
          );
        }
        return ApplyResult.ok(brief.copyWith(womenSafety: prefs));

      case 'accessibility':
        if (a is! MultiChoiceAnswer || a.optionIds.isEmpty) {
          return const ApplyResult.error('Pick at least one option (or “No accessibility needs”).');
        }
        final needs = _enums(AccessibilityNeed.values, a.optionIds);
        if (needs.contains(AccessibilityNeed.none) && needs.length > 1) {
          return const ApplyResult.error(
            '“No accessibility needs” can’t be combined with other needs.',
          );
        }
        final keep = {
          for (final f in AccessibilityFollowUps.forNeeds(needs)) f.id,
        };
        return ApplyResult.ok(
          brief.copyWith(
            accessibilityNeeds: needs,
            accessibilityConfirmed: true,
            accessibilityDetails: {
              for (final e in brief.accessibilityDetails.entries)
                if (keep.contains(e.key)) e.key: e.value,
            },
          ),
        );

      case 'transport':
        if (a is! MultiChoiceAnswer || a.optionIds.isEmpty) {
          return const ApplyResult.error('Pick at least one way to travel.');
        }
        return ApplyResult.ok(
          _confirmed(
            brief.copyWith(
              transportModes: _enums(TripTransportMode.values, a.optionIds),
            ),
            BriefField.transport,
          ),
        );

      case 'budget':
        if (a is! BudgetAnswer) return const ApplyResult.error('Please choose a budget.');
        if (a.max < 500) return const ApplyResult.error('Budget must be at least ₹500.');
        if (a.min > a.max) {
          return const ApplyResult.error('The minimum can’t be higher than the maximum.');
        }
        return ApplyResult.ok(
          _confirmed(
            brief.copyWith(budgetMinInr: a.min, budgetMaxInr: a.max),
            BriefField.budget,
          ),
        );

      case 'style':
        final v = a is ChoiceAnswer ? _byName(TripStyle.values, a.optionId) : null;
        return v == null ? ApplyResult.ok(brief) : ApplyResult.ok(brief.copyWith(style: v));
      case 'pace':
        final v = a is ChoiceAnswer ? _byName(TripPace.values, a.optionId) : null;
        return v == null ? ApplyResult.ok(brief) : ApplyResult.ok(brief.copyWith(pace: v));
      case 'stay':
        return a is MultiChoiceAnswer
            ? ApplyResult.ok(
                brief.copyWith(stayTypes: _enums(StayType.values, a.optionIds)),
              )
            : ApplyResult.ok(brief);
      case 'dietary':
        return a is MultiChoiceAnswer
            ? ApplyResult.ok(
                brief.copyWith(dietary: _enums(Dietary.values, a.optionIds)),
              )
            : ApplyResult.ok(brief);
    }
    return ApplyResult.error('Unexpected question: ${q.id}');
  }

  static String? _text(YatriAnswer a) {
    final raw = switch (a) {
      ChoiceAnswer() => a.optionId,
      TextAnswer() => a.text,
      _ => null,
    };
    final v = raw?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  static ApplyResult _followUp(TripBrief brief, YatriQuestion q, YatriAnswer a) {
    final chosen = switch (a) {
      ChoiceAnswer() => {a.optionId},
      MultiChoiceAnswer() => a.optionIds,
      _ => <String>{},
    };
    final valid = {for (final o in q.options) o.id};
    final ids = chosen.where(valid.contains).toSet();
    if (ids.isEmpty) return const ApplyResult.error('Pick at least one option.');
    return ApplyResult.ok(
      brief.copyWith(
        accessibilityDetails: {...brief.accessibilityDetails, q.id: ids},
      ),
    );
  }
}
