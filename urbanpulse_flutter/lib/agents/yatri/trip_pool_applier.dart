import 'dart:math' as math;

import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/itinerary/trip_pool.dart';
import '../../models/trip_brief.dart';

/// Rewrites an itinerary for Trip-pooling: the journey becomes one shared car
/// whose cost and CO2 are split by seats. Both travellers' apps run this on
/// their own plan, so the shared journey agrees on both sides.
abstract final class TripPoolApplier {
  /// An outstation cab, per vehicle (fuel, driver, tolls), India 2026.
  static const cabInrPerKm = 13.0;

  /// A car's own emissions per km: the per-passenger figure assumes about 1.5
  /// people aboard.
  static double get carGramsPerKm => TripTransportMode.carTaxi.gCo2PerPaxKm * 1.5;

  static const _carLike = {TripTransportMode.carTaxi, TripTransportMode.sharedEv, TripTransportMode.selfDriveEv};

  /// Adds [mate] to the pool (starting it on the first one).
  static Itinerary join(Itinerary it, TripPoolMate mate) {
    final pool = it.pool ?? start(it);
    if (pool == null) return it;
    return _apply(it, pool.withMate(mate));
  }

  /// Removes a mate; the last one leaving restores the solo journey.
  static Itinerary leave(Itinerary it, String requestId) {
    final pool = it.pool;
    if (pool == null || !pool.mates.any((m) => m.requestId == requestId)) return it;
    final next = pool.withoutMate(requestId);
    if (next.mates.isEmpty) return _restore(it, pool);
    return _apply(it, next);
  }

  /// The shared vehicle for this trip's journey, or null when there is no
  /// journey to share.
  static TripPool? start(Itinerary it) {
    final leg = it.chosenTransport;
    if (leg == null || leg.walking || leg.distanceKm <= 0) return null;
    final mine = math.max(1, it.brief?.travellerCount ?? 1);
    final carLike = _carLike.contains(leg.mode);
    final myVehicles = (mine / 4).ceil();
    return TripPool(
      vehicleCostInr: carLike ? (leg.costInr / myVehicles).round() : (leg.distanceKm * cabInrPerKm).round(),
      vehicleCo2Grams: carLike && leg.co2Grams > 0 ? (leg.co2Grams / myVehicles).round() : (leg.distanceKm * carGramsPerKm).round(),
      soloCostInr: leg.costInr,
      soloCo2Grams: leg.co2Grams,
      myTravellers: mine,
      soloLeg: leg,
    );
  }

  /// What joining a pool of [otherTravellers] would cost this traveller, for
  /// the offer shown before asking.
  static TripPool? preview(Itinerary it, int otherTravellers) =>
      start(it)?.withMate(TripPoolMate(requestId: 'preview', name: '', travellers: otherTravellers));

  static Itinerary _apply(Itinerary it, TripPool pool) {
    final solo = pool.soloLeg;
    final previous = it.chosenTransport ?? solo;
    final shared = TransportLeg(
      id: solo.id,
      from: solo.from,
      to: solo.to,
      mode: solo.mode == TripTransportMode.selfDriveEv || solo.mode == TripTransportMode.sharedEv ? TripTransportMode.sharedEv : TripTransportMode.carTaxi,
      distanceKm: solo.distanceKm,
      durationMin: _carLike.contains(solo.mode) ? solo.durationMin : (solo.distanceKm / 55 * 60).round(),
      costInr: pool.myCostInr,
      co2Grams: pool.myCo2Grams,
      stepFree: _carLike.contains(solo.mode) && solo.stepFree,
      note: 'Trip-pool with ${pool.matesLabel}: ${pool.seatsUsed} seats in ${pool.vehicles == 1 ? 'one shared car' : '${pool.vehicles} shared cars'}; this is your share.',
      fromPoint: solo.fromPoint,
      toPoint: solo.toPoint,
    );
    return _withJourney(it, previous, shared, pool, [
      'Trip-pool: sharing the ride with ${pool.matesLabel}. Your share of the journey is ₹${pool.myCostInr}'
          '${pool.savedInr > 0 ? ' (₹${pool.savedInr} less than going alone)' : ''}'
          '${pool.savedCo2Kg >= 0.1 ? ' and ${pool.savedCo2Kg.toStringAsFixed(1)} kg less CO₂' : ''}.',
    ]);
  }

  static Itinerary _restore(Itinerary it, TripPool pool) =>
      _withJourney(it, it.chosenTransport ?? pool.soloLeg, pool.soloLeg, null, const []);

  /// Swaps the journey leg everywhere it appears, with its cost and CO2.
  static Itinerary _withJourney(Itinerary it, TransportLeg before, TransportLeg after, TripPool? pool, List<String> notes) {
    final costDelta = after.costInr - before.costInr;
    final co2DeltaKg = (after.co2Grams - before.co2Grams) / 1000;

    final days = [
      for (final d in it.days)
        ItineraryDay(
          number: d.number,
          date: d.date,
          title: d.title,
          weather: d.weather,
          slots: [
            for (final s in d.slots)
              if (s.leg?.id == before.id)
                ItinerarySlot(
                  kind: s.kind,
                  start: s.start,
                  end: s.end,
                  title: pool == null ? s.title : 'Trip-pool ride to ${after.to}',
                  location: s.location,
                  refId: s.refId,
                  note: pool == null ? s.note : after.note,
                  costInr: s.costInr == null ? null : after.costInr,
                  leg: after,
                  access: s.access,
                  flags: s.flags,
                )
              else
                s,
          ],
        ),
    ];

    // The journey's budget line: the one that matches its cost, else the first
    // transport line.
    final lines = [...it.budget.lines];
    var i = lines.indexWhere((l) => l.category == BudgetCategory.transport && l.amountInr == before.costInr);
    if (i < 0) i = lines.indexWhere((l) => l.category == BudgetCategory.transport);
    if (i >= 0) {
      final l = lines[i];
      final base = l.label.replaceAll(' · Trip-pool share', '');
      lines[i] = BudgetLine(
        label: pool == null ? base : '$base · Trip-pool share',
        amountInr: math.max(0, l.amountInr + costDelta),
        category: l.category,
        isEstimated: true,
      );
    }

    final g = it.green;
    final green = g == null
        ? null
        : GreenReport(
            co2Kg: math.max(0, g.co2Kg + co2DeltaKg),
            co2SavedKg: math.max(0, g.co2SavedKg - co2DeltaKg),
            score: g.score,
            tips: g.tips,
            breakdown: {
              for (final e in g.breakdown.entries) e.key: e.key == 'Journey' ? math.max(0, e.value + co2DeltaKg) : e.value,
            },
            baselineKg: g.baselineKg,
          );

    return it.copyWith(
      chosenTransport: after,
      days: days,
      budget: Budget(lines: lines, budgetMinInr: it.budget.budgetMinInr, budgetMaxInr: it.budget.budgetMaxInr),
      green: green,
      assumptions: [for (final a in it.assumptions) if (!a.startsWith('Trip-pool:')) a, ...notes],
      pool: pool,
      clearPool: pool == null,
    );
  }
}
