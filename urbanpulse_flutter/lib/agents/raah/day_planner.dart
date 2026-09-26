import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../domain/opening_hours.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../services/data/forecast_client.dart';
import '../../services/data/http_util.dart';
import '../safar/transport_planner.dart';

/// Everything Raah needs to lay a trip out over its days.
class DayPlanInput {
  const DayPlanInput({
    required this.start,
    required this.end,
    required this.base,
    required this.baseName,
    required this.places,
    required this.travellers,
    this.children = 0,
    this.alternates = const [],
    this.weather = const {},
    this.localModes = const {},
    this.needs = const {},
    this.arrival,
    this.departure,
    this.pace,
    this.bannedOutdoorDates = const {},
    this.excludedIds = const {},
    this.walkLimitKm,
    this.slowPace = false,
    this.restStops = false,
    this.dietary = const {},
    this.fixedDays,
    this.dayWindows = const {},
    this.dayStopCaps = const {},
  });

  /// Editing a finished plan: which places go on which day (1-based day number
  /// to place ids, in the order wanted). When set, the planner does not regroup
  /// places by geography: it only lays each listed day out (times, meals,
  /// travel), so days the traveller did not touch come out exactly as before.
  /// Places not listed are left unscheduled, and spares are never added.
  final Map<int, List<String>>? fixedDays;

  /// A shorter day (1-based day number to start and end, minutes from midnight),
  /// e.g. a "rest day" that starts late and ends early.
  final Map<int, (int, int)> dayWindows;

  /// The most places on a given day (1-based day number).
  final Map<int, int> dayStopCaps;

  final DateTime start;
  final DateTime end;

  /// Where the traveller sleeps (or the destination centre if no stay was chosen).
  final LatLng base;
  final String baseName;
  final List<Hotspot> places;

  /// Unchosen places that can fill a gap (indoor swaps on a rainy day).
  final List<Hotspot> alternates;
  final int travellers;
  final int children;

  /// ISO date -> forecast. Empty when the dates are beyond the forecast.
  final Map<String, DayForecast> weather;
  final Set<TripTransportMode> localModes;
  final Set<AccessibilityNeed> needs;

  /// The journey to the destination and back (either may be unknown).
  final TransportLeg? arrival;
  final TransportLeg? departure;
  final TripPace? pace;

  /// Dates on which no outdoor place may be scheduled (the traveller asked).
  final Set<String> bannedOutdoorDates;

  /// Places the plan must not use (replaced after an audit).
  final Set<String> excludedIds;

  /// The farthest anyone in the group can comfortably walk between stops, from
  /// their own answer ("under 100 m"). Null uses the default for their needs.
  final double? walkLimitKm;

  /// Fewer places a day and longer at each (elderly travellers, "slower pace").
  final bool slowPace;

  /// A short sit-down after each visit ("frequent rest stops").
  final bool restStops;

  /// Food needs, noted on every meal.
  final Set<Dietary> dietary;
}

/// Outdoor places that landed on a day with heavy rain in the forecast.
class RainConflict {
  const RainConflict({required this.date, required this.day, required this.places, required this.summary});

  final String date;
  final int day;
  final List<Hotspot> places;
  final String summary;
}

class DayPlanResult {
  const DayPlanResult({
    required this.days,
    required this.unscheduled,
    this.rainConflicts = const [],
    this.notes = const [],
    this.visited = const [],
    this.freeMinutes = const [],
  });

  final List<ItineraryDay> days;

  /// Chosen places that did not fit anywhere.
  final List<Hotspot> unscheduled;
  final List<RainConflict> rainConflicts;
  final List<String> notes;

  /// The places actually placed on a day, in order.
  final List<Hotspot> visited;

  /// Minutes each day (by index) the traveller is at the destination and free
  /// to sightsee; 0 for a day taken up by the journey.
  final List<int> freeMinutes;
}

/// Raah: turns a set of places into practical days. Deterministic. It groups
/// places that are close together into the same day, gives the wettest days to
/// the least outdoor groups, orders each day so places are open when the
/// traveller arrives, and adds meals and local journeys. It never fails: what
/// does not fit is reported as unscheduled.
class DayPlanner {
  static const _lunchAt = 12 * 60 + 30;
  static const _lunchLatest = 15 * 60;
  static const _dinnerAt = 19 * 60;

