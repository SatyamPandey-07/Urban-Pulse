import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../domain/opening_hours.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/itinerary/plan_snapshot.dart';
import '../../models/trip_brief.dart';
import '../../services/data/forecast_client.dart';
import '../../services/data/http_util.dart';
import '../bhatkanti/hotspot_finder.dart';
import '../raah/day_planner.dart';

/// What one operation did to the plan, in words.
class OpResult {
  const OpResult(this.ok, this.note);

  final bool ok;
  final String note;
}

/// A working copy of a finished plan that edits are applied to. Days are lists
/// of place ids (what goes where); the planner later lays each day out. The
/// copy is thrown away if the edit fails, so a failed edit never damages the
/// plan.
class EditState {
  EditState(Itinerary it)
    : brief = it.brief!,
      hotel = it.hotel,
      alternatives = [...it.hotelAlternatives],
      transportOptions = [...it.transportOptions],
      chosen = it.chosenTransport,
      weather = {...?it.snapshot?.weather},
      center = it.snapshot?.center,
      origin = it.snapshot?.origin,
      dropped = {...?it.snapshot?.droppedIds},
      banned = {...?it.snapshot?.bannedOutdoor},
      pins = {...?it.snapshot?.pins},
      windows = {...?it.snapshot?.dayWindows},
      caps = {...?it.snapshot?.dayStopCaps},
      pool = _poolOf(it),
      start = it.start,
      end = it.end {
    membership = _membershipOf(it);
    final firstPlace = pool.values.firstOrNull;
    center ??= it.hotel?.location ?? firstPlace?.location;
  }

  TripBrief brief;
  HotelOption? hotel;
  final List<HotelOption> alternatives;
  List<TransportLeg> transportOptions;
  TransportLeg? chosen;
  final Map<String, DayForecast> weather;
  LatLng? center;
  final LatLng? origin;
  final Set<String> dropped;
  final Set<String> banned;
  final Set<String> pins;

  /// 1-based day -> start/end minutes (rest days).
  final Map<int, (int, int)> windows;

  /// 1-based day -> most visits.
  final Map<int, int> caps;

  /// Every place the plan knows, by id.
  final Map<String, Hotspot> pool;
  DateTime start;
  DateTime end;

  /// Per day (index = day - 1): the place ids, visits and named meals.
  late List<List<String>> membership;

  /// Things that could not be placed anywhere.
  final List<String> unplaced = [];


  /// Spare minutes each day (index = day - 1) has for sightseeing, from the last
  /// plan. Empty until known: then only the place-count cap applies.
  List<int> slack = [];

  /// What the edit did, for the answer to the traveller.
  final List<String> log = [];

  /// Things worth telling the traveller after the plan was laid out.
  final List<String> notes = [];

  int get dayCount => membership.length;

  static Map<String, Hotspot> _poolOf(Itinerary it) {
    final out = <String, Hotspot>{for (final h in it.snapshot?.pool ?? const <Hotspot>[]) h.id: h};
    // Plans saved before editing existed: rebuild what the days show.
    for (final d in it.days) {
      for (final s in d.slots) {
        final id = s.refId;
        if ((s.kind == SlotKind.visit || s.kind == SlotKind.meal) && id != null && s.location != null && !out.containsKey(id)) {
          final pax = math.max(1, it.brief?.travellerCount ?? 1);
          out[id] = Hotspot(
            id: id,
            name: s.title.replaceFirst(RegExp(r'^(Lunch|Dinner) at '), ''),
            location: s.location!,
            kind: s.kind == SlotKind.meal ? HotspotKind.food : HotspotKind.other,
            why: s.note ?? '',
            visitMinutes: math.max(20, s.duration.inMinutes),
            feeInr: s.costInr == null ? null : (s.costInr! / pax).round(),
            score: 0.5,
          );
        }
      }
    }
    return out;
  }

