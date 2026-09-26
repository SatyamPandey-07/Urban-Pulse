import 'dart:convert';

import '../../models/trip_brief.dart';
import 'extraction.dart';
import 'question_catalog.dart';

/// The "next best question" step. Once every mandatory field is valid the
/// agent may ask up to [maxAsks] more questions — but only when the brief is
/// thin enough that they would change the plan, and only after one small model
/// call. The choice is always restricted to [QuestionCatalog.optionalIds].
abstract final class NextBestQuestion {
  static const maxAsks = 2;

  /// Optional questions the traveller has not answered yet, in menu order.
  static List<String> candidates(TripBrief b) => [
    for (final id in QuestionCatalog.optionalIds)
      if (switch (id) {
        'style' => b.style == null,
        'pace' => b.pace == null,
        'stay' => b.stayTypes.isEmpty,
        'dietary' => b.dietary.isEmpty,
        _ => false,
      })
        id,
  ];

  /// A brief that already carries most optional detail is "rich": nothing left
  /// to ask is worth a model call.
  static bool worthConsulting(TripBrief b) => candidates(b).length >= 2;

  /// The ids the model chose: only real candidates, no repeats, at most
  /// [maxAsks], in the order it gave them. Anything unparseable means "ask
  /// nothing".
  static List<String> parse(String raw, List<String> candidates) {
    final sub = ExtractionParser.jsonSubstring(raw);
    if (sub == null) return const [];
    try {
      final decoded = jsonDecode(sub);
      final ask = decoded is Map<String, dynamic> ? decoded['ask'] : null;
      if (ask is! List) return const [];
      final out = <String>[];
      for (final id in ask) {
        if (id is String && candidates.contains(id) && !out.contains(id)) {
          out.add(id);
          if (out.length == maxAsks) break;
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
