import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../domain/access/access_rules.dart';
import '../../domain/regional_defaults.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../services/data/http_util.dart';
import '../runtime/report.dart';

/// How a mode of transport behaves, in numbers a plan can be built from. These
/// are typical values, not timetables, so every leg built from them is labelled
/// an estimate.
class ModeProfile {
  const ModeProfile({
    required this.speedKmh,
    required this.overheadMin,
    required this.roadFactor,
    required this.fareMinPerPax,
    this.perVehicle = false,
    this.minKm = 0,
    this.maxKm = 100000,
    this.childFactor = 0.6,
  });

  /// Average moving speed over the whole route.
  final double speedKmh;

  /// Getting to and from it: check-in, waiting, transfers.
  final int overheadMin;

  /// Route length relative to the straight line.
  final double roadFactor;
  final int fareMinPerPax;

  /// Priced per vehicle (cab, own car) rather than per person.
  final bool perVehicle;
  final double minKm;
  final double maxKm;

  /// A child's fare as a share of an adult's.
  final double childFactor;
}

/// What each mode is like for each access need, from general knowledge of how
/// these services work. Never a promise: the notes say to confirm.
abstract final class ModeAccess {
  static (SupportLevel, String) of(TripTransportMode mode, AccessibilityNeed need) {
    (SupportLevel, String) r(SupportLevel l, String d) => (l, d);
    const yes = SupportLevel.yes;
    const part = SupportLevel.partial;
    const no = SupportLevel.no;
    const unk = SupportLevel.unknown;
    final bool wc = need == AccessibilityNeed.wheelchair;
    final bool mobility = need == AccessibilityNeed.limitedMobility || need == AccessibilityNeed.elderlyCare;

    switch (mode) {
      case TripTransportMode.flight:
        return switch (need) {
          AccessibilityNeed.wheelchair => r(yes, 'Airlines offer wheelchair assistance and an aisle chair; request it when booking.'),
          AccessibilityNeed.limitedMobility || AccessibilityNeed.elderlyCare => r(yes, 'Assistance is available at the airport; request it when booking.'),
          AccessibilityNeed.visual => r(yes, 'Airports provide guided assistance on request.'),
          AccessibilityNeed.hearing => r(yes, 'Boarding and gate information is shown on screens; tell the airline about a hearing need.'),
          AccessibilityNeed.serviceAnimal => r(part, 'Service animals are usually allowed in the cabin with paperwork; check the airline.'),
          _ => r(unk, 'Ask the airline about this need.'),
        };
      case TripTransportMode.train:
        if (wc) return r(part, 'Stations often have stairs; book assistance and an accessible coach in advance.');
        if (mobility) return r(part, 'Lower berths and assistance can be requested; platforms may have steps.');
        if (need == AccessibilityNeed.visual) return r(part, 'Station staff can assist on request; not all stations have tactile guidance.');
        if (need == AccessibilityNeed.hearing) return r(part, 'Departures are shown on boards, but announcements are audio only at many stations.');
        if (need == AccessibilityNeed.serviceAnimal) return r(part, 'Service animals are often allowed; confirm with the railway.');
        return r(unk, 'Confirm this need with the operator.');
      case TripTransportMode.metroLocal:
        return switch (need) {
          AccessibilityNeed.wheelchair || AccessibilityNeed.limitedMobility || AccessibilityNeed.elderlyCare =>
            r(yes, 'Metros usually have lifts, ramps and priority seating.'),
          AccessibilityNeed.visual => r(yes, 'Tactile paving and audio announcements are usual.'),
          AccessibilityNeed.hearing => r(yes, 'Trains and stations show information on screens.'),
          AccessibilityNeed.serviceAnimal => r(part, 'Rules vary; confirm with the operator.'),
          _ => r(unk, 'Confirm this need with the operator.'),
        };
      case TripTransportMode.eBus:
        if (wc) return r(part, 'Low-floor buses exist in some cities; check the route.');
        if (mobility) return r(part, 'Low-floor buses help, but seating and steps vary.');
        if (need == AccessibilityNeed.visual) return r(part, 'Some buses announce stops; a companion is advisable.');
        if (need == AccessibilityNeed.hearing) return r(part, 'Stops are not always shown on a screen.');
        return r(unk, 'Confirm this need with the operator.');
      case TripTransportMode.bus:
        if (wc) return r(no, 'Most buses have steps and no wheelchair space.');
        if (mobility) return r(part, 'Boarding involves steps; choose a low-floor or reserved seat where possible.');
        if (need == AccessibilityNeed.visual) return r(part, 'Stop announcements are rare; a companion is advisable.');
        if (need == AccessibilityNeed.hearing) return r(part, 'Information is mostly spoken; a companion or written notes help.');
        return r(unk, 'Confirm this need with the operator.');
      case TripTransportMode.sharedEv:
      case TripTransportMode.carTaxi:
        if (wc) return r(part, 'A folding wheelchair fits in most boots; accessible vehicles are rare, so confirm with the driver.');
        if (mobility) return r(yes, 'Door-to-door travel avoids stairs and long walks.');
        if (need == AccessibilityNeed.visual) return r(yes, 'Door-to-door travel with a driver is easy to manage.');
        if (need == AccessibilityNeed.hearing) return r(yes, 'Share the destination in writing or on the app.');
        if (need == AccessibilityNeed.serviceAnimal) return r(part, 'Ask the driver before booking.');
        return r(unk, 'Confirm this need with the driver.');
      case TripTransportMode.selfDriveEv:
        if (wc) return r(yes, 'Your own vehicle: load the chair and go at your pace.');
        if (mobility) return r(yes, 'Your own vehicle avoids stairs and long walks.');
        if (need == AccessibilityNeed.visual) return r(no, 'Driving needs sight; a sighted driver in the group is required.');
        if (need == AccessibilityNeed.hearing) return r(yes, 'Nothing about hearing limits self-driving.');
        if (need == AccessibilityNeed.serviceAnimal) return r(yes, 'Your animal travels with you.');
        return r(unk, 'Confirm this need for your group.');
    }
  }
}