  static DayPlanResult plan(DayPlanInput input) {
    final notes = <String>[];
    // A date-only end (midnight) means the evening of that day, not its start.
    final end = input.end.hour == 0 && input.end.minute == 0 ? input.end.add(const Duration(hours: 18)) : input.end;
    final firstDate = _dateOnly(input.start);
    final lastDate = _dateOnly(end);
    final n = (lastDate.difference(firstDate).inDays + 1).clamp(1, 30);
    final dates = [for (var i = 0; i < n; i++) firstDate.add(Duration(days: i))];

    var (dayStartMin, dayEndMin, perDay) = switch (input.pace) {
      TripPace.relaxed => (9 * 60 + 30, 19 * 60 + 30, 4),
      TripPace.packed => (8 * 60 + 30, 21 * 60 + 30, 6),
      _ => (9 * 60, 20 * 60 + 30, 5),
    };
    if (input.slowPace) perDay = math.max(2, perDay - 1);

    // When the traveller is actually at the destination.
    final arrivalMin = input.arrival?.durationMin ?? 0;
    final returnMin = input.departure?.durationMin ?? 0;
    final presenceStart = input.start.add(Duration(minutes: arrivalMin));
    final presenceEnd = end.subtract(Duration(minutes: returnMin));
    if (presenceEnd.isBefore(presenceStart.add(const Duration(minutes: 120)))) {
      notes.add('The journey there and back leaves almost no time at the destination.');
    }

    // Each day's usable window: only while the traveller is there.
    final windows = <_Window?>[];
    for (var di = 0; di < dates.length; di++) {
      final d = dates[di];
      final override = input.dayWindows[di + 1];
      var ws = d.add(Duration(minutes: override?.$1 ?? dayStartMin));
      var we = d.add(Duration(minutes: override?.$2 ?? dayEndMin));
      final earliest = presenceStart.add(const Duration(minutes: 60));
      final latest = presenceEnd.subtract(const Duration(minutes: 60));
      if (earliest.isAfter(ws)) ws = earliest;
      if (latest.isBefore(we)) we = latest;
      windows.add(we.difference(ws).inMinutes >= 90 ? _Window(ws, we) : null);
    }
    final freeMinutes = [for (final w in windows) w?.minutes ?? 0];

    final excluded = input.excludedIds;
    var pool = [for (final h in input.places) if (!excluded.contains(h.id)) h];
    final fixed = input.fixedDays;
    // A plan being edited never gains spare places on its own.
    final alternates = fixed != null
        ? const <Hotspot>[]
        : [for (final h in input.alternates) if (!excluded.contains(h.id) && !pool.any((p) => p.id == h.id)) h];

    // Nothing chosen (every pick was dropped): plan from the spares instead.
    if (fixed == null && pool.isEmpty && alternates.isNotEmpty) pool = [...alternates];

    final usable = [for (var i = 0; i < n; i++) if (windows[i] != null) i];
    if (usable.isEmpty || pool.isEmpty) {
      return DayPlanResult(
        days: _buildDays(input, dates, {for (final i in usable) i: const <ItinerarySlot>[]}, windows, notes, end: end),
        unscheduled: pool,
        notes: [
          ...notes,
          if (pool.isEmpty) 'There were no places to schedule.' else 'There is no usable time at the destination.',
        ],
        freeMinutes: freeMinutes,
      );
    }

    // Forecast: how wet is each day (0..1)?
    final hasWeather = input.weather.isNotEmpty;
    if (!hasWeather) notes.add('The forecast does not reach these dates, so weather was not considered.');
    double rain(int i) {
      final f = input.weather[_iso(dates[i])];
      if (f == null) return 0.15;
      if (f.isRainy) return 1;
      return ((f.rainProbability ?? 15) / 100 * 0.7).clamp(0.0, 0.7);
    }

    bool banned(int i) => input.bannedOutdoorDates.contains(_iso(dates[i]));

    // Places that cannot go on a banned day.
    final maxStops = perDay + 1;

    // 1-2. Group by geography and give the groups to days, unless the caller
    // (the itinerary editor) has already said what goes where.
    final Map<int, List<Hotspot>> assignment;
    if (fixed != null) {
      final byId = {for (final h in pool) h.id: h};
      // A place can only be on one day: the first mention wins.
      final taken = <String>{};
      final days = fixed.entries.where((e) => e.key >= 1 && e.key <= n).toList()..sort((a, b) => a.key.compareTo(b.key));
      assignment = {
        for (final e in days) e.key - 1: [for (final id in e.value) if (byId[id] != null && taken.add(id)) byId[id]!],
      };
    } else {
      // Cluster by geography into as many groups as usable days, then give
      // clusters to days: big clusters to long days, outdoor ones to dry days.
      final k = math.min(usable.length, math.max(1, (pool.length / 2).ceil()));
      final clusters = _kMeans(pool, k);
      assignment = _assign(clusters, usable, windows, rain, banned, maxStops);
    }

    // 3. Sequence each day; whatever does not fit carries to a later day.
    final slotsByDay = <int, List<ItinerarySlot>>{};
    var cappedDays = 0;
    final visited = <Hotspot>[];
    var carry = <Hotspot>[];
    final rainConflicts = <RainConflict>[];
    for (var idx = 0; idx < usable.length; idx++) {
      final dayIdx = usable[idx];
      final cluster = assignment[dayIdx] ?? const <Hotspot>[];
      final candidates = [...cluster, ...carry];
      final w = windows[dayIdx]!;
      final res = _sequenceDay(
        input: input,
        dayNumber: dayIdx + 1,
        window: w,
        places: banned(dayIdx) ? [for (final h in candidates) if (!h.isOutdoor) h] : candidates,
        // (`maxStops` counts the meal stop: visits allowed = maxStops - 1.)
        maxStops: (input.dayStopCaps[dayIdx + 1] ?? (maxStops - 1)) + 1,
        rainy: rain(dayIdx) >= 1,
        weekday: dates[dayIdx].weekday,
      );
      slotsByDay[dayIdx] = res.slots;
      visited.addAll(res.placed);
      if (res.capped) cappedDays++;
      final placedIds = res.placed.map((h) => h.id).toSet();
      carry = [for (final h in candidates) if (!placedIds.contains(h.id)) h];
      // Outdoor places on a banned day cannot be carried back into it; they go on.
      if (rain(dayIdx) >= 1) {
        final wet = [for (final h in res.placed) if (h.isOutdoor && h.kind != HotspotKind.food) h];
        if (wet.isNotEmpty) {
          rainConflicts.add(
            RainConflict(date: _iso(dates[dayIdx]), day: dayIdx + 1, places: wet, summary: input.weather[_iso(dates[dayIdx])]?.summary ?? ''),
          );
        }
      }
    }

    // 4. A day with room left takes an indoor alternate on a rainy day, or the best spare place.
    if (alternates.isNotEmpty) {
      for (final dayIdx in usable) {
        final slots = slotsByDay[dayIdx] ?? const [];
        final placedHere = slots.where((s) => s.kind == SlotKind.visit).length;
        if (placedHere >= maxStops - 1) continue;
        final wantIndoor = rain(dayIdx) >= 1 || banned(dayIdx);
        final spare = [
          for (final h in alternates)
            if (!visited.any((v) => v.id == h.id) && (!wantIndoor || !h.isOutdoor)) h,
        ]..sort((a, b) => b.score.compareTo(a.score));
        if (spare.isEmpty) continue;
        final w = windows[dayIdx]!;
        final base = [
          for (final s in slots)
            if (s.kind == SlotKind.visit) visited.firstWhere((v) => v.id == s.refId, orElse: () => spare.first),
        ];
        // Only fill days that are clearly short, so plans do not get crowded.
        if (placedHere >= math.max(2, perDay - 2) && !wantIndoor) continue;
        final res = _sequenceDay(
          input: input,
          dayNumber: dayIdx + 1,
          window: w,
          places: [...base, ...spare.take(3)],
          maxStops: maxStops,
          rainy: rain(dayIdx) >= 1,
          weekday: dates[dayIdx].weekday,
        );
        if (res.placed.length > placedHere) {
          final before = visited.where((v) => base.any((b) => b.id == v.id)).length;
          slotsByDay[dayIdx] = res.slots;
          for (final h in res.placed) {
            if (!visited.any((v) => v.id == h.id)) visited.add(h);
          }
          notes.add('Added ${res.placed.length - before} spare place(s) on day ${dayIdx + 1} to use the free time.');
        }
      }
    }

    // Anything chosen that never got placed.
    final placedIds = visited.map((h) => h.id).toSet();
    // (Food places are only ever used for meals, so an unused one is not "left out".)
    final unscheduled = [for (final h in pool) if (!placedIds.contains(h.id) && h.kind != HotspotKind.food) h];
    if (unscheduled.isNotEmpty) {
      final names = '${unscheduled.take(3).map((h) => h.name).join(', ')}${unscheduled.length > 3 ? '…' : ''}';
      notes.add(
        cappedDays > 0
            ? '${unscheduled.length} more place(s) were left out to keep to about ${maxStops - 1} places a day, the pace you chose: $names.'
            : '${unscheduled.length} place(s) did not fit the time available: $names.',
      );
    }
    // A conflict only stays if the place is still on that day.
    final finalConflicts = [
      for (final c in rainConflicts)
        if (c.places.any((h) => placedIds.contains(h.id))) c,
    ];

    return DayPlanResult(
      days: _buildDays(input, dates, slotsByDay, windows, notes, visited: visited, end: end),
      unscheduled: unscheduled,
      rainConflicts: finalConflicts,
      notes: notes,
      visited: visited,
      freeMinutes: freeMinutes,
    );
  }