  static List<List<String>> _membershipOf(Itinerary it) => [
    for (final d in it.days)
      {
        for (final s in d.slots)
          if ((s.kind == SlotKind.visit || s.kind == SlotKind.meal) && s.refId != null) s.refId!,
      }.toList(),
  ];

  // --- time ---------------------------------------------------------------------

  /// Learns how much spare time each day has: the free time the planner gives
  /// that day, minus what the current days already use.
  void primeSlack(Itinerary it, {required int travellers, required int children}) {
    try {
      final plan = DayPlanner.plan(toPlanInput(travellers: travellers, children: children, extraPlaces: const []));
      slack = _slackFrom(plan.freeMinutes, it.days);
    } catch (_) {
      slack = [];
    }
  }

  /// After a plan: the same, from the days just laid out.
  void updateSlack(DayPlanResult plan) => slack = _slackFrom(plan.freeMinutes, plan.days);

  static List<int> _slackFrom(List<int> free, List<ItineraryDay> days) {
    final out = <int>[];
    for (var i = 0; i < days.length; i++) {
      final f = i < free.length ? free[i] : 0;
      final used = days[i].slots
          .where((s) => s.kind == SlotKind.visit || s.kind == SlotKind.meal || s.kind == SlotKind.rest || (s.kind == SlotKind.transit && !(s.leg?.id.startsWith('intercity') ?? false)))
          .fold<int>(0, (t, s) => t + s.duration.inMinutes);
      out.add(math.max(0, f - used));
    }
    return out;
  }

  bool _hasTimeFor(Hotspot h, int day) {
    if (slack.isEmpty || day - 1 >= slack.length) return true;
    return slack[day - 1] >= h.visitMinutes + 25;
  }

  void _spend(Hotspot h, int day, int sign) {
    if (slack.isEmpty || day - 1 >= slack.length) return;
    slack[day - 1] = math.max(0, slack[day - 1] - sign * (h.visitMinutes + 25));
  }

  // --- queries --------------------------------------------------------------

  Hotspot? place(String id) => pool[id];

  bool isFood(String id) => pool[id]?.kind == HotspotKind.food;

  /// Visits (not meals) on a day.
  List<String> visitsOn(int day) => [for (final id in membership[day - 1]) if (!isFood(id)) id];

  int? dayOf(String id) {
    for (var i = 0; i < membership.length; i++) {
      if (membership[i].contains(id)) return i + 1;
    }
    return null;
  }

  Set<String> get placed => {for (final d in membership) ...d};

  DateTime dateOf(int day) => DateTime(start.year, start.month, start.day + day - 1);

  int get perDay => switch (brief.pace) {
    TripPace.relaxed => 4,
    TripPace.packed => 6,
    _ => 5,
  };

  int capOf(int day) => caps[day] ?? perDay;

  LatLng get base => hotel?.location ?? center ?? const LatLng(0, 0);

  /// The middle of a day's places, or the stay if it has none.
  LatLng centroidOf(int day, {String? without}) {
    final pts = [
      for (final id in membership[day - 1])
        if (id != without && pool[id] != null) pool[id]!.location,
    ];
    if (pts.isEmpty) return base;
    final lat = pts.fold<double>(0, (s, p) => s + p.latitude) / pts.length;
    final lon = pts.fold<double>(0, (s, p) => s + p.longitude) / pts.length;
    return LatLng(lat, lon);
  }

  bool _opensOn(Hotspot h, int day) => !OpeningHours.parse(h.openingHours).closedAllDay(dateOf(day).weekday);

  bool _allowedOn(Hotspot h, int day) {
    if (!_opensOn(h, day)) return false;
    if (banned.contains(_iso(dateOf(day))) && h.isOutdoor && h.kind != HotspotKind.food) return false;
    return true;
  }

  static String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // --- moving things ---------------------------------------------------------