abstract final class TransportProfiles {
  static const Map<TripTransportMode, ModeProfile> byMode = {
    TripTransportMode.train: ModeProfile(speedKmh: 58, overheadMin: 60, roadFactor: 1.2, fareMinPerPax: 120, minKm: 30, maxKm: 3500),
    TripTransportMode.bus: ModeProfile(speedKmh: 44, overheadMin: 35, roadFactor: 1.3, fareMinPerPax: 60, minKm: 10, maxKm: 1200),
    TripTransportMode.eBus: ModeProfile(speedKmh: 46, overheadMin: 35, roadFactor: 1.3, fareMinPerPax: 80, minKm: 10, maxKm: 450),
    TripTransportMode.sharedEv: ModeProfile(speedKmh: 45, overheadMin: 20, roadFactor: 1.3, fareMinPerPax: 100, minKm: 5, maxKm: 500),
    TripTransportMode.selfDriveEv: ModeProfile(speedKmh: 46, overheadMin: 20, roadFactor: 1.3, fareMinPerPax: 150, perVehicle: true, minKm: 5, maxKm: 900),
    TripTransportMode.carTaxi: ModeProfile(speedKmh: 50, overheadMin: 10, roadFactor: 1.3, fareMinPerPax: 200, perVehicle: true, minKm: 1, maxKm: 1800),
    TripTransportMode.flight: ModeProfile(speedKmh: 700, overheadMin: 210, roadFactor: 1.05, fareMinPerPax: 2200, minKm: 250, maxKm: 20000, childFactor: 0.75),
    TripTransportMode.metroLocal: ModeProfile(speedKmh: 30, overheadMin: 12, roadFactor: 1.25, fareMinPerPax: 20, minKm: 1, maxKm: 60, childFactor: 0.5),
  };
}

