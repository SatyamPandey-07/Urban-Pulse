import '../../models/trip_brief.dart';
import '../../models/yatri_question.dart';
import 'accessibility_followups.dart';
import 'brief_validator.dart';
import 'question_catalog.dart';

/// Conversation bookkeeping the planner needs beyond the brief itself.
class PlannerState {
  PlannerState();

  /// Failed attempts per question id, so a stubborn question escalates.
  final Map<String, int> attempts = {};

  /// Whether the next-best-question step has already run (it is consulted at
  /// most once per conversation to keep token use low), and the optional
  /// questions it chose that are still waiting to be asked.
  bool nbaConsulted = false;
  final List<String> nbaQueue = [];

  void reset() {
    attempts.clear();
    nbaConsulted = false;
    nbaQueue.clear();
  }
}

/// Decides the next question to ask. Priority: conflicts and invalid values
/// first, then values that still need confirming, then missing mandatory
/// fields in registry order, then the one-time optional offer.
abstract final class QuestionPlanner {
  /// Registry order of question ids; follow-ups sort right after their parent.
  static const _order = [
    'destination',
    'origin',
    'dates',
    'travellers',
    'group',
    'childAges',
    'women',
    'womenSafety',
    'accessibility',
    'transport',
    'budget',
  ];

  static int _rank(BriefIssue i) => switch (i.kind) {
    IssueKind.conflict || IssueKind.invalid => 0,
    IssueKind.unconfirmed => 1,
    _ => 2,
  };

  static int _position(String questionId) {
    final base = questionId.startsWith('confirm.')
        ? questionId.substring('confirm.'.length)
        : questionId.startsWith('a11y.')
        ? 'accessibility'
        : questionId;
    final idx = _order.indexOf(base);
    // Follow-ups slot in just after `accessibility`, before `transport`.
    final within = questionId.startsWith('a11y.')
        ? AccessibilityFollowUps.all.indexWhere((f) => f.id == questionId) + 1
        : 0;
    return (idx < 0 ? _order.length : idx) * 100 + within;
  }

  /// The most urgent unresolved issue, or null when the brief is complete.
  static BriefIssue? nextIssue(ValidationReport report) {
    if (report.issues.isEmpty) return null;
    final sorted = [...report.issues]
      ..sort((a, b) {
        final byRank = _rank(a).compareTo(_rank(b));
        if (byRank != 0) return byRank;
        return _position(a.questionId).compareTo(_position(b.questionId));
      });
    return sorted.first;
  }

  static YatriQuestion? next(
    TripBrief brief,
    ValidationReport report,
    PlannerState state, {
    required DateTime now,
    String? detectedCity,
    Set<AccessibilityNeed> settingsNeeds = const {},
  }) {
    final issue = nextIssue(report);
    if (issue != null) {
      final attempt = state.attempts[issue.questionId] ?? 0;
      return QuestionCatalog.build(
        issue.questionId,
        brief,
        now: now,
        reason: issue.kind,
        hint: issue.message,
        attempt: attempt,
        detectedCity: detectedCity,
        settingsNeeds: settingsNeeds,
      );
    }

    // Mandatory fields are all valid: only questions the next-best-question
    // step chose remain.
    if (state.nbaQueue.isNotEmpty) {
      return QuestionCatalog.build(state.nbaQueue.first, brief, now: now);
    }
    return null;
  }
}