  // --- assignment ---------------------------------------------------------------

  static Map<int, List<Hotspot>> _assign(
    List<List<Hotspot>> clusters,
    List<int> usable,
    List<_Window?> windows,
    double Function(int) rain,
    bool Function(int) banned,
    int maxStops,
  ) {
    final k = clusters.length;
    if (k == 0 || usable.isEmpty) return {};
    // With more usable days than clusters, keep the longest days.
    final chosenDays = [...usable]
      ..sort((a, b) {
        final ca = windows[a]!.minutes;
        final cb = windows[b]!.minutes;
        return cb.compareTo(ca);
      });
    final useDays = chosenDays.take(k).toList()..sort();

    double cost(int c, int dayIdx) {
      final places = clusters[c];
      final need = places.fold<double>(0, (s, h) => s + h.visitMinutes + 25);
      final cap = windows[dayIdx]!.minutes - 90.0;
      final overflow = math.max(0, need - cap);
      final outdoorMin = places.where((h) => h.isOutdoor).fold<double>(0, (s, h) => s + h.visitMinutes);
      var cst = overflow * 1.5 + outdoorMin * rain(dayIdx) * 0.8;
      if (banned(dayIdx)) cst += outdoorMin * 10;
      if (places.length > maxStops) cst += (places.length - maxStops) * 40;
      return cst;
    }

    List<int> bestPerm;
    if (k <= 7) {
      bestPerm = _bestPermutation(k, (c, slot) => cost(c, useDays[slot]));
    } else {
      // Greedy for long trips: heaviest clusters first, each to its cheapest free day.
      final order = List.generate(k, (i) => i)
        ..sort((a, b) => clusters[b].fold<double>(0, (s, h) => s + h.visitMinutes).compareTo(clusters[a].fold<double>(0, (s, h) => s + h.visitMinutes)));
      final free = List.generate(k, (i) => i).toSet();
      bestPerm = List.filled(k, 0);
      for (final c in order) {
        var best = -1;
        var bestCost = double.infinity;
        for (final s in free) {
          final v = cost(c, useDays[s]);
          if (v < bestCost) {
            bestCost = v;
            best = s;
          }
        }
        bestPerm[c] = best;
        free.remove(best);
      }
    }
    return {for (var c = 0; c < k; c++) useDays[bestPerm[c]]: clusters[c]};
  }

