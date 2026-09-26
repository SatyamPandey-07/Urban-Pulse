import 'package:latlong2/latlong.dart';

import '../../agents/runtime/report.dart';
import '../trip_brief.dart';

// The building blocks of an itinerary: places, claims, legs and accessibility
// support. Everything that can come from a language model carries a
// [Provenance] so the UI can label it "AI-estimated".

List<double>? latLngToJson(LatLng? p) => p == null ? null : [p.latitude, p.longitude];

LatLng? latLngFromJson(Object? j) {
  if (j is List && j.length == 2 && j[0] is num && j[1] is num) {
    return LatLng((j[0] as num).toDouble(), (j[1] as num).toDouble());
  }
  return null;
}

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// A page a fact came from.
class SourceRef {
  const SourceRef({required this.title, required this.url, this.snippet, this.source = ''});

  final String title;
  final String url;
  final String? snippet;

  /// "Tavily", "TripAdvisor", "Reddit"…
  final String source;

  Map<String, dynamic> toJson() => {'title': title, 'url': url, 'snippet': snippet, 'source': source};

  static SourceRef fromJson(Map<String, dynamic> j) => SourceRef(
    title: j['title'] as String? ?? (j['url'] as String? ?? ''),
    url: j['url'] as String? ?? '',
    snippet: j['snippet'] as String?,
    source: j['source'] as String? ?? '',
  );
}

/// How well a claim survived checking.
enum Verdict { unverified, confirmed, mixed, contradicted }

/// Something a listing says that matters ("step-free entrance"), and what
/// Khoji found when it looked.
class Claim {
  const Claim({
    required this.text,
    this.verdict = Verdict.unverified,
    this.sources = const [],
    this.reviewQuotes = const [],
    this.confidence = 0.5,
  });

  /// The claim that holds a hotel's or place's guest reviews.
  static const reviewsLabel = 'What guests say';

  final String text;
  final Verdict verdict;
  final List<SourceRef> sources;

  /// Short quotes from reviews (Khoji prefers the lower-rated ones).
  final List<String> reviewQuotes;
  final double confidence;

  /// Whether this is the reviews entry rather than a factual claim.
  bool get isReviews => text == reviewsLabel;

  Claim copyWith({Verdict? verdict, List<SourceRef>? sources, List<String>? reviewQuotes, double? confidence}) =>
      Claim(
        text: text,
        verdict: verdict ?? this.verdict,
        sources: sources ?? this.sources,
        reviewQuotes: reviewQuotes ?? this.reviewQuotes,
        confidence: confidence ?? this.confidence,
      );

  Map<String, dynamic> toJson() => {
    'text': text,
    'verdict': verdict.name,
    'sources': [for (final s in sources) s.toJson()],
    'reviewQuotes': reviewQuotes,
    'confidence': confidence,
  };

  static Claim fromJson(Map<String, dynamic> j) => Claim(
    text: j['text'] as String? ?? '',
    verdict: enumByName(Verdict.values, j['verdict'], Verdict.unverified),
    sources: [
      for (final s in (j['sources'] as List<dynamic>? ?? const []))
        if (s is Map<String, dynamic>) SourceRef.fromJson(s),
    ],
    reviewQuotes: [for (final q in (j['reviewQuotes'] as List<dynamic>? ?? const [])) '$q'],
    confidence: (j['confidence'] as num?)?.toDouble() ?? 0.5,
  );
}

enum SupportLevel {
  yes,
  partial,
  no,
  unknown;

  /// A single glyph-free label for the UI.
  String get label => switch (this) {
    yes => 'Supported',
    partial => 'Partly',
    no => 'Not supported',
    unknown => 'Unconfirmed',
  };
}

/// Whether a place works for one access need, and on what evidence.
class NeedSupport {
  const NeedSupport({
    required this.need,
    required this.level,
    this.detail = '',
    this.provenance = const Provenance(source: 'unknown', confidence: 0),
  });

  final AccessibilityNeed need;
  final SupportLevel level;
  final String detail;
  final Provenance provenance;

  Map<String, dynamic> toJson() => {
    'need': need.name,
    'level': level.name,
    'detail': detail,
    'provenance': provenance.toJson(),
  };

