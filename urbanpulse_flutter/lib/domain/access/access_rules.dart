import '../../agents/runtime/report.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';

/// Turns raw evidence (OpenStreetMap tags, listing text) into per-need
/// accessibility support. Pure and deterministic: no model involved. Anything
/// the evidence does not speak to stays [SupportLevel.unknown] rather than
/// being guessed; a model may later fill it, labelled as an estimate.
abstract final class AccessRules {
  /// Needs worth evaluating (everything except "none").
  static Set<AccessibilityNeed> relevant(Iterable<AccessibilityNeed> needs) =>
      {for (final n in needs) if (n != AccessibilityNeed.none) n};

  // --- OpenStreetMap tags ---------------------------------------------------

  /// What a place's OSM [tags] say about each need in [needs].
  static Map<AccessibilityNeed, NeedSupport> fromOsmTags(
    Map<String, String> tags,
    Iterable<AccessibilityNeed> needs, {
    required Provenance provenance,
  }) {
    final out = <AccessibilityNeed, NeedSupport>{};
    String v(String k) => (tags[k] ?? '').toLowerCase().trim();

    final wheelchair = v('wheelchair');
    final toiletWc = v('toilets:wheelchair');
    final elevator = v('elevator') == 'yes' || v('lift') == 'yes';
    final steps = v('step_count');
    final tactile = v('tactile_paving');
    final braille = v('tactile_writing:braille') == 'yes' || v('braille') == 'yes';
    final hearingLoop = v('hearing_loop') == 'yes' || v('deaf') == 'yes' || v('hearing_impaired') == 'yes';
    final dog = v('dog');

    NeedSupport s(AccessibilityNeed n, SupportLevel l, [String detail = '']) =>
        NeedSupport(need: n, level: l, detail: detail, provenance: provenance);

    for (final need in relevant(needs)) {
      switch (need) {
        case AccessibilityNeed.wheelchair:
          out[need] = switch (wheelchair) {
            'yes' || 'designated' => s(need, SupportLevel.yes, [
              'Fully wheelchair accessible',
              if (toiletWc == 'yes') 'with an accessible toilet',
              if (elevator) 'and a lift',
            ].join(' ')),
            'limited' => s(need, SupportLevel.partial, 'Only partly wheelchair accessible${steps.isNotEmpty ? ' ($steps steps)' : ''}'),
            'no' => s(need, SupportLevel.no, 'Marked as not wheelchair accessible'),
            _ when elevator => s(need, SupportLevel.partial, 'Has a lift; step-free entrance not confirmed'),
            _ => s(need, SupportLevel.unknown),
          };
        case AccessibilityNeed.limitedMobility:
          out[need] = switch (wheelchair) {
            'yes' || 'designated' => s(need, SupportLevel.yes, 'Step-free access reported'),
            'limited' => s(need, SupportLevel.partial, 'Some steps or uneven access'),
            'no' => s(need, SupportLevel.no, 'Steps or difficult access reported'),
            _ when elevator => s(need, SupportLevel.partial, 'Has a lift'),
            _ => s(need, SupportLevel.unknown),
          };
        case AccessibilityNeed.elderlyCare:
          out[need] = (wheelchair == 'yes' || wheelchair == 'designated')
              ? s(need, SupportLevel.yes, 'Step-free access reported')
              : (elevator || wheelchair == 'limited')
              ? s(need, SupportLevel.partial, elevator ? 'Has a lift' : 'Partly step-free')
              : wheelchair == 'no'
              ? s(need, SupportLevel.no, 'Steps or difficult access reported')
              : s(need, SupportLevel.unknown);
        case AccessibilityNeed.visual:
          out[need] = braille
              ? s(need, SupportLevel.yes, 'Braille or tactile signage')
              : tactile == 'yes'
              ? s(need, SupportLevel.partial, 'Tactile paving present')
              : s(need, SupportLevel.unknown);
        case AccessibilityNeed.hearing:
          out[need] = hearingLoop
              ? s(need, SupportLevel.yes, 'Hearing support reported')
              : s(need, SupportLevel.unknown);
        case AccessibilityNeed.serviceAnimal:
          out[need] = switch (dog) {
            'yes' => s(need, SupportLevel.yes, 'Dogs welcome'),
            'leashed' => s(need, SupportLevel.yes, 'Dogs welcome on a lead'),
            'no' => s(need, SupportLevel.partial, 'Pets are not allowed; service animals usually still are, confirm first'),
            _ => s(need, SupportLevel.unknown),
          };
        case AccessibilityNeed.cognitiveSensory:
        case AccessibilityNeed.otherSpecial:
          out[need] = s(need, SupportLevel.unknown);
        case AccessibilityNeed.none:
          break;
      }
    }
    return out;
  }