  /// cluster index -> slot index with the lowest total cost.
  static List<int> _bestPermutation(int k, double Function(int cluster, int slot) cost) {
    final costs = List.generate(k, (c) => List.generate(k, (s) => cost(c, s)));
    var best = List.generate(k, (i) => i);
    var bestCost = double.infinity;
    final cur = List.filled(k, 0);
    final used = List.filled(k, false);
    void go(int c, double acc) {
      if (acc >= bestCost) return;
      if (c == k) {
        bestCost = acc;
        best = List.of(cur);
        return;
      }
      for (var s = 0; s < k; s++) {
        if (used[s]) continue;
        used[s] = true;
        cur[c] = s;
        go(c + 1, acc + costs[c][s]);
        used[s] = false;
      }
    }

    go(0, 0);
    return best;
  }

  /// Deterministic k-means on coordinates, seeded with the best place and then
  /// the farthest from those already chosen.
  static List<List<Hotspot>> _kMeans(List<Hotspot> places, int k) {
    if (k <= 1 || places.length <= 1) return [places];
    final byScore = [...places]..sort((a, b) => b.score.compareTo(a.score));
    final centres = <LatLng>[byScore.first.location];
    while (centres.length < k) {
      Hotspot? far;
      var farD = -1.0;
      for (final p in places) {
        final d = centres.map((c) => _km(c, p.location)).reduce(math.min);
        if (d > farD) {
          farD = d;
          far = p;
        }
      }
      centres.add(far!.location);
    }
    var groups = List.generate(k, (_) => <Hotspot>[]);
    for (var iter = 0; iter < 12; iter++) {
      groups = List.generate(k, (_) => <Hotspot>[]);
      for (final p in places) {
        var bi = 0;
        var bd = double.infinity;
        for (var c = 0; c < k; c++) {
          final d = _km(centres[c], p.location);
          if (d < bd) {
            bd = d;
            bi = c;
          }
        }
        groups[bi].add(p);
      }
      var moved = false;
      for (var c = 0; c < k; c++) {
        if (groups[c].isEmpty) continue;
        final lat = groups[c].fold<double>(0, (s, h) => s + h.location.latitude) / groups[c].length;
        final lon = groups[c].fold<double>(0, (s, h) => s + h.location.longitude) / groups[c].length;
        final next = LatLng(lat, lon);
        if (_km(centres[c], next) > 0.05) moved = true;
        centres[c] = next;
      }
      if (!moved) break;
    }
    // An empty cluster would waste a day: take the farthest place from the biggest group.
    for (var c = 0; c < k; c++) {
      if (groups[c].isNotEmpty) continue;
      final big = groups.reduce((a, b) => a.length >= b.length ? a : b);
      if (big.length > 1) groups[c].add(big.removeLast());
    }
    return [for (final g in groups) if (g.isNotEmpty) g];
  }

