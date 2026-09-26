import 'package:latlong2/latlong.dart';

import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/itinerary/plan_snapshot.dart';
import '../../models/trip_brief.dart';
import '../../services/data/forecast_client.dart';
import '../atithi/hotel_finder.dart';
import '../bhatkanti/hotspot_finder.dart';
import '../raah/day_planner.dart';
import '../safar/transport_planner.dart';

/// Puts every agent's finished work into one [Itinerary].
abstract final class ItineraryAssembler {
  static Itinerary build({
    required TripBrief brief,
    required DateTime now,
    required DayPlanResult days,
    required Budget budget,
    HotelSearchResult? hotels,
    HotelOption? hotel,
    HotspotSearchResult? spots,
    TransportPlan? transport,
    TransportLeg? chosenTransport,
    Map<String, DayForecast> weather = const {},
    AccessibilityAudit? audit,
    GreenReport? green,
    List<SourceRef> extraSources = const [],
    List<String> extraAssumptions = const [],
    LatLng? center,
    LatLng? origin,
    Set<String> bannedOutdoor = const {},
    Set<String> droppedIds = const {},
  }) {
    final assumptions = <String>[
      ...extraAssumptions,
      ...?hotels?.warnings,
      ...?spots?.warnings,
      ...?transport?.assumptions,
      ...days.notes,
      if (budget.hasEstimates) 'Lines marked as estimates use typical prices and may differ when you book.',
    ];

    final sources = <SourceRef>[];
    void addSource(SourceRef s) {
      if (s.url.isEmpty || sources.any((x) => x.url == s.url)) return;
      sources.add(s);
    }

    if (hotel != null) {
      final url = hotel.tripAdvisorUrl ?? hotel.bookingUrl;
      if (url != null) addSource(SourceRef(title: hotel.name, url: url, source: hotel.provenance.source));
      for (final c in hotel.claims) {
        c.sources.forEach(addSource);
      }
    }
    for (final h in days.visited) {
      h.sources.forEach(addSource);
      for (final c in h.claims) {
        c.sources.forEach(addSource);
      }
    }
    extraSources.forEach(addSource);

    final alternatives = [
      for (final o in hotels?.options ?? const <HotelOption>[])
        if (hotel == null || o.id != hotel.id) o,
    ];

    return Itinerary(
      id: 'itinerary_${now.millisecondsSinceEpoch}',
      createdAt: now,
      destination: brief.destination ?? '',
      origin: brief.originCity ?? '',
      start: brief.start ?? now,
      end: brief.end ?? now,
      travellerSummary: brief.toPromptSummary(),
      hotel: hotel,
      hotelAlternatives: alternatives,
      transportOptions: transport?.options ?? const [],
      chosenTransport: chosenTransport,
      days: days.days,
      budget: budget,
      audit: audit,
      green: green,
      sources: sources.take(80).toList(),
      assumptions: assumptions.toSet().toList(),
      confidence: _confidence(hotel, days, budget, weather),
      brief: brief,
      // What editing the finished plan needs: every ranked place (not only the
      // ones on the days), the weather and the choices made so far.
      snapshot: PlanSnapshot(
        pool: _pool(spots, days),
        weather: weather,
        center: center,
        origin: origin,
        bannedOutdoor: bannedOutdoor,
        droppedIds: droppedIds,
      ),
    );
  }

  /// The pages behind a plan: the stay's listing and claims, and each visited
  /// place's sources. Used when a plan is edited and its sources change.
  static List<SourceRef> sourcesFor({HotelOption? hotel, Iterable<Hotspot> visited = const []}) {
    final sources = <SourceRef>[];
    void add(SourceRef s) {
      if (s.url.isEmpty || sources.any((x) => x.url == s.url)) return;
      sources.add(s);
    }

    if (hotel != null) {
      final url = hotel.tripAdvisorUrl ?? hotel.bookingUrl;
      if (url != null) add(SourceRef(title: hotel.name, url: url, source: hotel.provenance.source));
      for (final c in hotel.claims) {
        c.sources.forEach(add);
      }
    }
    for (final h in visited) {
      h.sources.forEach(add);
      for (final c in h.claims) {
        c.sources.forEach(add);
      }
    }
    return sources.take(80).toList();
  }

  /// How much of a plan rests on real data (see [_confidence]).
  static double confidenceOf(HotelOption? hotel, DayPlanResult days, Budget budget, Map<String, DayForecast> weather) =>
      _confidence(hotel, days, budget, weather);

  /// The places to remember: those on the days first, then the best of the rest.
  static List<Hotspot> _pool(HotspotSearchResult? spots, DayPlanResult days) {
    final out = <Hotspot>[];
    final seen = <String>{};
    for (final h in [...days.visited, ...?spots?.selected, ...?spots?.pool]) {
      if (seen.add(h.id)) out.add(h);
      if (out.length >= PlanSnapshot.maxPool) break;
    }
    return out;
  }

  /// How much of the plan rests on real data rather than estimates, 0..1.
  static double _confidence(HotelOption? hotel, DayPlanResult days, Budget budget, Map<String, DayForecast> weather) {
    final hotelScore = hotel == null ? 0.0 : (hotel.priceIsEstimated ? 0.4 : 1.0);
    final visited = days.visited;
    final spotScore = visited.isEmpty
        ? 0.0
        : visited.fold<double>(0, (s, h) => s + (h.provenance.isEstimated ? 0.25 : h.provenance.confidence)) / visited.length;
    final total = budget.totalInr;
    final real = budget.lines.where((l) => !l.isEstimated).fold<int>(0, (s, l) => s + l.amountInr);
    final budgetScore = total <= 0 ? 0.0 : (0.2 + 0.8 * real / total).clamp(0.2, 1.0);
    final weatherScore = weather.isEmpty ? 0.5 : (weather.values.any((f) => f.isForecast) ? 1.0 : 0.6);
    final c = 0.35 * hotelScore + 0.35 * spotScore + 0.15 * budgetScore + 0.15 * weatherScore;
    return double.parse(c.clamp(0.0, 1.0).toStringAsFixed(2));
  }
}