  // --- Listing text ---------------------------------------------------------

  static final _negWheelchair = RegExp(
    r"\b(not|no|isn'?t|non)\b[\s-]{0,3}[^.,;\n]{0,25}wheelchair|\bno (elevators?|lifts?)\b|stairs only|steep stairs|only accessible by stairs",
    caseSensitive: false,
  );
  static final _yesWheelchair = RegExp(
    r'wheelchair[\s-]*(accessible|access|friendly)|accessible (rooms?|bathrooms?|guest rooms?|entrance)|roll-?in shower|step[\s-]?free|barrier[\s-]?free',
    caseSensitive: false,
  );
  static final _partialMobility = RegExp(r'\b(elevators?|lifts?|ramps?|ground floor|grab bars?)\b', caseSensitive: false);
  static final _visual = RegExp(r'braille|tactile|audio (guide|description)|large[\s-]?print|guide dogs? (are )?(welcome|allowed)', caseSensitive: false);
  static final _hearing = RegExp(
    r'hearing (loop|aid|impaired)|visual (alarms?|alerts?|doorbell)|sign language|closed[\s-]?captions?|\bTTY\b|\bTDD\b',
    caseSensitive: false,
  );
  static final _animalYes = RegExp(r'service (animals?|dogs?) (are )?(welcome|allowed)|pets? (are )?allowed|pet[\s-]?friendly|dogs? (are )?welcome', caseSensitive: false);
  static final _animalNo = RegExp(r'no pets|pets (are )?not allowed|no animals', caseSensitive: false);
  static final _sensory = RegExp(r'sensory[\s-]?friendly|quiet rooms?|calm (space|room)|low[\s-]?crowd|autism[\s-]?friendly|noise[\s-]?free', caseSensitive: false);
  static final _elder = RegExp(r'\b(elevators?|lifts?|ground floor|24[\s-]?hour (front )?desk|doctor on call|medical)\b', caseSensitive: false);

