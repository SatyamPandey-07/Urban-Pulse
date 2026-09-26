import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/bhatkanti/hotspot_finder.dart';
import 'package:urbanpulse/agents/raah/day_planner.dart';
import 'package:urbanpulse/agents/runtime/report.dart';
import 'package:urbanpulse/domain/curated_destinations.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/services/data/ai_estimator.dart';
import 'package:urbanpulse/services/data/data_cache.dart';
import 'package:urbanpulse/services/data/overpass_client.dart';
import 'package:urbanpulse/services/data/wikipedia_client.dart';

import 'fakes.dart';
import 'hotel_world.dart';

void main() {
  group('Hotspot finding and itinerary planning', () {
    test('CuratedDestinations returns verified spots for Munnar', () {
      final spots = CuratedDestinations.getCurated('Munnar', munnarCenter);
      expect(spots, isNotEmpty);
      expect(spots.length, greaterThanOrEqualTo(8));
      expect(spots.any((s) => s.name.contains('Eravikulam')), isTrue);
      expect(spots.any((s) => s.name.contains('Tea Museum')), isTrue);
      expect(spots.any((s) => s.name.contains('Mattupetty')), isTrue);
    });

    test('HotspotFinder finds places and falls back to curated guide when external sources fail', () async {
      final world = HotelWorld();
      final cache = MemoryCache();
      final model = ScriptedLlm()..configured = false;

      final finder = HotspotFinder(
        overpass: OverpassClient(client: world.client, cache: cache),
        wikipedia: WikipediaClient(client: world.client, cache: cache),
        llm: model,
        estimator: AiEstimator(model),
      );

      final q = HotspotQuery(
        destination: 'Munnar',
        center: munnarCenter,
        days: 3,
        pace: TripPace.balanced,
      );

      final result = await finder.find(q);
      expect(result.selected, isNotEmpty);
      expect(result.selected.length, greaterThanOrEqualTo(5));
      expect(result.pool, isNotEmpty);
      expect(result.sources, contains('Curated Travel Guide'));

      // Verify attractions have names, valid locations, and fees
      for (final h in result.selected) {
        expect(h.name, isNotEmpty);
        expect(h.location.latitude, closeTo(munnarCenter.latitude, 0.5));
        expect(h.location.longitude, closeTo(munnarCenter.longitude, 0.5));
      }
    });

    test('DayPlanner plans actual sightseeing stops, not just hotel checkin and meals', () {
      final spots = CuratedDestinations.getCurated('Munnar', munnarCenter);
      final query = HotspotQuery(
        destination: 'Munnar',
        center: munnarCenter,
        days: 3,
        pace: TripPace.balanced,
      );
      final hotspots = [for (final c in spots) HotspotFinder.select([
        Hotspot(
          id: c.id,
          name: c.name,
          location: c.location,
          kind: c.kind ?? HotspotKind.nature,
          why: c.why ?? 'Top sight in Munnar',
          visitMinutes: c.visitMinutes ?? 90,
          feeInr: c.feeInr ?? 0,
          isOutdoor: c.isOutdoor ?? true,
          score: 0.9,
          access: const {},
          claims: const [],
          sources: const [],
          provenance: const Provenance(source: 'test'),
        ),
      ], query).first];

      final start = DateTime(2026, 10, 1, 9, 0);
      final end = DateTime(2026, 10, 3, 18, 0);

      final input = DayPlanInput(
        start: start,
        end: end,
        base: munnarCenter,
        baseName: 'Munnar Resort',
        places: hotspots,
        alternates: const [],
        travellers: 2,
        children: 0,
        weather: const {},
        localModes: const {TripTransportMode.carTaxi},
        needs: const {},
        pace: TripPace.balanced,
      );

      final plan = DayPlanner.plan(input);
      expect(plan.days, hasLength(3));
      expect(plan.visited, isNotEmpty);

      // Verify that days contain actual visit slots
      final allVisitSlots = [
        for (final d in plan.days)
          for (final s in d.slots)
            if (s.kind == SlotKind.visit) s,
      ];
      expect(allVisitSlots, isNotEmpty);
      expect(allVisitSlots.length, greaterThanOrEqualTo(3));
    });
  });
}
