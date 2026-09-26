import 'dart:convert';

import '../../models/trip_brief.dart';

/// One value the model pulled out of free text, with how sure it was.
class Extracted {
  const Extracted(this.value, {this.confidence = 1, this.timeAssumed = false});

  final Object value;
  final double confidence;

  /// The model filled in a default time-of-day the user never stated.
  final bool timeAssumed;
}

/// What the receptionist model returned for one user message.
class Extraction {
  const Extraction({
    this.updates = const {},
    this.pendingOptionIds,
    this.pendingBool,
    this.clarify,
    this.offTopic = false,
    this.ack,
  });

  static const empty = Extraction();

  /// JSON key -> coerced value. See [ExtractionParser.keys].
  final Map<String, Extracted> updates;

  /// The user's message answered the question currently on screen.
  final Set<String>? pendingOptionIds;
  final bool? pendingBool;

  /// A short clarifying question the model wants to ask instead of guessing.
  final String? clarify;
  final bool offTopic;
  final String? ack;

  bool get isEmpty =>
      updates.isEmpty && pendingOptionIds == null && pendingBool == null;
}

/// Tolerant JSON -> [Extraction] parsing. Models wrap JSON in prose or code
/// fences, return strings for numbers and invent enum ids; none of that may
/// leak into the brief.
abstract final class ExtractionParser {
  static const stringKeys = {'destination', 'originCity', 'notes'};
  static const dateKeys = {'start', 'end'};
  static const intKeys = {
    'travellerCount',
    'adults',
    'seniors',
    'children',
    'women',
    'budgetMinInr',
    'budgetMaxInr',
  };
  static const keys = {
    ...stringKeys,
    ...dateKeys,
    ...intKeys,
    'childAges',
    'transportModes',
    'accessibilityNeeds',
    'womenSafety',
    'stayTypes',
    'dietary',
    'style',
    'pace',
    'sustainability',
  };

  /// First `{` to last `}` — same guard the itinerary parser uses.
  static String? jsonSubstring(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return raw.substring(start, end + 1);
  }

  static Extraction parse(String raw) {
    final sub = jsonSubstring(raw);
    if (sub == null) return Extraction.empty;
    final Object? decoded;
    try {
      decoded = jsonDecode(sub);
    } catch (_) {
      return Extraction.empty;
    }
    if (decoded is! Map<String, dynamic>) return Extraction.empty;

    final updates = <String, Extracted>{};
    final rawUpdates = decoded['updates'];
    if (rawUpdates is Map<String, dynamic>) {
      for (final key in keys) {
        final item = rawUpdates[key];
        if (item == null) continue;
        var value = item;
        var confidence = 1.0;
        var timeAssumed = false;
        if (item is Map<String, dynamic> && item.containsKey('value')) {
          value = item['value'];
          confidence = (item['confidence'] as num?)?.toDouble() ?? 1.0;
          timeAssumed = item['timeAssumed'] == true;
        }
        final coerced = _coerce(key, value);
        if (coerced == null) continue;
        updates[key] = Extracted(
          coerced,
          confidence: confidence.clamp(0.0, 1.0),
          timeAssumed: timeAssumed,
        );
      }
    }

    Set<String>? pendingIds;
    bool? pendingBool;
    final pending = decoded['pendingAnswer'];
    if (pending is Map<String, dynamic>) {
      final ids = pending['optionIds'];
      if (ids is List) pendingIds = {for (final i in ids) i.toString()};
      if (pending['bool'] is bool) pendingBool = pending['bool'] as bool;
    }

    String? text(Object? v) {
      final s = v is String ? v.trim() : null;
      return (s == null || s.isEmpty) ? null : s;
    }

    return Extraction(
      updates: updates,
      pendingOptionIds: pendingIds,
      pendingBool: pendingBool,
      clarify: text(decoded['clarify']),
      offTopic: decoded['offTopic'] == true,
      ack: text(decoded['ack']),
    );
  }

  static Object? _coerce(String key, Object? v) {
    if (stringKeys.contains(key)) {
      final s = v is String ? v.trim() : null;
      if (s == null || s.isEmpty) return null;
      return s.length > 300 ? s.substring(0, 300) : s;
    }
    if (dateKeys.contains(key)) {
      return v is String ? DateTime.tryParse(v.trim()) : null;
    }
    if (intKeys.contains(key)) return _int(v);
    switch (key) {
      case 'childAges':
        if (v is! List) return null;
        final ages = [for (final a in v) ?_int(a)];
        return ages.length == v.length ? ages : null;
      case 'transportModes':
        return _enumSet(TripTransportMode.values, v);
      case 'accessibilityNeeds':
        return _enumSet(AccessibilityNeed.values, v);
      case 'womenSafety':
        return _enumSet(WomenSafetyPref.values, v);
      case 'stayTypes':
        return _enumSet(StayType.values, v);
      case 'dietary':
        return _enumSet(Dietary.values, v);
      case 'style':
        return _enumOne(TripStyle.values, v);
      case 'pace':
        return _enumOne(TripPace.values, v);
      case 'sustainability':
        return _enumOne(SustainabilityPriority.values, v);
    }
    return null;
  }

  static int? _int(Object? v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static T? _enumOne<T extends Enum>(List<T> values, Object? v) {
    if (v is! String) return null;
    final want = v.trim().toLowerCase();
    for (final e in values) {
      if (e.name.toLowerCase() == want) return e;
    }
    return null;
  }

  static Set<T>? _enumSet<T extends Enum>(List<T> values, Object? v) {
    if (v is! List) return null;
    final out = <T>{
      for (final x in v)
        if (_enumOne(values, x) case final e?) e,
    };
    return out.isEmpty ? null : out;
  }
}
