import 'dart:math' as math;

import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../atithi/hotel_candidate.dart';

/// How much a rest day is lightened.
enum RestLevel {
  /// A late start, an early finish and at most two places.
  light,

  /// Nothing scheduled: a free day.
  free,
}

/// One change to a finished plan. The language model only ever produces these
/// (validated); deterministic code applies them by calling the same engines
/// that built the plan.
sealed class EditOp {
  const EditOp();

  /// A short line for the feed and the edit log.
  String describe();
}

/// "More rest on Day 2": fewer places, a shorter day; what no longer fits moves
/// to another (preferably later) day.
class RestDayOp extends EditOp {
  const RestDayOp(this.day, this.level);

  final int day;
  final RestLevel level;

  @override
  String describe() => level == RestLevel.free ? 'make day $day a free day' : 'lighten day $day';
}

class MoveStopOp extends EditOp {
  const MoveStopOp(this.placeId, this.toDay);

  final String placeId;
  final int toDay;

  @override
  String describe() => 'move a stop to day $toDay';
}

/// Replace a stop with something else: a named place, or the best fit for a
/// description ("something outdoors", "something cheaper", "a viewpoint").
class SwapStopOp extends EditOp {
  const SwapStopOp(this.placeId, {this.withPlaceId, this.withName, this.wish});

  final String placeId;

  /// A place already in the plan's pool.
  final String? withPlaceId;

  /// A place by name, to be looked up.
  final String? withName;

  /// Free-text wish ("something indoors").
  final String? wish;

  @override
  String describe() => 'replace a stop';
}

class RemoveStopOp extends EditOp {
  const RemoveStopOp(this.placeId);

  final String placeId;

  @override
  String describe() => 'remove a stop';
}

class AddStopOp extends EditOp {
  const AddStopOp({this.placeId, this.name, this.day});

  /// A place already known to the plan.
  final String? placeId;

  /// Or a place by name, to be looked up.
  final String? name;
  final int? day;

  @override
  String describe() => 'add ${name ?? 'a place'}';
}

class LockStopOp extends EditOp {
  const LockStopOp(this.placeId, {this.lock = true});

  final String placeId;
  final bool lock;

  @override
  String describe() => lock ? 'lock a stop in place' : 'unlock a stop';
}

/// A different stay: a named alternative, a search with new limits, or both.
class ChangeHotelOp extends EditOp {
  const ChangeHotelOp({this.hotelId, this.name, this.maxNightlyInr, this.needs = const {}, this.wish});

  final String? hotelId;
  final String? name;
  final int? maxNightlyInr;
  final Set<AccessibilityNeed> needs;
  final String? wish;

  @override
  String describe() => 'change the hotel';
}

class ChangeTransportOp extends EditOp {
  const ChangeTransportOp(this.mode);

  final TripTransportMode mode;

  @override
  String describe() => 'travel by ${mode.label.toLowerCase()}';
}

/// Longer or shorter trip, or new dates.
class ChangeDatesOp extends EditOp {
  const ChangeDatesOp({this.deltaDays, this.start, this.end, this.fillNew = true});

  /// Whether new days are filled with the best unused places (not when a place
  /// the traveller asked for is about to go there).
  final bool fillNew;
  final int? deltaDays;
  final DateTime? start;
  final DateTime? end;

  @override
  String describe() => deltaDays != null ? (deltaDays! > 0 ? 'add ${deltaDays!} day${deltaDays == 1 ? '' : 's'}' : 'remove ${-deltaDays!} day${deltaDays == -1 ? '' : 's'}') : 'change the dates';
}

class SetPreferencesOp extends EditOp {
  const SetPreferencesOp({this.pace, this.style, this.sustainability, this.budgetMaxInr, this.addNeeds = const {}, this.removeNeeds = const {}, this.budgetFactor});

  final TripPace? pace;
  final TripStyle? style;
  final SustainabilityPriority? sustainability;
  final int? budgetMaxInr;

  /// "Make it 20% cheaper" (0.8).
  final double? budgetFactor;
  final Set<AccessibilityNeed> addNeeds;
  final Set<AccessibilityNeed> removeNeeds;

  @override
  String describe() => 'change preferences';
}

/// A question about the plan, answered without changing it.
class ExplainOp extends EditOp {
  const ExplainOp({this.placeId, this.day});

  final String? placeId;
  final int? day;

  @override
  String describe() => 'explain';
}

/// One stop of the current plan, as the editor and the model see it.
class IndexedStop {
  const IndexedStop({required this.id, required this.name, required this.day, required this.kind, required this.start, required this.locked, this.why});

  final String id;
  final String name;