  // --- one day ------------------------------------------------------------------

  static _DayResult _sequenceDay({
    required DayPlanInput input,
    required int dayNumber,
    required _Window window,
    required List<Hotspot> places,
    required int maxStops,
    required bool rainy,
    required int weekday,
  }) {
    final slots = <ItinerarySlot>[];
    final placed = <Hotspot>[];
    var remaining = [...places];
    var t = window.start;
    var here = input.base;
    var hereName = input.baseName;
    var lunchDone = false;
    var dinnerDone = false;
    var hop = 0;

    int mins(DateTime d) => d.hour * 60 + d.minute;
    DateTime at(DateTime day, int minutes) => DateTime(day.year, day.month, day.day).add(Duration(minutes: minutes));
    final day = DateTime(window.start.year, window.start.month, window.start.day);

    final diets = [for (final d in input.dietary) if (d != Dietary.noPreference) d.label.toLowerCase()];
    final dietNote = diets.isEmpty ? null : 'Needs ${diets.join(' and ')} food: check the menu.';

    TransportLeg leg(LatLng from, String fromName, LatLng to, String toName) => TransportPlanner.local(
      id: 'local.$dayNumber.${hop++}',
      fromName: fromName,
      toName: toName,
      from: from,
      to: to,
      travellers: input.travellers,
      preferred: input.localModes,
      needs: input.needs,
      walkLimitKm: input.walkLimitKm,
    );

    void addTransit(TransportLeg l, String toName) {
      final end = t.add(Duration(minutes: l.durationMin));
      slots.add(
        ItinerarySlot(
          kind: SlotKind.transit,
          start: t,
          end: end,
          title: l.walking ? 'Walk to $toName' : '${l.mode.label} to $toName',
          location: l.toPoint,
          costInr: l.costInr == 0 ? null : l.costInr,
          leg: l,
          note: l.note,
        ),
      );
      t = end;
    }

    void meal(String title, {Hotspot? place, int minutes = 60}) {
      final end = t.add(Duration(minutes: minutes));
      slots.add(
        ItinerarySlot(
          kind: SlotKind.meal,
          start: t,
          end: end,
          title: place == null ? title : '$title at ${place.name}',
          location: place?.location ?? here,
          refId: place?.id,
          note: [?place?.why, ?dietNote].join(' ').trim().isEmpty ? null : [?place?.why, ?dietNote].join(' '),
        ),
      );
      if (place != null) {
        here = place.location;
        hereName = place.name;
        placed.add(place);
      }
      t = end;
    }

    int visitMinutes(Hotspot h) => input.slowPace ? (h.visitMinutes * 1.25).round() : h.visitMinutes;

    bool lunchDue() => !lunchDone && mins(t) >= _lunchAt;
    bool dinnerDue() => !dinnerDone && mins(t) >= _dinnerAt;

    var stops = 0;
    var capped = false;

    // Back at the stay with time before dinner: say so, rather than leave a gap.
    void restUntil(DateTime until) {
      if (until.difference(t).inMinutes >= 30) {
        slots.add(
          ItinerarySlot(
            kind: SlotKind.rest,
            start: t,
            end: until,
            title: input.slowPace || input.restStops ? 'Rest at ${input.baseName}' : 'Free time near ${input.baseName}',
            location: input.base,
            note: capped
                ? 'The day already has as many places as the pace you chose allows; this time is kept free on purpose.'
                : 'Nothing else nearby is open or fits before dinner; this time is free.',
          ),
        );
      }
      if (t.isBefore(until)) t = until;
    }

    for (var guard = 0; guard < 40; guard++) {
      // Meals come first when their time has arrived.
      if (lunchDue()) {
        lunchDone = true;
        if (mins(t) <= _lunchLatest && window.end.difference(t).inMinutes >= 45) {
          final food = _nearestFood(remaining, here, 4.0);
          if (food != null) {
            final l = leg(here, hereName, food.location, food.name);
            if (l.durationMin > 0 && _km(here, food.location) > 0.15) addTransit(l, food.name);
            remaining.removeWhere((h) => h.id == food.id);
            meal('Lunch', place: food);
          } else {
            meal('Lunch nearby');
          }
        }
        continue;
      }
      if (dinnerDue()) {
        dinnerDone = true;
        if (window.end.difference(t).inMinutes >= 45) {
          final food = _nearestFood(remaining, input.base, 3.0);
          final target = food?.location ?? input.base;
          final targetName = food?.name ?? input.baseName;
          if (_km(here, target) > 0.15) addTransit(leg(here, hereName, target, targetName), targetName);
          if (food != null) remaining.removeWhere((h) => h.id == food.id);
          meal(food == null ? 'Dinner near ${input.baseName}' : 'Dinner', place: food);
        }
        break;
      }
      // The day has as many places as the pace allows: only meals are left.
      final full = stops >= maxStops - 1;
      if (full) {
        capped = capped || remaining.any((h) => h.kind != HotspotKind.food);
        if (remaining.every((h) => h.kind != HotspotKind.food)) break;
      }

      // Choose the next place: the earliest one that is open and fits the day.
      _Pick? best;
      for (final h in full ? const <Hotspot>[] : remaining) {
        if (h.kind == HotspotKind.food) continue; // food places are for meals, not sightseeing
        final l = TransportPlanner.local(
          id: 'probe',
          fromName: hereName,
          toName: h.name,
          from: here,
          to: h.location,
          travellers: input.travellers,
          preferred: input.localModes,
          needs: input.needs,
          walkLimitKm: input.walkLimitKm,
        );
        final arrive = t.add(Duration(minutes: l.durationMin));
        final stay = visitMinutes(h);
        final hours = OpeningHours.parse(h.openingHours);
        final startMin = hours.nextSlot(weekday, mins(arrive), stay);
        if (startMin == null) continue;
        final startAt = at(day, startMin);
        final wait = startAt.difference(arrive).inMinutes;
        final end = startAt.add(Duration(minutes: stay));
        if (end.isAfter(window.end)) continue;
        if (wait > 120) continue;
        final cost = l.durationMin + wait * 1.2 - h.score * 12;
        if (best == null || cost < best.cost) best = _Pick(h, startAt, end, cost, wait);
      }
      if (best == null) {
        // Nothing fits before the meal: skip ahead to it if time remains.
        if (!lunchDone && mins(t) < _lunchAt && window.end.difference(at(day, _lunchAt)).inMinutes > 120) {
          t = at(day, _lunchAt);
          continue;
        }
        if (!dinnerDone && placed.isNotEmpty && window.end.difference(at(day, _dinnerAt)).inMinutes >= 60) {
          // Head back to the hotel now; dinner follows at its usual time.
          if (_km(here, input.base) > 0.15) {
            addTransit(leg(here, hereName, input.base, input.baseName), input.baseName);
            here = input.base;
            hereName = input.baseName;
          }
          if (mins(t) < _dinnerAt) restUntil(at(day, _dinnerAt));
          continue;
        }
        break;
      }

      final h = best.place;
      final l = leg(here, hereName, h.location, h.name);
      addTransit(l, h.name);
      if (best.startAt.isAfter(t) && best.startAt.difference(t).inMinutes >= 20) {
        slots.add(
          ItinerarySlot(
            kind: SlotKind.rest,
            start: t,
            end: best.startAt,
            title: 'Free time until ${h.name} opens',
            location: h.location,
          ),
        );
      }
      t = best.startAt;
      final flags = <String>[
        if (rainy && h.isOutdoor) 'Rain likely',
        if (h.openingHours == null && (h.kind == HotspotKind.culture || h.kind == HotspotKind.heritage || h.kind == HotspotKind.adventure)) 'Check opening hours',
      ];
      slots.add(
        ItinerarySlot(
          kind: SlotKind.visit,
          start: t,
          end: best.end,
          title: h.name,
          location: h.location,
          refId: h.id,
          note: h.why,
          costInr: _feeFor(h, input),
          access: _overall(h, input.needs),
          flags: flags,
        ),
      );
      here = h.location;
      hereName = h.name;
      t = best.end;
      remaining.removeWhere((x) => x.id == h.id);
      placed.add(h);
      stops++;
      if (input.restStops && window.end.difference(t).inMinutes >= 60) {
        final rested = t.add(const Duration(minutes: 20));
        slots.add(ItinerarySlot(kind: SlotKind.rest, start: t, end: rested, title: 'Rest stop', location: here, note: 'A seated break before moving on.'));
        t = rested;
      }
    }

    // Home for the evening when nothing brought us to dinner.
    if (!dinnerDone && placed.isNotEmpty && window.end.difference(t).inMinutes >= 90 && mins(window.end) >= _dinnerAt) {
      // Straight back to the stay after the last place, a rest, then dinner.
      if (_km(here, input.base) > 0.15) {
        addTransit(leg(here, hereName, input.base, input.baseName), input.baseName);
        here = input.base;
        hereName = input.baseName;
      }
      if (mins(t) < _dinnerAt) restUntil(at(day, _dinnerAt));
      meal('Dinner near ${input.baseName}');
    }
    return _DayResult(slots, placed, capped: capped);
  }