  /// The day a displaced place should go to: one with room that is open for it,
  /// preferring later days (what no longer fits "moves to a newer day"), then
  /// the nearest.
  int? bestDayFor(String id, {int? avoid, bool laterFirst = true, int extra = 0}) {
    final h = pool[id];
    if (h == null) return null;
    final options = <(int, double)>[];
    for (var d = 1; d <= dayCount; d++) {
      if (d == avoid) continue;
      if (visitsOn(d).length >= capOf(d) + extra) continue;
      if ((caps[d] ?? 1) == 0) continue;
      if (!_allowedOn(h, d)) continue;
      if (!_hasTimeFor(h, d)) continue;
      final later = avoid != null && d > avoid;
      final km = haversineKm(h.location.latitude, h.location.longitude, centroidOf(d).latitude, centroidOf(d).longitude);
      // Later days first when asked, then distance.
      options.add((d, (laterFirst && !later ? 1000 : 0) + km));
    }
    if (options.isEmpty) return null;
    options.sort((a, b) => a.$2.compareTo(b.$2));
    return options.first.$1;
  }

  void _addTo(String id, int day) {
    membership[day - 1].add(id);
    final h = pool[id];
    if (h != null) _spend(h, day, 1);
  }

  /// The day closest to a place, ignoring how full it is (for "make room").
  int? nearestDayFor(String id) {
    final h = pool[id];
    if (h == null) return null;
    int? best;
    var bestKm = double.infinity;
    for (var d = 1; d <= dayCount; d++) {
      if ((caps[d] ?? 1) == 0 || !_allowedOn(h, d)) continue;
      final c = centroidOf(d);
      final km = haversineKm(h.location.latitude, h.location.longitude, c.latitude, c.longitude);
      if (km < bestKm) {
        bestKm = km;
        best = d;
      }
    }
    return best;
  }

  /// The least important unlocked visit on a day.
  String? leastImportantOn(int day) {
    final visits = [for (final id in visitsOn(day)) if (!pins.contains(id)) id]..sort((a, b) => (pool[a]?.score ?? 0).compareTo(pool[b]?.score ?? 0));
    return visits.firstOrNull;
  }

  /// Puts [id] on [day] (removing it from wherever it was).
  void put(String id, int day) {
    final h = pool[id];
    final from = dayOf(id);
    for (final d in membership) {
      d.remove(id);
    }
    membership[day - 1].add(id);
    if (h != null) {
      if (from != null) _spend(h, from, -1);
      _spend(h, day, 1);
    }
  }

  void drop(String id) {
    for (final d in membership) {
      d.remove(id);
    }
    dropped.add(id);
    pins.remove(id);
  }

  OpResult moveStop(String id, int toDay) {
    final h = pool[id];
    if (h == null) return const OpResult(false, 'I could not find that stop.');
    final from = dayOf(id);
    if (from == toDay) return OpResult(true, '${h.name} is already on day $toDay.');
    if (!_opensOn(h, toDay)) return OpResult(false, '${h.name} is closed on ${_weekday(dateOf(toDay))}, so it cannot go on day $toDay.');
    if (banned.contains(_iso(dateOf(toDay))) && h.isOutdoor) return OpResult(false, 'Day $toDay has outdoor plans switched off because of rain.');
    if (visitsOn(toDay).length >= capOf(toDay) + 1 && !isFood(id)) return OpResult(false, 'Day $toDay is already full. Lighten it first, or pick another day.');
    if (!isFood(id) && !_hasTimeFor(h, toDay)) return OpResult(false, 'Day $toDay does not have time for ${h.name}. Lighten it first, or pick another day.');
    put(id, toDay);
    return OpResult(true, 'Moved ${h.name} to day $toDay.');
  }

  static String _weekday(DateTime d) => const ['Mondays', 'Tuesdays', 'Wednesdays', 'Thursdays', 'Fridays', 'Saturdays', 'Sundays'][d.weekday - 1];

  OpResult removeStop(String id) {
    final h = pool[id];
    if (h == null) return const OpResult(false, 'I could not find that stop.');
    if (pins.contains(id)) return OpResult(false, '${h.name} is locked. Unlock it first.');
    drop(id);
    return OpResult(true, 'Removed ${h.name}.');
  }