  static NeedSupport fromJson(Map<String, dynamic> j) => NeedSupport(
    need: enumByName(AccessibilityNeed.values, j['need'], AccessibilityNeed.none),
    level: enumByName(SupportLevel.values, j['level'], SupportLevel.unknown),
    detail: j['detail'] as String? ?? '',
    provenance: j['provenance'] is Map<String, dynamic>
        ? Provenance.fromJson(j['provenance'] as Map<String, dynamic>)
        : const Provenance(source: 'unknown', confidence: 0),
  );
}

Map<String, dynamic> _accessToJson(Map<AccessibilityNeed, NeedSupport> m) => {
  for (final e in m.entries) e.key.name: e.value.toJson(),
};

Map<AccessibilityNeed, NeedSupport> _accessFromJson(Object? j) {
  final out = <AccessibilityNeed, NeedSupport>{};
  if (j is Map<String, dynamic>) {
    for (final e in j.entries) {
      if (e.value is Map<String, dynamic>) {
        final s = NeedSupport.fromJson(e.value as Map<String, dynamic>);
        out[s.need] = s;
      }
    }
  }
  return out;
}

/// One place to stay.
class HotelOption {
  const HotelOption({
    required this.id,
    required this.name,
    this.location,
    this.address,
    this.type = 'Hotel',
    this.rating,
    this.reviewCount,
    this.nightlyInr,
    this.totalStayInr,
    this.priceIsEstimated = true,
    this.cheapestOta,
    this.bookingUrl,
    this.tripAdvisorUrl,
    this.imageUrl,
    this.access = const {},
    this.amenities = const [],
    this.claims = const [],
    this.distanceToCenterKm,
    this.ecoScore,
    this.labels = const [],
    this.priceBand,
    this.provenance = const Provenance(source: 'unknown'),
  });

  final String id;
  final String name;
  final LatLng? location;
  final String? address;
  final String type;
  final double? rating;
  final int? reviewCount;

  /// Best available nightly price in rupees.
  final int? nightlyInr;

  /// Total for the whole stay when a live rate was found.
  final int? totalStayInr;

  /// True when the price is derived (list range converted from USD, or a model
  /// estimate) rather than a live OTA total.
  final bool priceIsEstimated;
  final String? cheapestOta;
  final String? bookingUrl;
  final String? tripAdvisorUrl;
  final String? imageUrl;

  /// Per access need: does this hotel work, and how do we know.
  final Map<AccessibilityNeed, NeedSupport> access;
  final List<String> amenities;
  final List<Claim> claims;
  final double? distanceToCenterKm;

  /// 0..1 from eco signals (certifications, practices), when known.
  final double? ecoScore;
  final List<String> labels;

  /// "cheap" | "average" | "high" for the chosen dates, from Xotelo's heatmap.
  final String? priceBand;
  final Provenance provenance;

  HotelOption copyWith({
    LatLng? location,
    int? nightlyInr,
    int? totalStayInr,
    bool? priceIsEstimated,
    String? cheapestOta,
    String? bookingUrl,
    Map<AccessibilityNeed, NeedSupport>? access,
    List<String>? amenities,
    List<Claim>? claims,
    double? distanceToCenterKm,
    double? ecoScore,
    String? priceBand,
    Provenance? provenance,
  }) => HotelOption(
    id: id,
    name: name,
    location: location ?? this.location,
    address: address,
    type: type,
    rating: rating,
    reviewCount: reviewCount,
    nightlyInr: nightlyInr ?? this.nightlyInr,
    totalStayInr: totalStayInr ?? this.totalStayInr,
    priceIsEstimated: priceIsEstimated ?? this.priceIsEstimated,
    cheapestOta: cheapestOta ?? this.cheapestOta,
    bookingUrl: bookingUrl ?? this.bookingUrl,
    tripAdvisorUrl: tripAdvisorUrl,
    imageUrl: imageUrl,
    access: access ?? this.access,
    amenities: amenities ?? this.amenities,
    claims: claims ?? this.claims,
    distanceToCenterKm: distanceToCenterKm ?? this.distanceToCenterKm,
    ecoScore: ecoScore ?? this.ecoScore,
    labels: labels,
    priceBand: priceBand ?? this.priceBand,
    provenance: provenance ?? this.provenance,
  );

