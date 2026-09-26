import '../../models/trip_brief.dart';
import 'extraction.dart';

/// A value the traveler changed after it was already set — used to acknowledge
/// corrections ("Updated travellers 4 → 5").
class BriefChange {
  const BriefChange(this.label, this.from, this.to);

  final String label;
  final String from;
  final String to;

  @override
  String toString() => '$label: $from → $to';
}

class MergeResult {
  const MergeResult(this.brief, this.changes);

  final TripBrief brief;
  final List<BriefChange> changes;
}

/// Folds a model [Extraction] into the brief. Extraction is deliberately
/// weak: it may fill or correct values, but it never confirms accessibility
/// and low-confidence values stay flagged until the traveler confirms them.
abstract final class BriefMerger {
  static const confidenceFloor = 0.7;

  static MergeResult apply(TripBrief brief, Extraction ex) {
    var b = brief;
    final changes = <BriefChange>[];
    final uncertain = {...b.uncertain};

    void mark(BriefField f, Extracted e, {bool assumedTime = false}) {
      if (e.confidence < confidenceFloor || (assumedTime && e.timeAssumed)) {
        uncertain.add(f);
      } else {
        uncertain.remove(f);
      }
    }

    void changed(String label, Object? from, Object? to) {
      if (from != null && '$from' != '$to') {
        changes.add(BriefChange(label, '$from', '$to'));
      }
    }

    final u = ex.updates;

    if (u['destination'] case final e?) {
      final v = e.value as String;
      changed('Destination', b.destination, v);
      b = b.copyWith(destination: v);
      mark(BriefField.destination, e);
    }
    if (u['originCity'] case final e?) {
      final v = e.value as String;
      changed('Starting city', b.originCity, v);
      b = b.copyWith(originCity: v);
      mark(BriefField.origin, e);
    }

    if (u['start'] != null || u['end'] != null) {
      final s = u['start'];
      final e = u['end'];
      final newStart = s?.value as DateTime? ?? b.start;
      var newEnd = e?.value as DateTime? ?? b.end;
      // A start with no end: assume the same evening so a range exists to
      // confirm; the traveler is asked to confirm it because of `timeAssumed`.
      newEnd ??= newStart == null
          ? null
          : DateTime(newStart.year, newStart.month, newStart.day, 18);
      if (newStart != null && newEnd != null) {
        if (b.start != null && b.start != newStart) {
          changed('Start', b.start, newStart);
        }
        b = b.copyWith(start: newStart, end: newEnd);
        final anyLow = [s, e].whereType<Extracted>().any(
          (x) => x.confidence < confidenceFloor || x.timeAssumed,
        );
        if (anyLow || e == null && s != null) {
          uncertain.add(BriefField.dates);
        } else {
          uncertain.remove(BriefField.dates);
        }
      }
    }

    if (u['travellerCount'] case final e?) {
      final v = e.value as int;
      changed('Travellers', b.travellerCount, v);
      b = b.copyWith(travellerCount: v);
      mark(BriefField.travellers, e);
    }

    // Group breakdown — merged field by field; the validator decides whether
    // the parts add up, so a changed total surfaces as a conflict.
    if (u['adults'] != null ||
        u['seniors'] != null ||
        u['children'] != null ||
        u['women'] != null ||
        u['childAges'] != null) {
      b = b.copyWith(
        adults: u['adults']?.value as int? ?? b.adults,
        seniors: u['seniors']?.value as int? ?? b.seniors,
        children: u['children']?.value as int? ?? b.children,
        women: u['women']?.value as int? ?? b.women,
        childAges: u['childAges']?.value as List<int>? ?? b.childAges,
      );
      if (b.travellerCount == null &&
          b.adults != null &&
          b.seniors != null &&
          b.children != null) {
        b = b.copyWith(travellerCount: b.adults! + b.seniors! + b.children!);
      }
    }

    if (u['budgetMinInr'] != null || u['budgetMaxInr'] != null) {
      final min = u['budgetMinInr'];
      final max = u['budgetMaxInr'];
      final newMax = max?.value as int? ?? b.budgetMaxInr;
      if (newMax != null) {
        changed('Budget', b.budgetMaxInr, newMax);
        b = b.copyWith(
          budgetMinInr: min?.value as int? ?? b.budgetMinInr ?? 0,
          budgetMaxInr: newMax,
        );
        final low = [min, max].whereType<Extracted>().any(
          (x) => x.confidence < confidenceFloor,
        );
        low ? uncertain.add(BriefField.budget) : uncertain.remove(BriefField.budget);
      }
    }

    if (u['transportModes'] case final e?) {
      b = b.copyWith(
        transportModes: (e.value as Set).cast<TripTransportMode>(),
      );
      mark(BriefField.transport, e);
    }

    if (u['accessibilityNeeds'] case final e?) {
      var needs = (e.value as Set).cast<AccessibilityNeed>();
      if (needs.length > 1) needs = needs.difference({AccessibilityNeed.none});
      // Extraction only pre-ticks: the traveler must still confirm.
      b = b.copyWith(
        accessibilityNeeds: needs,
        accessibilityConfirmed: false,
      );
    }

    if (u['womenSafety'] case final e?) {
      var prefs = (e.value as Set).cast<WomenSafetyPref>();
      if (prefs.length > 1) prefs = prefs.difference({WomenSafetyPref.none});
      b = b.copyWith(womenSafety: prefs);
    }

    if (u['style'] case final e?) b = b.copyWith(style: e.value as TripStyle);
    if (u['pace'] case final e?) b = b.copyWith(pace: e.value as TripPace);
    if (u['sustainability'] case final e?) {
      b = b.copyWith(sustainability: e.value as SustainabilityPriority);
    }
    if (u['stayTypes'] case final e?) {
      b = b.copyWith(stayTypes: (e.value as Set).cast<StayType>());
    }
    if (u['dietary'] case final e?) {
      b = b.copyWith(dietary: (e.value as Set).cast<Dietary>());
    }
    if (u['notes'] case final e?) b = b.copyWith(notes: e.value as String);

    return MergeResult(b.copyWith(uncertain: uncertain), changes);
  }
}