  static Hotspot? _nearestFood(List<Hotspot> remaining, LatLng from, double maxKm) {
    Hotspot? best;
    var bd = double.infinity;
    for (final h in remaining) {
      if (h.kind != HotspotKind.food) continue;
      final d = _km(from, h.location);
      if (d <= maxKm && d < bd) {
        bd = d;
        best = h;
      }
    }
    return best;
  }

  /// The entry fee for the whole group: children pay half.
  static int? _feeFor(Hotspot h, DayPlanInput input) {
    final fee = h.feeInr;
    if (fee == null || fee <= 0) return null;
    final kids = math.min(input.children, input.travellers);
    final grown = input.travellers - kids;
    return (fee * (grown + kids * 0.5)).round();
  }

  /// The group-wide reading of a place: the worst of the needs it was checked for.
  static SupportLevel? _overall(Hotspot h, Set<AccessibilityNeed> needs) {
    final relevant = [for (final n in needs) if (n != AccessibilityNeed.none) n];
    if (relevant.isEmpty) return null;
    final levels = [for (final n in relevant) h.access[n]?.level ?? SupportLevel.unknown];
    if (levels.contains(SupportLevel.no)) return SupportLevel.no;
    if (levels.contains(SupportLevel.partial)) return SupportLevel.partial;
    if (levels.contains(SupportLevel.unknown)) return SupportLevel.unknown;
    return SupportLevel.yes;
  }

