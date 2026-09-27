import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/agents/yatri/surprise_me.dart';
import 'package:urbanpulse/agents/yatri/trip_pool_applier.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';
import 'package:urbanpulse/models/itinerary/trip_pool.dart';
import 'package:urbanpulse/models/trip_brief.dart';

Itinerary _trip({TripTransportMode mode = TripTransportMode.carTaxi, int travellers = 2}) {
  final start = DateTime(2026, 7, 20, 7);
  final leg = TransportLeg(id: 'journey', from: 'Mumbai', to: 'Lonavala', mode: mode, distanceKm: 83, durationMin: 120, costInr: 2400, co2Grams: 21000);
  return Itinerary(
    id: 'it1',
    createdAt: start,
    destination: 'Lonavala',
    origin: 'Mumbai',
    start: start,
    end: start.add(const Duration(days: 1)),
    chosenTransport: leg,
    days: [
      ItineraryDay(
        number: 1,
        date: start,
        title: 'Arrive',
        slots: [ItinerarySlot(kind: SlotKind.transit, start: start, end: start.add(const Duration(hours: 2)), title: 'Cab to Lonavala', leg: leg, costInr: 2400)],
      ),
    ],
    budget: const Budget(lines: [BudgetLine(label: 'Journey', amountInr: 2400, category: BudgetCategory.transport)]),
    green: const GreenReport(co2Kg: 30, co2SavedKg: 5, breakdown: {'Journey': 21}),
    brief: TripBrief(id: 'brief_1', createdAt: start, destination: 'Lonavala', start: start, travellerCount: travellers),
  );
}

void main() {
  group('Trip-pool', () {
    test('sharing the car splits its cost and CO2 by seats, everywhere the journey appears', () {
      final pooled = TripPoolApplier.join(_trip(), const TripPoolMate(requestId: 'r1', name: 'Asha', travellers: 2, origin: 'Mumbai'));
      final pool = pooled.pool!;
      expect(pool.seatsUsed, 4);
      expect(pool.myCostInr, 1200); // half of one car
      expect(pooled.chosenTransport!.costInr, 1200);
      expect(pooled.chosenTransport!.note, contains('Asha'));
      expect(pooled.days.first.slots.first.leg!.costInr, 1200);
      expect(pooled.budget.lines.first.amountInr, 1200);
      expect(pooled.budget.lines.first.label, contains('Trip-pool'));
      expect(pooled.green!.co2Kg, closeTo(30 - 10.5, 0.01));
      expect(pooled.assumptions.single, startsWith('Trip-pool:'));
      expect(pool.savedInr, 1200);
    });

    test('a second mate shares further; the last one leaving restores the solo journey', () {
      var it = TripPoolApplier.join(_trip(travellers: 1), const TripPoolMate(requestId: 'r1', name: 'Asha', travellers: 1));
      it = TripPoolApplier.join(it, const TripPoolMate(requestId: 'r2', name: 'Ravi', travellers: 1));
      expect(it.pool!.seatsUsed, 3);
      expect(it.chosenTransport!.costInr, 800);
      // Joining again with the same request changes nothing.
      expect(TripPoolApplier.join(it, const TripPoolMate(requestId: 'r2', name: 'Ravi', travellers: 1)).chosenTransport!.costInr, 800);
      it = TripPoolApplier.leave(it, 'r1');
      expect(it.chosenTransport!.costInr, 1200);
      it = TripPoolApplier.leave(it, 'r2');
      expect(it.pool, isNull);
      expect(it.chosenTransport!.costInr, 2400);
      expect(it.budget.lines.first.amountInr, 2400);
      expect(it.budget.lines.first.label, 'Journey');
      expect(it.assumptions, isEmpty);
    });

    test('a train trip pools as a shared cab, and the pool survives saving', () {
      final it = TripPoolApplier.join(_trip(mode: TripTransportMode.train), const TripPoolMate(requestId: 'r1', name: 'Asha', travellers: 2));
      expect(it.chosenTransport!.mode, TripTransportMode.carTaxi);
      expect(it.pool!.vehicleCostInr, (83 * TripPoolApplier.cabInrPerKm).round());
      final back = Itinerary.fromJson(jsonDecode(jsonEncode(it.toJson())) as Map<String, dynamic>);
      expect(back.pool!.mates.single.name, 'Asha');
      expect(back.pool!.soloLeg.mode, TripTransportMode.train);
      expect(back.brief!.tripPool, isFalse);
    });
  });

  group('Surprise Me', () {
    const mumbai = LatLng(19.076, 72.8777);

    test('picks somewhere new within weekend reach, from past trips', () async {
      final past = TripBrief(
        id: 'b1',
        createdAt: DateTime(2026, 5, 1),
        destination: 'Lonavala',
        originCity: 'Mumbai',
        start: DateTime(2026, 5, 2),
        end: DateTime(2026, 5, 3),
        travellerCount: 2,
        adults: 2,
        style: TripStyle.nature,
        budgetMaxInr: 12000,
      );
      final profile = TravelProfile.from(home: 'Mumbai', briefs: [past], itineraries: const []);
      final steps = <SurpriseStep>[];
      final picks = await SurpriseMe(now: () => DateTime(2026, 9, 27, 10)).pick(profile, home: mumbai, onStep: (s, _) => steps.add(s));
      expect(picks, hasLength(3));
      expect(picks.map((p) => p.place.name), isNot(contains('Lonavala')));
      expect(picks.every((p) => p.distanceKm <= 400), isTrue);
      expect(steps, SurpriseStep.values);
      final b = picks.first.brief;
      expect(b.start!.weekday, DateTime.saturday);
      expect(b.originCity, 'Mumbai');
      expect(b.travellerCount, 2);
      expect(b.style, TripStyle.nature);
    });

    test('access needs keep hard places out of the picks', () async {
      final past = TripBrief(
        id: 'b1',
        createdAt: DateTime(2026, 5, 1),
        destination: 'Goa',
        travellerCount: 2,
        accessibilityNeeds: const {AccessibilityNeed.wheelchair},
        style: TripStyle.nature,
      );
      final profile = TravelProfile.from(home: 'Mumbai', briefs: [past], itineraries: const []);
      final picks = await SurpriseMe(now: () => DateTime(2026, 9, 27, 10)).pick(profile, home: mumbai);
      expect(picks.every((p) => p.place.access > 0), isTrue);
      expect(picks.first.brief.accessibilityNeeds, contains(AccessibilityNeed.wheelchair));
    });
  });
}