  /// Makes a day lighter. What is displaced goes to another day if there is room.
  OpResult rest(int day, bool free) {
    if (day < 1 || day > dayCount) return const OpResult(false, 'That day is not in the trip.');
    final keepCount = free ? 0 : 2;
    final visits = visitsOn(day);
    // Locked places stay; then the most important.
    final ranked = [...visits]..sort((a, b) {
      final pa = pins.contains(a) ? 1 : 0;
      final pb = pins.contains(b) ? 1 : 0;
      if (pa != pb) return pb - pa;
      return (pool[b]?.score ?? 0).compareTo(pool[a]?.score ?? 0);
    });
    final keep = <String>{
      ...ranked.where(pins.contains),
      ...ranked.where((id) => !pins.contains(id)).take(math.max(0, keepCount - ranked.where(pins.contains).length)),
    };
    if (free) keep.removeWhere((id) => !pins.contains(id));
    final displaced = [for (final id in visits) if (!keep.contains(id)) id];
    // Meals at named places follow their day only if a visit stays.
    for (final id in [...membership[day - 1]]) {
      if (isFood(id) && free) membership[day - 1].remove(id);
    }
    caps[day] = free ? 0 : math.min(2, capOf(day));
    if (free) {
      windows.remove(day);
    } else {
      windows[day] = (10 * 60 + 30, 17 * 60 + 30);
    }
    final moved = <String>[];
    final lost = <String>[];
    for (final id in displaced) {
      membership[day - 1].remove(id);
      final to = bestDayFor(id, avoid: day);
      if (to == null) {
        lost.add(id);
      } else {
        _addTo(id, to);
        moved.add(id);
      }
    }
    for (final id in lost) {
      unplaced.add(id);
    }
    String names(List<String> ids) => ids.map((id) => pool[id]?.name ?? 'a stop').take(3).join(', ');
    final parts = <String>[
      free ? 'Day $day is now a free day.' : 'Day $day is lighter: it keeps ${keep.length} place${keep.length == 1 ? '' : 's'} and starts later.',
      if (moved.isNotEmpty) '${names(moved)} moved to other days.',
      if (lost.isNotEmpty) 'There was no room elsewhere for ${names(lost)}.',
    ];
    return OpResult(true, parts.join(' '));
  }

  /// Whether the planner can lay the plan out with [newId] on [day] in place of
  /// [replacing], with every other place still placed. A dry run: the working
  /// copy is not changed.
  bool fitsIfSwapped(String newId, String replacing, {required int travellers, required int children}) {
    final day = dayOf(replacing);
    if (day == null) return false;
    final backup = [for (final d in membership) [...d]];
    try {
      final at = membership[day - 1].indexOf(replacing);
      membership[day - 1][at] = newId;
      final expected = {for (final d in membership) ...d}.where((id) => !isFood(id)).toSet();
      final plan = DayPlanner.plan(toPlanInput(travellers: travellers, children: children, extraPlaces: const [], excluding: {replacing}));
      final got = {for (final h in plan.visited) h.id};
      return expected.every(got.contains);
    } finally {
      for (var i = 0; i < membership.length; i++) {
        membership[i] = backup[i];
      }
    }
  }

