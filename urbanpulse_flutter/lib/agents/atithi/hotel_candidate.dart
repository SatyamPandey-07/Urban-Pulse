import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../domain/access/access_rules.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../services/data/http_util.dart';
import '../runtime/report.dart';

/// A hotel while it is being assembled from several sources. Mutable on
/// purpose: each source adds what it knows, then [HotelCandidates.merge] folds
/// duplicates together.
class HotelCandidate {
  HotelCandidate({
    required this.name,
    required this.source,
    this.location,
    this.address,
    this.type = 'Hotel',
    this.rating,
    this.reviewCount,
    this.nightlyInr,
    this.priceIsEstimated = true,
    this.xoteloKey,
    this.tripAdvisorUrl,
    this.imageUrl,
    this.website,
    this.phone,
    this.stars,
    this.osmId,
    this.geoapifyId,
    Map<String, String>? tags,
    List<String>? labels,
    List<String>? amenities,
    List<String>? claims,
    List<Provenance>? sources,
  }) : tags = tags ?? {},
       labels = labels ?? [],
       amenities = amenities ?? [],
       claims = claims ?? [],
       sources = sources ?? [Provenance(source: source)];

  String name;

  /// The source that created this candidate.
  final String source;
  LatLng? location;
  String? address;
  String type;
  double? rating;
  int? reviewCount;

  /// Nightly price for one room, in rupees.
  int? nightlyInr;
  bool priceIsEstimated;
  String? xoteloKey;
  String? tripAdvisorUrl;
  String? imageUrl;
  String? website;
  String? phone;
  int? stars;
  String? osmId;
  String? geoapifyId;

  /// Raw OpenStreetMap tags, for accessibility rules.
  final Map<String, String> tags;
  final List<String> labels;
  final List<String> amenities;

  /// Things a listing or page says about the hotel ("step-free entrance").
  final List<String> claims;
  final List<Provenance> sources;

  /// Per-need evidence gathered so far.
  final Map<AccessibilityNeed, NeedSupport> access = {};

  /// Set from live OTA rates.
  int? totalStayInr;
  String? cheapestOta;
  String? bookingUrl;

  String get id {
    if (xoteloKey != null) return xoteloKey!;
    if (geoapifyId != null) return 'geo:$geoapifyId';
    if (osmId != null) return 'osm:$osmId';
    return 'web:${HotelCandidates.normalize(name)}';
  }

  bool get hasLocation => location != null;

  /// Folds [other] (the same hotel from another source) into this one,
  /// keeping the best value of each field.
  void absorb(HotelCandidate other) {
    // Prefer Xotelo for name, rating, price and links; OSM/Geoapify for position.
    if (xoteloKey == null && other.xoteloKey != null) {
      xoteloKey = other.xoteloKey;
      name = other.name;
    }
    location ??= other.location;
    if (other.location != null && other.source != 'web search' && (location == null || source == 'web search')) {
      location = other.location;
    }
    address ??= other.address;
    if (type == 'Hotel' && other.type != 'Hotel') type = other.type;
    rating ??= other.rating;
    reviewCount ??= other.reviewCount;
    if (nightlyInr == null || (priceIsEstimated && !other.priceIsEstimated)) {
      if (other.nightlyInr != null) {
        nightlyInr = other.nightlyInr;
        priceIsEstimated = other.priceIsEstimated;
      }
    }
    tripAdvisorUrl ??= other.tripAdvisorUrl;
    imageUrl ??= other.imageUrl;
    website ??= other.website;
    phone ??= other.phone;
    stars ??= other.stars;
    osmId ??= other.osmId;
    geoapifyId ??= other.geoapifyId;
    tags.addAll({for (final e in other.tags.entries) if (!tags.containsKey(e.key)) e.key: e.value});
    for (final l in other.labels) {
      if (!labels.contains(l)) labels.add(l);
    }
    for (final a in other.amenities) {
      if (!amenities.contains(a)) amenities.add(a);
    }
    for (final c in other.claims) {
      if (!claims.contains(c)) claims.add(c);
    }
    for (final p in other.sources) {
      if (!sources.any((s) => s.source == p.source && s.url == p.url)) sources.add(p);
    }
    for (final e in other.access.entries) {
      final prev = access[e.key];
      access[e.key] = prev == null ? e.value : AccessRules.merge(prev, e.value);
    }
  }
}

abstract final class HotelCandidates {
  static const _stop = {
    'hotel', 'hotels', 'resort', 'resorts', 'the', 'inn', 'guest', 'house', 'guesthouse', 'homestay', 'hostel',
    'lodge', 'stay', 'stays', 'residency', 'and', 'by', 'at', 'in', 'of', 'a', 'an', 'suites', 'suite', 'villa',
  };

