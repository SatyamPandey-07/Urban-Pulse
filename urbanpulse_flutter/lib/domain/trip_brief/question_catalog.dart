import '../../models/trip_brief.dart';
import '../../models/yatri_question.dart';
import 'accessibility_followups.dart';

/// Builds the concrete [YatriQuestion] for a question id: wording, answer
/// widget, options and pre-fills. Everything here is deterministic — the model
/// may only re-phrase [YatriQuestion.defaultText], never change the contract.
abstract final class QuestionCatalog {
  static const popularDestinations = [
    'Lonavala', 'Alibaug', 'Matheran', 'Mahabaleshwar', 'Coorg', 'Munnar', 'Jaipur', 'Goa', 'Rishikesh', 'Hampi', 'Shillong',
  ];
  static const popularOrigins = [
    'Panvel', 'Mumbai', 'Pune', 'Delhi', 'Bengaluru', 'Chennai', 'Kolkata', 'Hyderabad',
  ];
  static const skipId = 'skip';

  /// Optional questions the agent may pick from once the mandatory ones are
  /// answered (see the next-best-question step).
  static const optionalIds = ['style', 'pace', 'stay', 'dietary'];

  /// The widget flavours the agent is allowed to choose per question; the
  /// first is the default. Anything else the model suggests is ignored.
  static const _variants = <String, List<String>>{
    'dates': ['calendar', 'presets'],
    'budget': ['tiers', 'slider'],
    'travellers': ['list', 'stepper'],
  };

  static List<String> variantsFor(String questionId) =>
      _variants[questionId] ?? const [];

  /// [wanted] if it is an allowed flavour for [questionId], else null.
  static String? validVariant(String questionId, String? wanted) =>
      wanted != null && variantsFor(questionId).contains(wanted) ? wanted : null;