class TransportQuery {
  const TransportQuery({
    required this.originName,
    required this.destinationName,
    required this.origin,
    required this.destination,
    required this.travellers,
    this.adults = 1,
    this.children = 0,
    this.modes = const {},
    this.needs = const {},
    this.priority = SustainabilityPriority.balanced,
    this.departure,
  });

  final String originName;
  final String destinationName;
  final LatLng origin;
  final LatLng destination;
  final int travellers;
  final int adults;
  final int children;

  /// The modes the traveller ticked; empty means "any".
  final Set<TripTransportMode> modes;
  final Set<AccessibilityNeed> needs;
  final SustainabilityPriority priority;
  final DateTime? departure;
}

/// The outbound options and which one Safar would pick.
class TransportPlan {
  const TransportPlan({
    required this.query,
    required this.options,
    required this.recommendedIndex,
    required this.distanceKm,
    this.assumptions = const [],
    this.notes = const {},
  });

  final TransportQuery query;

  /// One-way legs, origin to destination. The return trip mirrors the chosen one.
  final List<TransportLeg> options;
  final int recommendedIndex;

  /// Straight-line distance between the two places.
  final double distanceKm;
  final List<String> assumptions;

  /// Extra per-mode remarks (from the model), by mode name.
  final Map<String, String> notes;

  bool get isEmpty => options.isEmpty;
  TransportLeg? get recommended => options.isEmpty ? null : options[recommendedIndex.clamp(0, options.length - 1)];

  TransportPlan withChoice(int index) => TransportPlan(
    query: query,
    options: options,
    recommendedIndex: index,
    distanceKm: distanceKm,
    assumptions: assumptions,
    notes: notes,
  );
}

/// Safar's engine. Deterministic: distances, times, fares and emissions come
/// from mode profiles, so the result never depends on a model being available.
abstract final class TransportPlanner {
  /// Journeys shorter than this need no intercity leg.
  static const localOnlyKm = 3.0;

  static bool feasible(TripTransportMode m, double km) {
    final p = TransportProfiles.byMode[m]!;
    return km >= p.minKm && km <= p.maxKm;
  }

  static TransportPlan plan(TransportQuery q) {
    final km = haversineKm(q.origin.latitude, q.origin.longitude, q.destination.latitude, q.destination.longitude);
    final assumptions = <String>[];
    if (km < localOnlyKm) {
      return TransportPlan(
        query: q,
        options: const [],
        recommendedIndex: 0,
        distanceKm: km,
        assumptions: ['${q.originName} and ${q.destinationName} are close together, so no long-distance travel is planned.'],
      );
    }

    final intercity = TripTransportMode.values.where((m) => m != TripTransportMode.metroLocal || km <= 60).toList();
    var modes = [for (final m in TripTransportMode.values) if (q.modes.contains(m) && feasible(m, km)) m];
    final chosenButImpossible = [for (final m in q.modes) if (!feasible(m, km)) m];
    if (chosenButImpossible.isNotEmpty) {
      assumptions.add(
        '${chosenButImpossible.map((m) => m.label).join(', ')} ${chosenButImpossible.length == 1 ? 'is' : 'are'} not practical '
        'for about ${km.round()} km, so ${modes.isEmpty ? 'other options are shown' : 'it was left out'}.',
      );
    }
    if (modes.length < 2) {
      // Offer a sensible alternative so there is a real choice.
      final extras = [for (final m in intercity) if (!modes.contains(m) && feasible(m, km) && m != TripTransportMode.metroLocal) m]
        ..sort((a, b) => a.gCo2PerPaxKm.compareTo(b.gCo2PerPaxKm));
      final need = math.min(extras.length, modes.isEmpty ? 3 : 2 - modes.length);
      if (need > 0) {
        modes = [...modes, ...extras.take(need)];
        if (q.modes.isNotEmpty && chosenButImpossible.isEmpty) assumptions.add('An alternative was added so you can compare.');
      }
    }

    final legs = [for (final m in modes) _leg(q, m, km)];
    if (legs.isEmpty) {
      return TransportPlan(query: q, options: const [], recommendedIndex: 0, distanceKm: km, assumptions: assumptions);
    }
    final best = _recommended(q, legs);
    return TransportPlan(query: q, options: legs, recommendedIndex: best, distanceKm: km, assumptions: assumptions);
  }

