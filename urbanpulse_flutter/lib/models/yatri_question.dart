import 'package:flutter/widgets.dart';

import 'trip_brief.dart';

/// How the agent wants a question answered — ordered by the spec's preference:
/// options first, free text last.
enum AnswerWidget {
  mcq,
  cta,
  yesNo,
  multiSelect,
  dateTimeRange,
  groupStepper,
  budgetRange,
  text,
}

/// Why a question is being asked.
enum IssueKind { conflict, invalid, unconfirmed, missing, optional, edit }

class QuestionOption {
  const QuestionOption({
    required this.id,
    required this.label,
    this.emoji,
    this.icon,
    this.subtitle,
    this.badge,
    this.exclusive = false,
    this.recommended = false,
  });

  final String id;
  final String label;
  final String? emoji;
  final IconData? icon;
  final String? subtitle;

  /// Short trailing tag, e.g. a CO2 figure.
  final String? badge;

  /// Selecting it clears the other options (e.g. "None").
  final bool exclusive;
  final bool recommended;
}

/// One question the receptionist agent puts to the traveler.
class YatriQuestion {
  const YatriQuestion({
    required this.id,
    required this.fields,
    required this.widget,
    required this.defaultText,
    this.options = const [],
    this.preselected = const {},
    this.prefill = const {},
    this.text,
    this.hint,
    this.reason = IssueKind.missing,
    this.attempt = 0,
    this.skippable = false,
  });

  final String id;
  final List<BriefField> fields;
  final AnswerWidget widget;
  final List<QuestionOption> options;
  final Set<String> preselected;

  /// Widget-specific starting values (stepper counts, date range, budget…).
  final Map<String, Object?> prefill;

  /// Deterministic wording. Always present so the loop never depends on the
  /// model for phrasing.
  final String defaultText;

  /// The model's warmer phrasing of [defaultText], when it produced one.
  final String? text;

  /// A validation or conflict message shown in the error colour.
  final String? hint;
  final IssueKind reason;
  final int attempt;
  final bool skippable;

  String get displayText => text ?? defaultText;

  YatriQuestion copyWith({
    String? text,
    String? hint,
    int? attempt,
    Map<String, Object?>? prefill,
    Set<String>? preselected,
  }) =>
      YatriQuestion(
        id: id,
        fields: fields,
        widget: widget,
        defaultText: defaultText,
        options: options,
        preselected: preselected ?? this.preselected,
        prefill: prefill ?? this.prefill,
        text: text ?? this.text,
        hint: hint ?? this.hint,
        reason: reason,
        attempt: attempt ?? this.attempt,
        skippable: skippable,
      );
}

/// A structured answer from a card. Free text never becomes an answer
/// directly — it goes through extraction.
sealed class YatriAnswer {
  const YatriAnswer();

  /// What the traveler's chat bubble says.
  String get displayLabel;
}

final class ChoiceAnswer extends YatriAnswer {
  const ChoiceAnswer(this.optionId, this.label);

  final String optionId;
  final String label;

  @override
  String get displayLabel => label;
}

final class MultiChoiceAnswer extends YatriAnswer {
  const MultiChoiceAnswer(this.optionIds, this.labels);

  final Set<String> optionIds;
  final List<String> labels;

  @override
  String get displayLabel => labels.isEmpty ? 'None' : labels.join(', ');
}

final class BoolAnswer extends YatriAnswer {
  const BoolAnswer(this.value);

  final bool value;

  @override
  String get displayLabel => value ? 'Yes' : 'No';
}

final class DateRangeAnswer extends YatriAnswer {
  const DateRangeAnswer(this.start, this.end);

  final DateTime start;
  final DateTime end;

  @override
  String get displayLabel => '${_d(start)} ${_t(start)} → ${_d(end)} ${_t(end)}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];

  static String _d(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  static String _t(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

final class GroupAnswer extends YatriAnswer {
  const GroupAnswer({
    required this.adults,
    required this.seniors,
    required this.children,
    required this.women,
    required this.childAges,
  });

  final int adults;
  final int seniors;
  final int children;
  final int women;
  final List<int> childAges;

  @override
  String get displayLabel {
    final parts = [
      if (adults > 0) '$adults adult${adults == 1 ? '' : 's'}',
      if (seniors > 0) '$seniors senior${seniors == 1 ? '' : 's'}',
      if (children > 0)
        '$children child${children == 1 ? '' : 'ren'}'
            '${childAges.isEmpty ? '' : ' (${childAges.join(', ')} yrs)'}',
    ];
    final women_ = women > 0 ? ' · $women women' : '';
    return '${parts.join(', ')}$women_';
  }
}

final class BudgetAnswer extends YatriAnswer {
  const BudgetAnswer(this.min, this.max);

  final int min;
  final int max;

  @override
  String get displayLabel => '₹$min – ₹$max';
}

final class TextAnswer extends YatriAnswer {
  const TextAnswer(this.text);

  final String text;

  @override
  String get displayLabel => text;
}