  /// What listing or review [text] says about each need in [needs]. Negations
  /// ("not wheelchair accessible", "no lift") are honoured and win over
  /// positives, since a listing that mentions accessibility but says "not" is
  /// the dangerous case.
  static Map<AccessibilityNeed, NeedSupport> fromText(
    String text,
    Iterable<AccessibilityNeed> needs, {
    required Provenance provenance,
  }) {
    final out = <AccessibilityNeed, NeedSupport>{};
    String? hit(RegExp r) => r.firstMatch(text)?.group(0)?.trim();

    NeedSupport s(AccessibilityNeed n, SupportLevel l, String detail) =>
        NeedSupport(need: n, level: l, detail: detail, provenance: provenance);

    final neg = hit(_negWheelchair);
    final yes = hit(_yesWheelchair);
    final part = hit(_partialMobility);

    for (final need in relevant(needs)) {
      switch (need) {
        case AccessibilityNeed.wheelchair:
        case AccessibilityNeed.limitedMobility:
          if (neg != null) {
            out[need] = s(need, SupportLevel.no, 'The listing says: “$neg”');
          } else if (yes != null) {
            out[need] = s(need, SupportLevel.yes, 'The listing mentions “$yes”');
          } else if (part != null) {
            out[need] = s(need, SupportLevel.partial, 'The listing mentions “$part”; step-free access is not confirmed');
          }
        case AccessibilityNeed.elderlyCare:
          if (neg != null) {
            out[need] = s(need, SupportLevel.no, 'The listing says: “$neg”');
          } else if (yes != null || hit(_elder) != null) {
            out[need] = s(need, SupportLevel.partial, 'The listing mentions “${yes ?? hit(_elder)}”');
          }
        case AccessibilityNeed.visual:
          final m = hit(_visual);
          if (m != null) out[need] = s(need, SupportLevel.partial, 'The listing mentions “$m”');
        case AccessibilityNeed.hearing:
          final m = hit(_hearing);
          if (m != null) out[need] = s(need, SupportLevel.partial, 'The listing mentions “$m”');
        case AccessibilityNeed.serviceAnimal:
          final no = hit(_animalNo);
          final ok = hit(_animalYes);
          if (ok != null) {
            out[need] = s(need, SupportLevel.yes, 'The listing mentions “$ok”');
          } else if (no != null) {
            out[need] = s(need, SupportLevel.partial, 'Pets are not allowed (“$no”); service animals usually still are, confirm first');
          }
        case AccessibilityNeed.cognitiveSensory:
          final m = hit(_sensory);
          if (m != null) out[need] = s(need, SupportLevel.partial, 'The listing mentions “$m”');
        case AccessibilityNeed.otherSpecial:
        case AccessibilityNeed.none:
          break;
      }
    }
    return out;
  }

  // --- Combining evidence ---------------------------------------------------

  /// How much a source is trusted; used to break ties between evidence.
  static double weight(NeedSupport s) {
    if (s.level == SupportLevel.unknown) return -1;
    final base = s.provenance.confidence;
    return s.provenance.isEstimated ? base * 0.5 : base;
  }

  /// Merges two readings of the same need. Real sources beat estimates; two
  /// real sources that disagree (one says yes, one says no) become "partly"
  /// with the disagreement spelled out, so nobody is told it is fine when it
  /// might not be.
  static NeedSupport merge(NeedSupport a, NeedSupport b) {
    if (a.level == SupportLevel.unknown) return b;
    if (b.level == SupportLevel.unknown) return a;

    final aReal = !a.provenance.isEstimated;
    final bReal = !b.provenance.isEstimated;
    if (aReal != bReal) return aReal ? a : b;

    // A "no" from one real source against any kind of "yes" from another is a
    // disagreement worth flagging, not something to average away.
    bool positive(SupportLevel l) => l == SupportLevel.yes || l == SupportLevel.partial;
    final opposite =
        (positive(a.level) && b.level == SupportLevel.no) ||
        (a.level == SupportLevel.no && positive(b.level));
    if (opposite) {
      return NeedSupport(
        need: a.need,
        level: SupportLevel.partial,
        detail: 'Sources disagree: ${a.provenance.source} says '
            '${a.level.label.toLowerCase()}, ${b.provenance.source} says ${b.level.label.toLowerCase()}. Confirm before booking.',
        provenance: a.provenance.copyWith(confidence: a.provenance.confidence < b.provenance.confidence ? a.provenance.confidence : b.provenance.confidence),
      );
    }
    return weight(a) >= weight(b) ? a : b;
  }

  /// Combines several evidence maps, need by need.
  static Map<AccessibilityNeed, NeedSupport> mergeAll(Iterable<Map<AccessibilityNeed, NeedSupport>> maps) {
    final out = <AccessibilityNeed, NeedSupport>{};
    for (final m in maps) {
      for (final e in m.entries) {
        final prev = out[e.key];
        out[e.key] = prev == null ? e.value : merge(prev, e.value);
      }
    }
    return out;
  }
}
