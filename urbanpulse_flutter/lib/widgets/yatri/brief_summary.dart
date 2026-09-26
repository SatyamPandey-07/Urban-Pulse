import '../../core/formatting.dart';
import '../../models/trip_brief.dart';
import '../../models/yatri_question.dart';

/// Human-readable label / value rows for a brief, shared by the review card
/// and the review form header.
List<(String, String)> briefSummaryRows(TripBrief b) {
  String? dates() => b.start == null || b.end == null
      ? null
      : '${DateRangeAnswer(b.start!, b.end!).displayLabel} · ${b.days} day${b.days == 1 ? '' : 's'}';

  final group = b.hasPartsBreakdown
      ? GroupAnswer(
          adults: b.adults!,
          seniors: b.seniors!,
          children: b.children!,
          women: b.women ?? 0,
          childAges: b.childAges,
        ).displayLabel
      : null;

  final rows = <(String, String?)>[
    ('Destination', b.destination),
    ('From', b.originCity),
    ('Dates', dates()),
    ('Travellers', group ?? b.travellerCount?.toString()),
    (
      'Budget',
      b.budgetMaxInr == null
          ? null
          : '${rupees(b.budgetMinInr ?? 0)} – ${rupees(b.budgetMaxInr!)}',
    ),
    (
      'Transport',
      b.transportModes.isEmpty
          ? null
          : b.transportModes.map((m) => m.label).join(', '),
    ),
    (
      'Accessibility',
      b.accessibilityNeeds.isEmpty
          ? null
          : b.accessibilityNeeds.map((n) => n.label).join(', '),
    ),
    (
      'Safety',
      b.womenSafety.isEmpty ? null : b.womenSafety.map((s) => s.label).join(', '),
    ),
  ];
  return [
    for (final (label, value) in rows)
      if (value != null && value.isNotEmpty) (label, value),
  ];
}