  /// True when every need in [needs] is at least partly supported.
  bool meets(Iterable<AccessibilityNeed> needs) => needs.every((n) {
    if (n == AccessibilityNeed.none) return true;
    final s = access[n]?.level;
    return s == SupportLevel.yes || s == SupportLevel.partial;
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'location': latLngToJson(location),
    'address': address,
    'type': type,
    'rating': rating,
    'reviewCount': reviewCount,
    'nightlyInr': nightlyInr,
    'totalStayInr': totalStayInr,
    'priceIsEstimated': priceIsEstimated,
    'cheapestOta': cheapestOta,
    'bookingUrl': bookingUrl,
    'tripAdvisorUrl': tripAdvisorUrl,
    'imageUrl': imageUrl,
    'access': _accessToJson(access),
    'amenities': amenities,
    'claims': [for (final c in claims) c.toJson()],
    'distanceToCenterKm': distanceToCenterKm,
    'ecoScore': ecoScore,
    'labels': labels,
    'priceBand': priceBand,
    'provenance': provenance.toJson(),
  };

  static HotelOption fromJson(Map<String, dynamic> j) => HotelOption(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? 'Hotel',
    location: latLngFromJson(j['location']),
    address: j['address'] as String?,
    type: j['type'] as String? ?? 'Hotel',
    rating: (j['rating'] as num?)?.toDouble(),
    reviewCount: (j['reviewCount'] as num?)?.toInt(),
    nightlyInr: (j['nightlyInr'] as num?)?.toInt(),
    totalStayInr: (j['totalStayInr'] as num?)?.toInt(),
    priceIsEstimated: j['priceIsEstimated'] as bool? ?? true,
    cheapestOta: j['cheapestOta'] as String?,
    bookingUrl: j['bookingUrl'] as String?,
    tripAdvisorUrl: j['tripAdvisorUrl'] as String?,
    imageUrl: j['imageUrl'] as String?,
    access: _accessFromJson(j['access']),
    amenities: [for (final a in (j['amenities'] as List<dynamic>? ?? const [])) '$a'],
    claims: [
      for (final c in (j['claims'] as List<dynamic>? ?? const []))
        if (c is Map<String, dynamic>) Claim.fromJson(c),
    ],
    distanceToCenterKm: (j['distanceToCenterKm'] as num?)?.toDouble(),
    ecoScore: (j['ecoScore'] as num?)?.toDouble(),
    labels: [for (final l in (j['labels'] as List<dynamic>? ?? const [])) '$l'],
    priceBand: j['priceBand'] as String?,
    provenance: j['provenance'] is Map<String, dynamic>
        ? Provenance.fromJson(j['provenance'] as Map<String, dynamic>)
        : const Provenance(source: 'unknown'),
  );
}

enum HotspotKind {
  heritage,
  nature,
  culture,
  religious,
  food,
  adventure,
  viewpoint,
  shopping,
  trending,
  other,
}

/// A place worth visiting.
class Hotspot {
  const Hotspot({
    required this.id,
    required this.name,
    required this.location,
    this.kind = HotspotKind.other,
    this.why = '',
    this.visitMinutes = 90,
    this.feeInr,
    this.openingHours,
    this.isOutdoor = true,
    this.isTrending = false,
    this.score = 0.5,
    this.access = const {},
    this.claims = const [],
    this.sources = const [],
    this.provenance = const Provenance(source: 'unknown'),
  });

  final String id;
  final String name;
  final LatLng location;
  final HotspotKind kind;

  /// One sentence on why it is worth going.
  final String why;
  final int visitMinutes;
  final int? feeInr;

  /// OSM-style opening hours text (`Mo-Su 09:00-17:00`), parsed by Raah.
  final String? openingHours;
  final bool isOutdoor;

  /// Newly opened or currently buzzing, as opposed to a long-standing sight.
  final bool isTrending;

  /// 0..1 importance for the trip.
  final double score;
  final Map<AccessibilityNeed, NeedSupport> access;
  final List<Claim> claims;
  final List<SourceRef> sources;
  final Provenance provenance;