  static int paying(TransportQuery q) {
    final grown = math.max(1, q.travellers - q.children);
    return grown;
  }

  static TransportLeg _leg(TransportQuery q, TripTransportMode m, double straightKm) {
    final p = TransportProfiles.byMode[m]!;
    final road = straightKm * p.roadFactor;
    var minutes = (road / p.speedKmh * 60).round() + p.overheadMin;
    // A self-drive EV needs charging stops on long runs.
    if (m == TripTransportMode.selfDriveEv) minutes += (road / 220).floor() * 35;

    final units = paying(q) + q.children * p.childFactor;
    final vehicles = math.max(1, (q.travellers / 4).ceil());
    var cost = p.perVehicle
        ? RegionalDefaults.farePerKmInr(m.name) * road * vehicles
        : math.max(p.fareMinPerPax.toDouble(), RegionalDefaults.farePerKmInr(m.name) * road) * units;
    if (p.perVehicle) cost = math.max(cost, p.fareMinPerPax.toDouble() * vehicles);
    // Road tolls, driver's allowance and the return run make cabs dearer than the metered rate.
    if (m == TripTransportMode.carTaxi) cost *= 1.15;

    final grams = (m.gCo2PerPaxKm * road * q.travellers).round();
    final wc = ModeAccess.of(m, AccessibilityNeed.wheelchair);
    final note = _note(q, m);
    return TransportLeg(
      id: 'intercity.${m.name}',
      from: q.originName,
      to: q.destinationName,
      mode: m,
      distanceKm: double.parse(road.toStringAsFixed(1)),
      durationMin: minutes,
      costInr: _roundTo(cost.round(), 10),
      co2Grams: grams,
      stepFree: wc.$1 == SupportLevel.yes,
      note: note,
      isEstimated: true,
      fromPoint: q.origin,
      toPoint: q.destination,
    );
  }

  static String? _note(TransportQuery q, TripTransportMode m) {
    final needs = AccessRules.relevant(q.needs);
    if (needs.isEmpty) return null;
    final lines = <String>[];
    for (final n in needs) {
      final (level, detail) = ModeAccess.of(m, n);
      if (level == SupportLevel.unknown) continue;
      lines.add(detail);
    }
    return lines.isEmpty ? null : lines.take(2).join(' ');
  }