  // --- assembling days ----------------------------------------------------------

  static List<ItineraryDay> _buildDays(
    DayPlanInput input,
    List<DateTime> dates,
    Map<int, List<ItinerarySlot>> slotsByDay,
    List<_Window?> windows,
    List<String> notes, {
    List<Hotspot> visited = const [],
    required DateTime end,
  }) {
    final out = <ItineraryDay>[];
    final arrival = input.arrival;
    final departure = input.departure;
    final arrivalEnd = arrival == null ? null : input.start.add(Duration(minutes: arrival.durationMin));
    final departStart = departure == null ? null : end.subtract(Duration(minutes: departure.durationMin));

    for (var i = 0; i < dates.length; i++) {
      final d = dates[i];
      final slots = <ItinerarySlot>[];

      if (arrival != null && _sameDay(input.start, d)) {
        slots.add(
          ItinerarySlot(
            kind: SlotKind.transit,
            start: input.start,
            end: arrivalEnd!,
            title: '${arrival.mode.label} from ${arrival.from} to ${arrival.to}',
            location: arrival.toPoint,
            costInr: arrival.costInr,
            leg: arrival,
            note: arrival.note,
          ),
        );
      }
      if (arrival != null && arrivalEnd != null && _sameDay(arrivalEnd, d) && !_sameDay(input.start, d)) {
        slots.add(
          ItinerarySlot(
            kind: SlotKind.transit,
            start: DateTime(d.year, d.month, d.day),
            end: arrivalEnd,
            title: 'Arrive in ${arrival.to} (${arrival.mode.label.toLowerCase()})',
            location: arrival.toPoint,
            leg: arrival,
          ),
        );
      }
      if (arrivalEnd != null && _sameDay(arrivalEnd, d) && input.baseName.isNotEmpty) {
        slots.add(
          ItinerarySlot(
            kind: SlotKind.stay,
            start: arrivalEnd,
            end: arrivalEnd.add(const Duration(minutes: 45)),
            title: 'Check in at ${input.baseName}',
            location: input.base,
            note: 'Drop bags and freshen up; formal check-in is usually mid-afternoon.',
          ),
        );
      }
      slots.addAll(slotsByDay[i] ?? const []);

      if (departure != null && departStart != null && _sameDay(end, d)) {
        slots.add(
          ItinerarySlot(
            kind: SlotKind.stay,
            start: departStart.subtract(const Duration(minutes: 75)),
            end: departStart.subtract(const Duration(minutes: 45)),
            title: 'Check out of ${input.baseName}',
            location: input.base,
          ),
        );
        slots.add(
          ItinerarySlot(
            kind: SlotKind.transit,
            start: departStart,
            end: end,
            title: '${departure.mode.label} home to ${departure.to}',
            location: departure.toPoint,
            costInr: departure.costInr,
            leg: departure,
            note: departure.note,
          ),
        );
      }
      slots.sort((a, b) => a.start.compareTo(b.start));

      final f = input.weather[_iso(d)];
      out.add(
        ItineraryDay(
          number: i + 1,
          date: d,
          title: _titleFor(i, dates.length, slots),
          slots: slots,
          weather: f?.summary,
        ),
      );
    }
    return out;
  }