  static YatriQuestion build(
    String id,
    TripBrief b, {
    required DateTime now,
    IssueKind reason = IssueKind.missing,
    String? hint,
    int attempt = 0,
    String? detectedCity,
    Set<AccessibilityNeed> settingsNeeds = const {},
  }) {
    final shownHint = reason == IssueKind.missing ? null : hint;

    if (id.startsWith('confirm.')) return _confirm(id, b, shownHint, attempt);
    if (id.startsWith('a11y.')) {
      return _followUp(id, b, reason, shownHint, attempt);
    }

    switch (id) {
      case 'destination':
        return YatriQuestion(
          id: id,
          fields: const [BriefField.destination],
          widget: AnswerWidget.mcq,
          defaultText: 'Where would you like to go?',
          hint: shownHint,
          reason: reason,
          attempt: attempt,
          options: [
            for (final d in popularDestinations)
              QuestionOption(id: d, label: d, emoji: '📍'),
          ],
        );
      case 'origin':
        return YatriQuestion(
          id: id,
          fields: const [BriefField.origin],
          widget: AnswerWidget.mcq,
          defaultText: 'Which city will you start from?',
          hint: shownHint,
          reason: reason,
          attempt: attempt,
          options: [
            if (detectedCity != null && detectedCity.isNotEmpty)
              QuestionOption(
                id: detectedCity,
                label: 'Use my location: $detectedCity',
                emoji: '🎯',
                recommended: true,
              ),
            for (final c in popularOrigins)
              if (c != detectedCity) QuestionOption(id: c, label: c, emoji: '🏙️'),
          ],
        );
      case 'dates':
        return YatriQuestion(
          id: id,
          fields: const [BriefField.dates],
          widget: AnswerWidget.dateTimeRange,
          defaultText: 'When are you travelling? Pick the dates and timings.',
          hint: shownHint,
          reason: reason,
          attempt: attempt,
          variant: 'calendar',
          prefill: {'now': now, 'start': b.start, 'end': b.end},
        );
      case 'travellers':
        return YatriQuestion(
          id: id,
          fields: const [BriefField.travellers],
          widget: AnswerWidget.mcq,
          defaultText: 'How many people are travelling in total?',
          hint: shownHint,
          reason: reason,
          attempt: attempt,
          variant: 'list',
          options: [
            const QuestionOption(id: '1', label: 'Just me', emoji: '🧍'),
            for (final n in [2, 3, 4, 5, 6])
              QuestionOption(id: '$n', label: '$n people', emoji: '👥'),
          ],
        );
      case 'group':
        final total = b.travellerCount ?? 1;
        return YatriQuestion(
          id: id,
          fields: const [BriefField.group],
          widget: AnswerWidget.groupStepper,
          defaultText:
              'Let’s break down the group of $total — who’s travelling?',
          hint: shownHint,
          reason: reason,
          attempt: attempt,
          prefill: {
            'total': total,
            'adults': b.adults ?? (total - (b.seniors ?? 0) - (b.children ?? 0)).clamp(0, total),
            'seniors': b.seniors ?? 0,
            'children': b.children ?? 0,
            'women': b.women ?? 0,
            'childAges': b.childAges,
          },
        );
      case 'womenSafety':
        return YatriQuestion(
          id: id,
          fields: const [BriefField.womenSafety],
          widget: AnswerWidget.multiSelect,
          defaultText:
              'Any safety preferences for the women travelling? Choose all that apply.',
          hint: shownHint,
          reason: reason,
          attempt: attempt,
          preselected: {for (final s in b.womenSafety) s.name},
          options: [
            for (final s in WomenSafetyPref.values)
              QuestionOption(
                id: s.name,
                label: s.label,
                emoji: s.emoji,
                exclusive: s == WomenSafetyPref.none,
              ),
          ],
        );
      case 'accessibility':
        final pre = {...b.accessibilityNeeds, ...settingsNeeds};
        return YatriQuestion(
          id: id,
          fields: const [BriefField.accessibility],
          widget: AnswerWidget.multiSelect,
          defaultText:
              'Does anyone have accessibility needs? Select all that apply — '
              'I’ll ask what helps for each one.',
          hint: shownHint,
          reason: reason,
          attempt: attempt,
          preselected: {for (final n in pre) n.name},
          options: [
            for (final n in AccessibilityNeed.values)
              QuestionOption(
                id: n.name,
                label: n.label,
                emoji: n.emoji,
                exclusive: n == AccessibilityNeed.none,
              ),
          ],
        );
      case 'transport':
        final pre = b.transportModes.isNotEmpty
            ? b.transportModes
            : {TripTransportMode.train, TripTransportMode.eBus};
        return YatriQuestion(
          id: id,
          fields: const [BriefField.transport],
          widget: AnswerWidget.multiSelect,
          defaultText:
              'How would you be happy to travel? Greener options are ticked.',
          hint: shownHint,
          reason: reason,
          attempt: attempt,
          preselected: {for (final m in pre) m.name},
          options: [
            for (final m in TripTransportMode.values)
              QuestionOption(
                id: m.name,
                label: m.label,
                emoji: m.emoji,
                badge: '~${m.gCo2PerPaxKm} g CO₂/km',
                recommended: m.isEco,
              ),
          ],
        );
      case 'budget':
        return YatriQuestion(
          id: id,
          fields: const [BriefField.budget],
          widget: AnswerWidget.budgetRange,
          defaultText: 'What’s your budget for the whole trip?',
          hint: shownHint,
          reason: reason,
          attempt: attempt,
          variant: 'tiers',
          prefill: {
            'people': b.travellerCount ?? 1,
            'days': b.days == 0 ? 1 : b.days,
            'min': b.budgetMinInr,
            'max': b.budgetMaxInr,
          },
        );
      case 'childAges':
        final kids = b.children ?? 0;
        return YatriQuestion(
          id: id,
          fields: const [BriefField.group],
          widget: AnswerWidget.childAges,
          defaultText: kids == 1
              ? 'How old is the child?'
              : 'How old are the $kids children?',
          hint: shownHint,
          reason: reason,
          attempt: attempt,
          prefill: {'children': kids, 'childAges': b.childAges},
        );
      case 'women':
        final total = b.travellerCount ?? 1;
        final shown = total < 5 ? total : 4;
        return YatriQuestion(
          id: id,
          fields: const [BriefField.group],
          widget: AnswerWidget.mcq,
          defaultText: 'Are any of the travellers women?',
          hint: shownHint,
          reason: reason,
          attempt: attempt,
          options: [
            const QuestionOption(id: '0', label: 'No women in the group'),
            for (var n = 1; n <= shown; n++)
              QuestionOption(
                id: '$n',
                label: n == total
                    ? (total == 1 ? 'Yes, I am a woman' : 'All $total are women')
                    : '$n ${n == 1 ? 'woman' : 'women'}',
              ),
            if (total > shown)
              QuestionOption(id: '$total', label: 'All $total are women'),
          ],
        );
      case 'style':
        return _optionalMcq(
          id, BriefField.style, 'What kind of trip is this?',
          [for (final v in TripStyle.values) (v.name, v.label, v.emoji)],
        );
      case 'pace':
        return _optionalMcq(
          id, BriefField.pace, 'What pace do you prefer?',
          [for (final v in TripPace.values) (v.name, v.label, v.emoji)],
        );
      case 'stay':
        return _optionalMulti(
          id, BriefField.stay, 'What kind of stay do you like?',
          [for (final v in StayType.values) (v.name, v.label, v.emoji)],
        );
      case 'dietary':
        return _optionalMulti(
          id, BriefField.dietary, 'Any food preferences?',
          [for (final v in Dietary.values) (v.name, v.label, v.emoji)],
        );
    }
    throw ArgumentError('Unknown question id: $id');
  }