  /// Replacement candidates for [id], best first, given what the traveller wants.
  List<Hotspot> replacementCandidates(String id, {String? wish, required HotspotQuery query, int? atDay}) {
    final old = pool[id];
    final day = atDay ?? dayOf(id);
    final want = _Wish.parse(wish);
    // The replacement must fit the time the old stop leaves free on that day.
    final room = day == null || slack.isEmpty || day - 1 >= slack.length ? 1 << 30 : slack[day - 1] + (old?.visitMinutes ?? 0) + 25;
    final candidates = [
      for (final h in pool.values)
        if (!placed.contains(h.id) &&
            !dropped.contains(h.id) &&
            h.id != id &&
            !HotspotFinder.isExcluded(h, query) &&
            (h.kind == HotspotKind.food) == (old?.kind == HotspotKind.food) &&
            h.visitMinutes + 25 <= room &&
            (day == null || _allowedOn(h, day)))
          h,
    ];
    if (candidates.isEmpty) return const [];
    double score(Hotspot h) {
      var s = h.score * 2;
      if (want.indoor == true && !h.isOutdoor) s += 3;
      if (want.indoor == true && h.isOutdoor) s -= 4;
      if (want.indoor == false && h.isOutdoor) s += 3;
      if (want.indoor == false && !h.isOutdoor) s -= 4;
      if (want.free && (h.feeInr ?? 0) == 0) s += 2;
      if (want.kinds.isNotEmpty) s += want.kinds.contains(h.kind) ? 3 : -1.5;
      if (old != null && want.kinds.isEmpty && h.kind == old.kind) s += 0.6;
      if (day != null) {
        final c = centroidOf(day, without: id);
        s -= haversineKm(h.location.latitude, h.location.longitude, c.latitude, c.longitude) / 15;
      }
      return s;
    }

    candidates.sort((a, b) => score(b).compareTo(score(a)));
    return candidates;
  }

  /// The single best replacement.
  Hotspot? bestReplacement(String id, {String? wish, required HotspotQuery query, int? atDay}) =>
      replacementCandidates(id, wish: wish, query: query, atDay: atDay).firstOrNull;

  OpResult swapStop(String id, String withId) {
    final old = pool[id];
    final next = pool[withId];
    if (old == null || next == null) return const OpResult(false, 'I could not find that place.');
    if (pins.contains(id)) return OpResult(false, '${old.name} is locked. Unlock it first.');
    final day = dayOf(id);
    if (day == null) return OpResult(false, '${old.name} is not on a day.');
    if (!_allowedOn(next, day)) return OpResult(false, '${next.name} is closed on ${_weekday(dateOf(day))}, so it cannot replace ${old.name}.');
    final at = membership[day - 1].indexOf(id);
    membership[day - 1][at] = withId;
    dropped.add(id);
    dropped.remove(withId);
    return OpResult(true, 'Replaced ${old.name} with ${next.name}.');
  }

  OpResult addStop(String id, {int? day}) {
    final h = pool[id];
    if (h == null) return const OpResult(false, 'I could not find that place.');
    dropped.remove(id);
    if (placed.contains(id)) return OpResult(true, '${h.name} is already in your plan.');
    final target = day != null && day >= 1 && day <= dayCount && _allowedOn(h, day) ? day : bestDayFor(id, extra: 1) ?? bestDayFor(id, extra: 2);
    if (target == null) return OpResult(false, 'No day has room for ${h.name}, or it is closed on the days that do.');
    membership[target - 1].add(id);
    return OpResult(true, 'Added ${h.name} to day $target.');
  }

  OpResult lock(String id, bool on) {
    final h = pool[id];
    if (h == null) return const OpResult(false, 'I could not find that stop.');
    if (on) {
      pins.add(id);
    } else {
      pins.remove(id);
    }
    return OpResult(true, on ? '${h.name} is locked to its day.' : '${h.name} is unlocked.');
  }

  /// Fewer places a day (slower pace): extras move on or are set aside.
  List<String> rebalance() {
    final notes = <String>[];
    for (var d = 1; d <= dayCount; d++) {
      final cap = capOf(d);
      final visits = visitsOn(d);
      if (visits.length <= cap) continue;
      final extras = ([...visits]..sort((a, b) => (pool[a]?.score ?? 0).compareTo(pool[b]?.score ?? 0))).where((id) => !pins.contains(id)).take(visits.length - cap).toList();
      for (final id in extras) {
        membership[d - 1].remove(id);
        final to = bestDayFor(id, avoid: d);
        if (to != null) {
          _addTo(id, to);
        } else {
          unplaced.add(id);
        }
      }
      if (extras.isNotEmpty) notes.add('Day $d now keeps $cap places.');
    }
    return notes;
  }