  Hotspot copyWith({
    Map<AccessibilityNeed, NeedSupport>? access,
    List<Claim>? claims,
    List<SourceRef>? sources,
    double? score,
    int? feeInr,
    String? openingHours,
  }) => Hotspot(
    id: id,
    name: name,
    location: location,
    kind: kind,
    why: why,
    visitMinutes: visitMinutes,
    feeInr: feeInr ?? this.feeInr,
    openingHours: openingHours ?? this.openingHours,
    isOutdoor: isOutdoor,
    isTrending: isTrending,
    score: score ?? this.score,
    access: access ?? this.access,
    claims: claims ?? this.claims,
    sources: sources ?? this.sources,
    provenance: provenance,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'location': latLngToJson(location),
    'kind': kind.name,
    'why': why,
    'visitMinutes': visitMinutes,
    'feeInr': feeInr,
    'openingHours': openingHours,
    'isOutdoor': isOutdoor,
    'isTrending': isTrending,
    'score': score,
    'access': _accessToJson(access),
    'claims': [for (final c in claims) c.toJson()],
    'sources': [for (final s in sources) s.toJson()],
    'provenance': provenance.toJson(),
  };

  static Hotspot fromJson(Map<String, dynamic> j) => Hotspot(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? 'Place',
    location: latLngFromJson(j['location']) ?? const LatLng(0, 0),
    kind: enumByName(HotspotKind.values, j['kind'], HotspotKind.other),
    why: j['why'] as String? ?? '',
    visitMinutes: (j['visitMinutes'] as num?)?.toInt() ?? 90,
    feeInr: (j['feeInr'] as num?)?.toInt(),
    openingHours: j['openingHours'] as String?,
    isOutdoor: j['isOutdoor'] as bool? ?? true,
    isTrending: j['isTrending'] as bool? ?? false,
    score: (j['score'] as num?)?.toDouble() ?? 0.5,
    access: _accessFromJson(j['access']),
    claims: [
      for (final c in (j['claims'] as List<dynamic>? ?? const []))
        if (c is Map<String, dynamic>) Claim.fromJson(c),
    ],
    sources: [
      for (final s in (j['sources'] as List<dynamic>? ?? const []))
        if (s is Map<String, dynamic>) SourceRef.fromJson(s),
    ],
    provenance: j['provenance'] is Map<String, dynamic>
        ? Provenance.fromJson(j['provenance'] as Map<String, dynamic>)
        : const Provenance(source: 'unknown'),
  );
}

/// One journey leg: to the destination, or between two places in it.
class TransportLeg {
  const TransportLeg({
    required this.id,
    required this.from,
    required this.to,
    required this.mode,
    required this.distanceKm,
    required this.durationMin,
    required this.costInr,
    this.co2Grams = 0,
    this.stepFree = false,
    this.note,
    this.isEstimated = true,
    this.fromPoint,
    this.toPoint,
    this.walking = false,
  });

  final String id;
  final String from;
  final String to;
  final TripTransportMode mode;
  final double distanceKm;
  final int durationMin;

  /// Total for the whole group.
  final int costInr;
  final int co2Grams;

  /// Whether a wheelchair user can board and alight without steps.
  final bool stepFree;
  final String? note;
  final bool isEstimated;
  final LatLng? fromPoint;
  final LatLng? toPoint;

  /// A short walk. [mode] is a placeholder then and must not be shown.
  final bool walking;

  /// What to call this leg: "Walk", "Train", …
  String get modeLabel => walking ? 'Walk' : mode.label;

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': from,
    'to': to,
    'mode': mode.name,
    'distanceKm': distanceKm,
    'durationMin': durationMin,
    'costInr': costInr,
    'co2Grams': co2Grams,
    'stepFree': stepFree,
    'note': note,
    'isEstimated': isEstimated,
    'fromPoint': latLngToJson(fromPoint),
    'toPoint': latLngToJson(toPoint),
    'walking': walking,
  };

  static TransportLeg fromJson(Map<String, dynamic> j) => TransportLeg(
    id: j['id'] as String? ?? '',
    from: j['from'] as String? ?? '',
    to: j['to'] as String? ?? '',
    mode: enumByName(TripTransportMode.values, j['mode'], TripTransportMode.carTaxi),
    distanceKm: (j['distanceKm'] as num?)?.toDouble() ?? 0,
    durationMin: (j['durationMin'] as num?)?.toInt() ?? 0,
    costInr: (j['costInr'] as num?)?.toInt() ?? 0,
    co2Grams: (j['co2Grams'] as num?)?.toInt() ?? 0,
    stepFree: j['stepFree'] as bool? ?? false,
    note: j['note'] as String?,
    isEstimated: j['isEstimated'] as bool? ?? true,
    fromPoint: latLngFromJson(j['fromPoint']),
    toPoint: latLngFromJson(j['toPoint']),
    walking: j['walking'] as bool? ?? false,
  );
}
