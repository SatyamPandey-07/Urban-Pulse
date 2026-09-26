import 'dart:math' as math;

import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../safar/transport_planner.dart';

/// What Hariyali measures.
class GreenInput {
  const GreenInput({
    required this.days,
    required this.nights,
    required this.rooms,
    required this.travellers,
    this.hotel,
    this.outbound,
    this.inbound,
    this.transport,
    this.hotelAlternatives = const [],
    this.needs = const {},
    this.localModes = const {},
  });

  final List<ItineraryDay> days;
  final int nights;
  final int rooms;
  final int travellers;
  final HotelOption? hotel;
  final TransportLeg? outbound;
  final TransportLeg? inbound;
  final TransportPlan? transport;
  final List<HotelOption> hotelAlternatives;
  final Set<AccessibilityNeed> needs;
  final Set<TripTransportMode> localModes;
}

/// A greener journey Hariyali could suggest, with what it would cost the traveller.
class GreenerJourney {
  const GreenerJourney({required this.index, required this.leg, required this.savedKg, required this.extraMinutes, required this.extraCostInr});

  final int index;
  final TransportLeg leg;
  final double savedKg;
  final int extraMinutes;
  final int extraCostInr;
}

class GreenResult {
  const GreenResult({required this.report, this.greenerJourney});

  final GreenReport report;

  /// The best swap that saves a meaningful amount without hurting time, money or access.
  final GreenerJourney? greenerJourney;
}

/// Hariyali's engine: the carbon footprint of every choice, an eco score, the
/// saving against the most polluting comparable choices, and concrete greener
/// alternatives. Deterministic; emission factors are typical values, so the
/// figures are estimates and the app says so.
abstract final class GreenEngine {
  /// Typical kg CO₂e per room per night by kind of stay (energy, laundry, food service).
  static double stayKgPerNight(HotelOption? h) {
    if (h == null) return 0;
    final t = h.type.toLowerCase();
    final base = t.contains('resort')
        ? 32.0
        : (t.contains('hostel')
              ? 7.0
              : (t.contains('guest') || t.contains('home') || t.contains('cottage') || t.contains('chalet') ? 10.0 : (t.contains('apartment') ? 12.0 : 20.0)));
    final eco = h.ecoScore ?? 0;
    return base * (1 - 0.35 * eco.clamp(0.0, 1.0));
  }

  /// What a typical hotel night emits, the yardstick for "saved".
  static const _baselineStayKg = 25.0;