  /// A faster pace: days with room take the best unused place nearby. Only
  /// full days in the middle of the trip are filled (the first and last days
  /// are shortened by travel).
  int fill(bool Function(Hotspot) allowed) {
    var added = 0;
    for (var d = 2; d < dayCount; d++) {
      if ((caps[d] ?? 1) == 0) continue;
      while (visitsOn(d).length < capOf(d)) {
        final centre = centroidOf(d);
        Hotspot? best;
        var bestScore = -1e9;
        for (final h in pool.values) {
          if (placed.contains(h.id) || dropped.contains(h.id) || h.kind == HotspotKind.food || !allowed(h) || !_allowedOn(h, d)) continue;
          final s = h.score * 2 - haversineKm(h.location.latitude, h.location.longitude, centre.latitude, centre.longitude) / 15;
          if (s > bestScore) {
            bestScore = s;
            best = h;
          }
        }
        if (best == null) break;
        membership[d - 1].add(best.id);
        added++;
      }
    }
    return added;
  }

  /// A longer trip: the new days are filled with the best unused places, kept
  /// close together.
  OpResult addDays(int n, {bool fill = true}) {
    final newDays = <int>[];
    for (var i = 0; i < n; i++) {
      membership.add([]);
      end = end.add(const Duration(days: 1));
      newDays.add(membership.length);
    }
    final unused = [
      for (final h in pool.values)
        if (fill && !placed.contains(h.id) && !dropped.contains(h.id) && h.kind != HotspotKind.food) h,
    ]..sort((a, b) => b.score.compareTo(a.score));
    final added = <String>[];
    for (final day in newDays) {
      final group = <Hotspot>[];
      for (final h in [...unused]) {
        if (group.length >= perDay - 1) break;
        if (!_allowedOn(h, day)) continue;
        if (group.isNotEmpty) {
          final near = group.first;
          if (haversineKm(h.location.latitude, h.location.longitude, near.location.latitude, near.location.longitude) > 25) continue;
        }
        group.add(h);
        unused.remove(h);
      }
      for (final h in group) {
        membership[day - 1].add(h.id);
        added.add(h.name);
      }
    }
    return OpResult(true, 'Added ${n == 1 ? 'a day' : '$n days'}${added.isEmpty ? '' : ' with ${added.take(3).join(', ')}${added.length > 3 ? '…' : ''}'}.');
  }

  /// A shorter trip: the last days go, and their places move earlier if they fit.
  OpResult removeDays(int n) {
    final moved = <String>[];
    final lost = <String>[];
    for (var i = 0; i < n && membership.length > 1; i++) {
      final gone = membership.removeLast();
      end = end.subtract(const Duration(days: 1));
      caps.remove(membership.length + 1);
      windows.remove(membership.length + 1);
      for (final id in gone) {
        if (isFood(id)) continue;
        final to = bestDayFor(id, laterFirst: false);
        if (to != null) {
          _addTo(id, to);
          moved.add(id);
        } else {
          unplaced.add(id);
          lost.add(id);
        }
      }
    }
    String names(List<String> ids) => ids.map((id) => pool[id]?.name ?? 'a stop').take(3).join(', ');
    return OpResult(true, 'Removed ${n == 1 ? 'the last day' : 'the last $n days'}.${moved.isEmpty ? '' : ' ${names(moved)} moved earlier.'}${lost.isEmpty ? '' : ' There was no room for ${names(lost)}.'}');
  }

  // --- handing over to the planner --------------------------------------------