  /// 1-based.
  final int day;
  final SlotKind kind;
  final DateTime start;
  final bool locked;
  final String? why;
}

/// The finished plan as something an edit can point at. Builds the compact text
/// the model reads, and resolves the ways people refer to a stop ("the fort",
/// "day 2's museum", an id) to a real one.
class PlanIndex {
  PlanIndex(this.itinerary) : stops = _stops(itinerary);

  final Itinerary itinerary;
  final List<IndexedStop> stops;

  static List<IndexedStop> _stops(Itinerary it) {
    final pins = it.snapshot?.pins ?? const <String>{};
    final out = <IndexedStop>[];
    for (final d in it.days) {
      for (final s in d.slots) {
        if ((s.kind == SlotKind.visit || s.kind == SlotKind.meal) && s.refId != null) {
          out.add(IndexedStop(id: s.refId!, name: s.title, day: d.number, kind: s.kind, start: s.start, locked: pins.contains(s.refId), why: s.note));
        }
      }
    }
    return out;
  }

  List<IndexedStop> get visits => [for (final s in stops) if (s.kind == SlotKind.visit) s];

  IndexedStop? byId(String? id) => id == null ? null : stops.where((s) => s.id == id).firstOrNull;

  List<IndexedStop> onDay(int day) => [for (final s in stops) if (s.day == day) s];

  int get dayCount => itinerary.days.length;

  /// The stops a phrase could mean, best first. Exact id first, then names by
  /// similarity; a day hint ("day 2") narrows it.
  List<IndexedStop> resolve(String ref, {int? dayHint}) {
    final r = ref.trim();
    if (r.isEmpty) return const [];
    final exact = byId(r);
    if (exact != null) return [exact];
    final scored = <(IndexedStop, double)>[];
    for (final s in stops) {
      if (dayHint != null && s.day != dayHint) continue;
      final sim = HotelCandidates.similarity(s.name, r);
      final contains = s.name.toLowerCase().contains(r.toLowerCase()) || r.toLowerCase().contains(s.name.toLowerCase());
      final score = contains ? math.max(sim, 0.75) : sim;
      if (score >= 0.5) scored.add((s, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    // Several stops of the same place (a lunch and a visit) count once.
    final seen = <String>{};
    return [for (final e in scored) if (seen.add(e.$1.id)) e.$1];
  }

  /// The plan in a few lines, for the model. Ids are what the model must use.
  String digest() {
    final it = itinerary;
    final b = StringBuffer();
    b.writeln('Trip: ${it.destination}, ${it.days.length} days (${dateRangeLabel(it.start, it.end)}), from ${it.origin}.');
    final brief = it.brief;
    if (brief != null) {
      final needs = [for (final n in brief.accessibilityNeeds) if (n != AccessibilityNeed.none) n.name];
      b.writeln('Group: ${it.travellerSummary}. Access needs: ${needs.isEmpty ? 'none' : needs.join(', ')}. Pace: ${brief.pace?.name ?? 'balanced'}. Budget: ${brief.budgetMaxInr == null ? 'not set' : rupees(brief.budgetMaxInr!)}.');
    }
    b.writeln('Stay: ${it.hotel?.name ?? 'none'}${it.hotel?.nightlyInr == null ? '' : ' (${rupees(it.hotel!.nightlyInr!)}/night)'}. Alternatives: ${it.hotelAlternatives.take(4).map((h) => '[${h.id}] ${h.name}').join('; ')}.');
    b.writeln('Journey: ${it.chosenTransport?.mode.label ?? 'none'}. Total cost now ${rupees(it.budget.totalInr)}.');
    for (final d in it.days) {
      final line = [
        for (final s in d.slots)
          if ((s.kind == SlotKind.visit || s.kind == SlotKind.meal) && s.refId != null) '[${s.refId}] ${s.title} (${s.kind == SlotKind.meal ? 'meal' : 'visit'} ${clock12(s.start)}${(it.snapshot?.pins.contains(s.refId) ?? false) ? ', locked' : ''})',
      ];
      b.writeln('Day ${d.number} ${shortDate(d.date)}: ${line.isEmpty ? '(free)' : line.join('; ')}');
    }
    final spare = [
      for (final h in (it.snapshot?.pool ?? const <Hotspot>[]))
        if (!stops.any((s) => s.id == h.id)) h,
    ].take(10);
    if (spare.isNotEmpty) b.writeln('Other places available: ${spare.map((h) => '[${h.id}] ${h.name} (${h.kind.name}${h.isOutdoor ? ', outdoor' : ', indoor'})').join('; ')}.');
    return b.toString();
  }
}