  static GreenResult compute(GreenInput i) {
    final out = i.outbound;
    final back = i.inbound ?? out;
    final journeyKg = ((out?.co2Grams ?? 0) + (back?.co2Grams ?? 0)) / 1000;

    var localGrams = 0;
    var localRoadKm = 0.0;
    var walkLegs = 0;
    var hopLegs = 0;
    var cabLegs = 0;
    var cabGrams = 0;
    for (final d in i.days) {
      for (final s in d.slots) {
        final l = s.leg;
        if (s.kind != SlotKind.transit || l == null || l.id.startsWith('intercity')) continue;
        hopLegs++;
        if (l.walking) {
          walkLegs++;
          continue;
        }
        localGrams += l.co2Grams;
        localRoadKm += l.distanceKm;
        if (l.mode == TripTransportMode.carTaxi) {
          cabLegs++;
          cabGrams += l.co2Grams;
        }
      }
    }
    final localKg = localGrams / 1000;
    final stayKg = stayKgPerNight(i.hotel) * i.nights * i.rooms;
    final total = journeyKg + localKg + stayKg;

    // The most polluting comparable choices, for the "saved" figure.
    final journeyBaselineKg = _journeyBaseline(i, out);
    final localBaselineKg = TripTransportMode.carTaxi.gCo2PerPaxKm * localRoadKm * i.travellers / 1000;
    final stayBaselineKg = _baselineStayKg * i.nights * i.rooms;
    final baseline = math.max(total, journeyBaselineKg + localBaselineKg + (i.hotel == null ? 0 : stayBaselineKg));
    final saved = math.max(0.0, baseline - total);

    final ratio = baseline <= 0 ? 1.0 : (total / baseline).clamp(0.0, 1.0);
    final walkShare = hopLegs == 0 ? 0.0 : walkLegs / hopLegs;
    final ecoIndex = ((i.hotel?.ecoScore ?? 0.3) + walkShare) / 2;
    final score = (75 * (1 - ratio) + 25 * ecoIndex).round().clamp(0, 100);

    // Greener journey
    GreenerJourney? greener;
    final tips = <String>[];
    final plan = i.transport;
    if (out != null && plan != null) {
      final curPenalty = TransportPlanner.accessPenalty(i.needs, out.mode);
      for (var idx = 0; idx < plan.options.length; idx++) {
        final alt = plan.options[idx];
        if (alt.mode == out.mode) continue;
        final saving = (out.co2Grams - alt.co2Grams) * 2 / 1000;
        if (saving <= 0) continue;
        if (TransportPlanner.accessPenalty(i.needs, alt.mode) > curPenalty + 0.05) continue;
        if (greener == null || saving > greener.savedKg) {
          greener = GreenerJourney(
            index: idx,
            leg: alt,
            savedKg: saving,
            extraMinutes: alt.durationMin - out.durationMin,
            extraCostInr: (alt.costInr - out.costInr) * 2,
          );
        }
      }
      if (greener != null) {
        final g = greener;
        final dur = g.extraMinutes == 0 ? 'the same travel time' : (g.extraMinutes > 0 ? '${durationLabel(g.extraMinutes)} longer each way' : '${durationLabel(-g.extraMinutes)} shorter each way');
        final money = g.extraCostInr == 0 ? 'costing about the same' : (g.extraCostInr > 0 ? 'costing about ${rupees(g.extraCostInr)} more' : 'saving about ${rupees(-g.extraCostInr)}');
        tips.add('Going by ${g.leg.mode.label.toLowerCase()} instead of ${out.mode.label.toLowerCase()} would cut about ${fixed(g.savedKg, 0)} kg CO₂ ($dur, $money).');
      }
    }

    // Local travel
    if (cabLegs >= 2 && !i.localModes.contains(TripTransportMode.sharedEv)) {
      final saving = cabGrams * (1 - TripTransportMode.sharedEv.gCo2PerPaxKm / TripTransportMode.carTaxi.gCo2PerPaxKm) / 1000;
      if (saving >= 1) tips.add('Shared EV cabs for the $cabLegs local hops would save about ${fixed(saving, 0)} kg CO₂.');
    }
    if (walkLegs > 0) tips.add('$walkLegs short hop${walkLegs == 1 ? ' is' : 's are'} planned on foot: no emissions at all.');

    // The stay
    final eco = [
      for (final h in i.hotelAlternatives)
        if (h.id != i.hotel?.id && (h.ecoScore ?? 0) >= 0.6 && h.meets(i.needs)) h,
    ]..sort((a, b) => (b.ecoScore ?? 0).compareTo(a.ecoScore ?? 0));
    if (eco.isNotEmpty && (i.hotel?.ecoScore ?? 0) < 0.6) {
      final h = eco.first;
      final saving = (stayKgPerNight(i.hotel) - stayKgPerNight(h)) * i.nights * i.rooms;
      tips.add('${h.name} shows eco practices${h.nightlyInr == null ? '' : ' (${h.priceIsEstimated ? '≈ ' : ''}${rupees(h.nightlyInr!)} a night)'}${saving >= 2 ? ' and could save about ${fixed(saving, 0)} kg CO₂' : ''}.');
    } else if ((i.hotel?.ecoScore ?? 0) >= 0.6) {
      tips.add('${i.hotel!.name} shows eco practices, which lowers the stay\'s footprint.');
    }
    if (out != null && out.mode == TripTransportMode.flight && plan != null && plan.distanceKm < 800) {
      tips.add('For under 800 km, a train or bus usually emits far less than a flight and costs less door to door.');
    }

    return GreenResult(
      report: GreenReport(
        co2Kg: double.parse(total.toStringAsFixed(1)),
        co2SavedKg: double.parse(saved.toStringAsFixed(1)),
        score: score,
        tips: tips,
        breakdown: {
          if (journeyKg > 0) 'Journey': double.parse(journeyKg.toStringAsFixed(1)),
          if (localKg > 0) 'Local travel': double.parse(localKg.toStringAsFixed(1)),
          if (stayKg > 0) 'Stay': double.parse(stayKg.toStringAsFixed(1)),
        },
        baselineKg: double.parse(baseline.toStringAsFixed(1)),
      ),
      greenerJourney: greener,
    );
  }

  /// The return trip by the most polluting practical mode, or the chosen one if
  /// it already is.
  static double _journeyBaseline(GreenInput i, TransportLeg? out) {
    if (out == null) return 0;
    var worst = out.co2Grams;
    for (final l in i.transport?.options ?? const <TransportLeg>[]) {
      if (l.co2Grams > worst) worst = l.co2Grams;
    }
    return worst * 2 / 1000;
  }
}
