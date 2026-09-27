import 'package:latlong2/latlong.dart';

import '../agents/atithi/hotel_finder.dart';
import '../agents/hariyali/carbon_engine.dart';
import '../agents/runtime/agent_toolkit.dart';
import '../core/formatting.dart';
import '../models/hospitality_stay.dart';
import '../models/itinerary/itinerary_parts.dart';
import '../models/trip_brief.dart';
import '../services/data/location_key_resolver.dart';
import '../state/accessibility_controller.dart';

/// What a search for stays found.
class LiveStaysResult {
  const LiveStaysResult({this.stays = const [], this.sources = const [], this.warnings = const [], this.considered = 0, this.error});

  final List<HospitalityStay> stays;
  final List<String> sources;
  final List<String> warnings;
  final int considered;

  /// Why nothing could be searched, in words for the traveller.
  final String? error;
}

/// The accessibility needs the traveller saved in Settings.
Set<AccessibilityNeed> needsFromSettings(AccessibilityController a) => {
  if (a.isWheelchairModeEnabled) AccessibilityNeed.wheelchair,
  if (a.isVisualAssistanceEnabled) AccessibilityNeed.visual,
  if (a.isHearingAssistanceEnabled) AccessibilityNeed.hearing,
  if (a.isServiceAnimalFriendlyOnly) AccessibilityNeed.serviceAnimal,
};

/// Finds real stays near a place with the app's own hotel finder (the same one
/// Yatri's planner uses), and shapes them for the Sustainable & Inclusive Stays
/// screen. Nothing is filled in: what the finder does not know is shown as not
/// reported.
class LiveStaysService {
  LiveStaysService(this.toolkit);

  final AgentToolkit toolkit;

  Future<LiveStaysResult> find({required String city, required LatLng center, required Set<AccessibilityNeed> needs, DateTime? checkIn, int nights = 1}) async {
    try {
      final start = checkIn ?? DateTime.now().add(const Duration(days: 1));
      final day = DateTime(start.year, start.month, start.day);
      final ts = toolkit.newPlan();
      final finder = HotelFinder(
        resolver: LocationKeyResolver(xotelo: toolkit.xotelo, geocode: (p) => toolkit.geocoder.lookup(p), llm: toolkit.llm, search: ts.search, cache: toolkit.cache),
        xotelo: toolkit.xotelo,
        overpass: toolkit.overpass,
        geoapify: toolkit.geoapify,
        tools: ts.registry,
        llm: toolkit.llm,
        estimator: toolkit.estimator,
        fetchPage: ts.fetch,
      );
      final r = await finder.find(
        HotelQuery(destination: city, center: center, checkIn: day, checkOut: day.add(Duration(days: nights)), needs: needs, preferEco: true, radiusKm: 12),
      );
      return LiveStaysResult(
        stays: [for (final h in r.options) toStay(h, city, needs)],
        sources: r.sources,
        warnings: r.warnings,
        considered: r.considered,
        error: r.options.isEmpty ? 'No stays were found near $city. Try a nearby city, or check your connection.' : null,
      );
    } catch (_) {
      return const LiveStaysResult(error: 'Could not search for stays right now. Check your connection and try again.');
    }
  }

  static const _notReported = 'Not reported';

  static HospitalityStay toStay(HotelOption h, String city, Set<AccessibilityNeed> needs) {
    // Access: what the finder confirmed for each of the traveller's needs.
    var score = 0.0;
    var counted = 0;
    final tags = <String>[];
    for (final n in needs) {
      final s = h.access[n];
      counted++;
      switch (s?.level) {
        case SupportLevel.yes:
          score += 100;
          tags.add('${n.label}: supported');
        case SupportLevel.partial:
          score += 60;
          tags.add('${n.label}: partly');
        case SupportLevel.no:
          tags.add('${n.label}: not supported');
        default:
          tags.add('${n.label}: not confirmed');
      }
    }
    const accessWords = ['wheelchair', 'step-free', 'ramp', 'lift', 'elevator', 'braille', 'tactile', 'accessible'];
    for (final a in [...h.amenities, ...h.labels]) {
      if (accessWords.any((w) => a.toLowerCase().contains(w)) && !tags.contains(a)) tags.add(a);
    }
    final rating = counted == 0 ? 0 : (score / counted).round();

    final all = [...h.amenities, ...h.labels].map((e) => e.toLowerCase()).toList();
    final energy = all.where((e) => e.contains('solar') || e.contains('renewable') || e.contains('wind')).toList();
    final waste = all.where((e) => e.contains('waste') || e.contains('plastic') || e.contains('compost') || e.contains('recycl')).toList();

    final kg = GreenEngine.stayKgPerNight(h);
    final eco = h.ecoScore;
    return HospitalityStay(
      id: h.id,
      name: h.name,
      category: h.type,
      location: [if (h.address != null && h.address!.trim().isNotEmpty) h.address!.trim() else city, if (h.distanceToCenterKm != null) '${h.distanceToCenterKm!.toStringAsFixed(1)} km from centre'].join(' · '),
      ecoScore: eco == null ? 0 : (eco * 5).round().clamp(1, 5),
      accessibilityRating: rating,
      energySource: energy.isEmpty ? _notReported : energy.take(2).join(', '),
      wastePolicy: waste.isEmpty ? _notReported : waste.take(2).join(', '),
      accessibilityTags: tags,
      carbonFootprintPerNight: '${fixed(kg)} kg CO2e / night (estimate)',
      pricePerNight: h.nightlyInr == null ? 'Price not available' : '${rupees(h.nightlyInr!)} / night${h.priceIsEstimated ? ' (estimate)' : ''}',
      contactPhone: '',
      bookingUrl: h.bookingUrl ?? h.tripAdvisorUrl,
      rating: h.rating,
      reviewCount: h.reviewCount,
    );
  }
}