  static String _titleFor(int i, int count, List<ItinerarySlot> slots) {
    final visits = [for (final s in slots) if (s.kind == SlotKind.visit) s.title];
    final where = visits.isEmpty
        ? null
        : visits.length == 1
        ? visits.first
        : '${visits.first} and ${visits.length - 1} more';
    if (i == 0 && slots.any((s) => s.kind == SlotKind.stay && s.title.startsWith('Check in'))) {
      return where == null ? 'Arrive and settle in' : 'Arrive · $where';
    }
    if (i == count - 1 && count > 1 && slots.any((s) => s.title.startsWith('Check out'))) {
      return where == null ? 'Head home' : '$where · head home';
    }
    return where ?? 'A free day';
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  static String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static double _km(LatLng a, LatLng b) => haversineKm(a.latitude, a.longitude, b.latitude, b.longitude);
}

class _Window {
  const _Window(this.start, this.end);

  final DateTime start;
  final DateTime end;

  int get minutes => end.difference(start).inMinutes;
}

class _Pick {
  const _Pick(this.place, this.startAt, this.end, this.cost, this.wait);

  final Hotspot place;
  final DateTime startAt;
  final DateTime end;
  final double cost;
  final int wait;
}

class _DayResult {
  const _DayResult(this.slots, this.placed, {this.capped = false});

  final List<ItinerarySlot> slots;
  final List<Hotspot> placed;

  /// The day stopped at its place limit with places still waiting.
  final bool capped;
}