  /// The input that makes Raah lay the days out exactly as this copy says.
  DayPlanInput toPlanInput({required int travellers, required int children, required List<Hotspot> extraPlaces, Set<String> excluding = const {}}) {
    final ids = <String>{for (final d in membership) ...d}..removeAll(excluding);
    return DayPlanInput(
      start: start,
      end: end,
      base: base,
      baseName: hotel?.name ?? '${brief.destination} centre',
      places: [for (final id in ids) if (pool[id] != null) pool[id]!, ...extraPlaces],
      alternates: const [],
      travellers: travellers,
      children: children,
      weather: weather,
      localModes: brief.transportModes,
      needs: brief.accessibilityNeeds,
      arrival: chosen,
      departure: mirrorOf(chosen),
      pace: brief.pace,
      bannedOutdoorDates: banned,
      excludedIds: dropped,
      walkLimitKm: _walkLimit(brief),
      slowPace: (brief.accessibilityDetails['a11y.elderly.support']?.contains('slow_pace') ?? false) || brief.accessibilityNeeds.contains(AccessibilityNeed.elderlyCare),
      restStops: brief.accessibilityDetails['a11y.mobility.support']?.contains('rest_stops') ?? false,
      dietary: brief.dietary,
      fixedDays: {for (var i = 0; i < membership.length; i++) i + 1: [...membership[i]]},
      dayWindows: windows,
      dayStopCaps: caps,
    );
  }

  static double? _walkLimit(TripBrief b) {
    final w = b.accessibilityDetails['a11y.mobility.walking'] ?? const {};
    if (w.contains('lt100')) return 0.1;
    if (w.contains('100_500')) return 0.4;
    if (w.contains('500_1000')) return 0.8;
    return null;
  }

  static TransportLeg? mirrorOf(TransportLeg? leg) {
    if (leg == null) return null;
    return TransportLeg(
      id: 'intercity.return.${leg.mode.name}',
      from: leg.to,
      to: leg.from,
      mode: leg.mode,
      distanceKm: leg.distanceKm,
      durationMin: leg.durationMin,
      costInr: leg.costInr,
      co2Grams: leg.co2Grams,
      stepFree: leg.stepFree,
      note: leg.note,
      isEstimated: leg.isEstimated,
      fromPoint: leg.toPoint,
      toPoint: leg.fromPoint,
    );
  }

  /// What the plan remembers after the edit.
  PlanSnapshot snapshot() => PlanSnapshot(
    pool: pool.values.toList(),
    weather: weather,
    center: center,
    origin: origin,
    bannedOutdoor: banned,
    droppedIds: dropped,
    pins: pins,
    dayWindows: windows,
    dayStopCaps: caps,
  );
}

/// What "something outdoors / cheaper / a viewpoint" asks for.
class _Wish {
  const _Wish({this.indoor, this.free = false, this.kinds = const {}});

  final bool? indoor;
  final bool free;
  final Set<HotspotKind> kinds;

  static _Wish parse(String? text) {
    final t = (text ?? '').toLowerCase();
    if (t.isEmpty) return const _Wish();
    bool has(String pattern) => RegExp(pattern).hasMatch(t);
    return _Wish(
      indoor: has(r'\b(indoor|indoors|inside|covered|air[- ]condition|museum|gallery)\b') ? true : (has(r'\b(outdoor|outdoors|outside|open[- ]air|nature|garden|park|walk|trek|hike)\b') ? false : null),
      free: has(r'\b(free|cheap|cheaper|no fee|budget)\b'),
      kinds: {
        if (has(r'\b(view|viewpoint|sunset|sunrise|scenic|lookout)\b')) HotspotKind.viewpoint,
        if (has(r'\b(food|eat|restaurant|cafe|street food|local dish|lunch|dinner)\b')) HotspotKind.food,
        if (has(r'\b(heritage|history|historic|fort|palace|monument|ruins)\b')) HotspotKind.heritage,
        if (has(r'\b(museum|gallery|art|culture|cultural)\b')) HotspotKind.culture,
        if (has(r'\b(temple|church|mosque|religious|spiritual|shrine)\b')) HotspotKind.religious,
        if (has(r'\b(nature|waterfall|lake|garden|park|wildlife|forest|beach)\b')) HotspotKind.nature,
        if (has(r'\b(adventure|trek|hike|rafting|zip)\b')) HotspotKind.adventure,
        if (has(r'\b(shop|shopping|market|bazaar)\b')) HotspotKind.shopping,
      },
    );
  }
}