  /// Weighs cost, time and emissions by what the traveller cares about, and
  /// penalises modes that fit their access needs badly.
  static int _recommended(TransportQuery q, List<TransportLeg> legs) {
    double norm(num v, num lo, num hi) => hi <= lo ? 0 : ((v - lo) / (hi - lo)).toDouble();
    final costs = legs.map((l) => l.costInr).toList();
    final times = legs.map((l) => l.durationMin).toList();
    final co2 = legs.map((l) => l.co2Grams).toList();
    final (wc, wt, we) = switch (q.priority) {
      SustainabilityPriority.greenest => (0.25, 0.25, 0.5),
      SustainabilityPriority.convenience => (0.3, 0.5, 0.2),
      SustainabilityPriority.balanced => (0.33, 0.34, 0.33),
    };
    var bestIdx = 0;
    var best = double.infinity;
    for (var i = 0; i < legs.length; i++) {
      var score = wc * norm(costs[i], costs.reduce(math.min), costs.reduce(math.max)) +
          wt * norm(times[i], times.reduce(math.min), times.reduce(math.max)) +
          we * norm(co2[i], co2.reduce(math.min), co2.reduce(math.max));
      score += accessPenalty(q.needs, legs[i].mode);
      if (score < best) {
        best = score;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  /// 0 for a mode that suits every need, up to about 0.5 for one that cannot.
  static double accessPenalty(Set<AccessibilityNeed> needs, TripTransportMode mode) {
    final list = AccessRules.relevant(needs);
    if (list.isEmpty) return 0;
    var sum = 0.0;
    for (final n in list) {
      sum += switch (ModeAccess.of(mode, n).$1) {
        SupportLevel.yes => 0.0,
        SupportLevel.partial => 0.12,
        SupportLevel.unknown => 0.08,
        SupportLevel.no => 0.5,
      };
    }
    return sum / list.length;
  }

  // --- local legs ---------------------------------------------------------

  /// A short trip inside the destination: on foot when it is close and the
  /// group can walk, else by the group's preferred local vehicle.
  static TransportLeg local({
    required String id,
    required String fromName,
    required String toName,
    required LatLng from,
    required LatLng to,
    required int travellers,
    Set<TripTransportMode> preferred = const {},
    Set<AccessibilityNeed> needs = const {},
  }) {
    final straight = haversineKm(from.latitude, from.longitude, to.latitude, to.longitude);
    final road = math.max(0.05, straight * 1.3);
    final limited = needs.any(
      (n) => n == AccessibilityNeed.wheelchair || n == AccessibilityNeed.limitedMobility || n == AccessibilityNeed.elderlyCare,
    );
    final walkLimitKm = limited ? 0.25 : 0.7;
    if (road <= walkLimitKm) {
      return TransportLeg(
        id: id,
        from: fromName,
        to: toName,
        mode: TripTransportMode.carTaxi,
        walking: true,
        distanceKm: double.parse(road.toStringAsFixed(2)),
        durationMin: math.max(2, (road / 4.2 * 60).round()),
        costInr: 0,
        co2Grams: 0,
        stepFree: !needs.contains(AccessibilityNeed.wheelchair) || road <= 0.1,
        isEstimated: true,
        fromPoint: from,
        toPoint: to,
      );
    }

    final mode = preferred.contains(TripTransportMode.sharedEv)
        ? TripTransportMode.sharedEv
        : preferred.contains(TripTransportMode.selfDriveEv)
        ? TripTransportMode.selfDriveEv
        : TripTransportMode.carTaxi;
    final vehicles = math.max(1, (travellers / 4).ceil());
    final cost = switch (mode) {
      TripTransportMode.sharedEv => math.max(40, 9 * road) * math.max(1, travellers / 2),
      TripTransportMode.selfDriveEv => math.max(20, 4 * road),
      _ => math.max(70, 14 * road) * vehicles,
    };
    final wc = ModeAccess.of(mode, AccessibilityNeed.wheelchair);
    return TransportLeg(
      id: id,
      from: fromName,
      to: toName,
      mode: mode,
      distanceKm: double.parse(road.toStringAsFixed(1)),
      durationMin: math.max(6, (road / 22 * 60).round() + 5),
      costInr: _roundTo(cost.round(), 10),
      co2Grams: (mode.gCo2PerPaxKm * road * travellers).round(),
      stepFree: wc.$1 == SupportLevel.yes,
      note: mode == TripTransportMode.carTaxi && needs.contains(AccessibilityNeed.wheelchair) ? wc.$2 : null,
      isEstimated: true,
      fromPoint: from,
      toPoint: to,
    );
  }

  static int _roundTo(int v, int step) => ((v + step ~/ 2) ~/ step) * step;
}

/// A short "9h 30m" for a duration in minutes.
String durationLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// The Provenance to attach to values derived from [ModeAccess].
const modeProvenance = Provenance(source: 'Typical for this mode of transport', confidence: 0.5);