  static YatriQuestion _optionalMcq(
    String id,
    BriefField field,
    String text,
    List<(String, String, String)> options,
  ) => YatriQuestion(
    id: id,
    fields: [field],
    widget: AnswerWidget.mcq,
    defaultText: text,
    reason: IssueKind.optional,
    skippable: true,
    options: [
      for (final (oid, label, emoji) in options)
        QuestionOption(id: oid, label: label, emoji: emoji),
    ],
  );

  static YatriQuestion _optionalMulti(
    String id,
    BriefField field,
    String text,
    List<(String, String, String)> options,
  ) => YatriQuestion(
    id: id,
    fields: [field],
    widget: AnswerWidget.multiSelect,
    defaultText: text,
    reason: IssueKind.optional,
    skippable: true,
    options: [
      for (final (oid, label, emoji) in options)
        QuestionOption(id: oid, label: label, emoji: emoji),
    ],
  );

  static YatriQuestion _followUp(
    String id,
    TripBrief b,
    IssueKind reason,
    String? hint,
    int attempt,
  ) {
    final f = AccessibilityFollowUps.byId(id);
    if (f == null) throw ArgumentError('Unknown follow-up: $id');
    return YatriQuestion(
      id: id,
      fields: const [BriefField.accessibilityDetails],
      widget: f.multi ? AnswerWidget.multiSelect : AnswerWidget.mcq,
      defaultText: f.text,
      options: f.options,
      preselected: b.accessibilityDetails[id] ?? const {},
      hint: hint,
      reason: reason,
      attempt: attempt,
    );
  }

  static YatriQuestion _confirm(
    String id,
    TripBrief b,
    String? hint,
    int attempt,
  ) {
    final field = id.substring('confirm.'.length);
    final (BriefField f, String text) = switch (field) {
      'destination' => (
        BriefField.destination,
        'I noted the destination as ${b.destination}. Is that right?',
      ),
      'origin' => (
        BriefField.origin,
        'I noted you’re starting from ${b.originCity}. Is that right?',
      ),
      'dates' => (
        BriefField.dates,
        'I noted ${b.start == null || b.end == null ? 'the dates' : DateRangeAnswer(b.start!, b.end!).displayLabel}. Is that right?',
      ),
      'travellers' => (
        BriefField.travellers,
        'I noted ${b.travellerCount} travellers. Is that right?',
      ),
      'transport' => (
        BriefField.transport,
        'I noted ${b.transportModes.map((m) => m.label).join(', ')}. Is that right?',
      ),
      'budget' => (
        BriefField.budget,
        'I noted a budget of ₹${b.budgetMinInr ?? 0} – ₹${b.budgetMaxInr}. Is that right?',
      ),
      _ => throw ArgumentError('Unknown confirm target: $id'),
    };
    return YatriQuestion(
      id: id,
      fields: [f],
      widget: AnswerWidget.yesNo,
      defaultText: text,
      hint: hint,
      reason: IssueKind.unconfirmed,
      attempt: attempt,
    );
  }
}