  /// Lower-case alphanumerics only.
  static String normalize(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim().replaceAll(' ', '-');

  static Set<String> _tokens(String name) => {
    for (final t in name.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
      if (t.length > 1 && !_stop.contains(t)) t,
  };

  /// Overlap of the distinctive words in two names, 0..1.
  static double similarity(String a, String b) {
    final ta = _tokens(a);
    final tb = _tokens(b);
    if (ta.isEmpty || tb.isEmpty) return normalize(a) == normalize(b) ? 1 : 0;
    final inter = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    return inter / union;
  }

  /// Whether two records describe the same property: very similar names, or a
  /// close name within a few hundred metres.
  static bool sameHotel(HotelCandidate a, HotelCandidate b) {
    if (a.xoteloKey != null && a.xoteloKey == b.xoteloKey) return true;
    if (normalize(a.name) == normalize(b.name)) return true;
    final sim = similarity(a.name, b.name);
    if (a.location != null && b.location != null) {
      final km = haversineKm(a.location!.latitude, a.location!.longitude, b.location!.latitude, b.location!.longitude);
      if (km <= 0.25 && sim >= 0.5) return true;
      if (km <= 3 && sim >= 0.8) return true;
      return false;
    }
    return sim >= 0.8;
  }

  /// Folds duplicates across sources into one candidate each. The first
  /// occurrence keeps its place, so pass the most trusted source first.
  static List<HotelCandidate> merge(Iterable<HotelCandidate> all) {
    final out = <HotelCandidate>[];
    for (final c in all) {
      final match = out.where((o) => sameHotel(o, c)).firstOrNull;
      if (match == null) {
        out.add(c);
      } else {
        match.absorb(c);
      }
    }
    return out;
  }

  /// How well a candidate fits, 0..1, from what is known so far. Access
  /// dominates when the group has needs; unknowns count for less than yeses but
  /// more than nos, so a verified-good hotel outranks an unverified one.
  static double fit(
    HotelCandidate c, {
    required Set<AccessibilityNeed> needs,
    int? nightlyCapInr,
    LatLng? center,
    bool preferEco = false,
  }) {
    final wanted = AccessRules.relevant(needs);

    double accessScore() {
      if (wanted.isEmpty) return 1;
      var sum = 0.0;
      for (final n in wanted) {
        sum += switch (c.access[n]?.level) {
          SupportLevel.yes => 1.0,
          SupportLevel.partial => 0.6,
          SupportLevel.unknown || null => 0.25,
          SupportLevel.no => 0.0,
        };
      }
      return sum / wanted.length;
    }

    double priceScore() {
      final p = c.nightlyInr;
      if (p == null) return 0.4;
      if (nightlyCapInr == null) return 0.7;
      if (p <= nightlyCapInr) return 1.0 - 0.3 * (p / nightlyCapInr);
      final over = (p - nightlyCapInr) / nightlyCapInr;
      return over <= 0.2 ? 0.45 : 0.1;
    }

    double ratingScore() {
      final r = c.rating;
      if (r == null) return 0.4;
      final base = ((r - 3) / 2).clamp(0.0, 1.0);
      final n = c.reviewCount ?? 0;
      // Few reviews: trust the rating less.
      final trust = n <= 0 ? 0.5 : (math.log(n + 1) / math.log(200)).clamp(0.5, 1.0);
      return base * trust + 0.3 * (1 - trust);
    }

    double distanceScore() {
      if (center == null || c.location == null) return 0.4;
      final km = haversineKm(center.latitude, center.longitude, c.location!.latitude, c.location!.longitude);
      return (1 - km / 15).clamp(0.0, 1.0);
    }

    final eco = preferEco ? (_ecoSignal(c) ?? 0.3) : 0.5;
    final hasNeeds = wanted.isNotEmpty;
    final wa = hasNeeds ? 0.36 : 0.0;
    final wp = hasNeeds ? 0.24 : 0.32;
    final wr = hasNeeds ? 0.18 : 0.32;
    final wd = hasNeeds ? 0.12 : 0.22;
    final we = preferEco ? 0.10 : 0.14;
    final total = wa + wp + wr + wd + we;
    return (accessScore() * wa + priceScore() * wp + ratingScore() * wr + distanceScore() * wd + eco * we) / total;
  }

  /// 0..1 from green words in the labels, amenities or claims, or null.
  static double? _ecoSignal(HotelCandidate c) {
    final text = [...c.labels, ...c.amenities, ...c.claims, c.name].join(' ').toLowerCase();
    var hits = 0;
    for (final w in const ['eco', 'green', 'solar', 'sustainab', 'organic', 'rainwater', 'plastic-free', 'zero waste', 'carbon']) {
      if (text.contains(w)) hits++;
    }
    return hits == 0 ? null : (0.5 + 0.15 * hits).clamp(0.0, 1.0);
  }

  static double? ecoScore(HotelCandidate c) => _ecoSignal(c);

  /// Known amenities found in free text, in a stable order.
  static List<String> amenitiesIn(String text) {
    final t = text.toLowerCase();
    const known = <String, String>{
      'free wifi': 'Free Wi-Fi',
      'wi-fi': 'Wi-Fi',
      'wifi': 'Wi-Fi',
      'free internet': 'Internet',
      'free parking': 'Free parking',
      'parking': 'Parking',
      'swimming pool': 'Pool',
      'pool': 'Pool',
      'breakfast': 'Breakfast',
      'restaurant': 'Restaurant',
      'bar/lounge': 'Bar',
      'fitness': 'Fitness centre',
      'gym': 'Gym',
      'spa': 'Spa',
      'airport transportation': 'Airport transfer',
      'shuttle': 'Shuttle',
      'air conditioning': 'Air conditioning',
      'room service': 'Room service',
      'laundry': 'Laundry',
      'elevator': 'Elevator',
      'lift': 'Lift',
      '24-hour front desk': '24-hour front desk',
      'pet friendly': 'Pet friendly',
      'family rooms': 'Family rooms',
    };
    final out = <String>[];
    for (final e in known.entries) {
      if (t.contains(e.key) && !out.contains(e.value)) out.add(e.value);
    }
    return out;
  }
}
