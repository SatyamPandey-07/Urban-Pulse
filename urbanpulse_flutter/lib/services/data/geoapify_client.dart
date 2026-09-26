import 'package:http/http.dart' as http;

import 'data_cache.dart';
import 'http_util.dart';

/// A place from Geoapify Places (OpenStreetMap-backed), with the raw OSM tags
/// it was built from so accessibility details survive.
class GeoPlace {
  const GeoPlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.address,
    this.categories = const [],
    this.website,
    this.phone,
    this.openingHours,
    this.wheelchair,
    this.tags = const {},
    this.distanceM,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;
  final String? address;
  final List<String> categories;
  final String? website;
  final String? phone;
  final String? openingHours;

  /// OSM `wheelchair` value: yes | limited | no, when known.
  final String? wheelchair;

  /// Raw OpenStreetMap tags (`wheelchair`, `tactile_paving`, `hearing_impaired`…).
  final Map<String, String> tags;
  final double? distanceM;

  static GeoPlace? fromFeature(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final p = raw['properties'];
    if (p is! Map<String, dynamic>) return null;
    final name = (p['name'] as String?)?.trim();
    final lat = asDouble(p['lat']);
    final lon = asDouble(p['lon']);
    if (name == null || name.isEmpty || lat == null || lon == null) return null;

    final datasource = p['datasource'] as Map<String, dynamic>?;
    final rawTags = datasource?['raw'] as Map<String, dynamic>?;
    final tags = <String, String>{
      for (final e in (rawTags ?? const {}).entries)
        if (e.value != null) e.key: '${e.value}',
    };
    final facilities = p['facilities'] as Map<String, dynamic>?;
    var wheelchair = tags['wheelchair'];
    if (wheelchair == null && facilities?['wheelchair'] is bool) {
      wheelchair = (facilities!['wheelchair'] as bool) ? 'yes' : 'no';
    }
    final contact = p['contact'] as Map<String, dynamic>?;

    return GeoPlace(
      id: (p['place_id'] as String?) ?? '${p['lat']},${p['lon']}',
      name: name,
      lat: lat,
      lon: lon,
      address: p['formatted'] as String?,
      categories: [
        for (final c in (p['categories'] as List<dynamic>? ?? const []))
          if (c is String) c,
      ],
      website: (p['website'] as String?) ?? contact?['website'] as String? ?? tags['website'],
      phone: contact?['phone'] as String? ?? tags['phone'],
      openingHours: (p['opening_hours'] as String?) ?? tags['opening_hours'],
      wheelchair: wheelchair,
      tags: tags,
      distanceM: asDouble(p['distance']),
    );
  }
}

/// A geocoding candidate ("did you mean…?").
class GeoCandidate {
  const GeoCandidate({
    required this.label,
    required this.lat,
    required this.lon,
    this.city,
    this.state,
    this.country,
    this.type,
    this.confidence,
  });

  final String label;
  final double lat;
  final double lon;
  final String? city;
  final String? state;
  final String? country;
  final String? type;
  final double? confidence;
}

/// Geoapify Places + geocoding. Needs a free key (~3,000 credits/day; one
/// simple request is one credit, so results are cached). Every call returns
/// null on failure. Requires a "Powered by Geoapify" credit in the UI.
class GeoapifyClient {
  GeoapifyClient({required this.apiKey, http.Client? client, DataCache? cache})
    : _client = client ?? http.Client(),
      _cache = cache ?? MemoryCache();

  final String apiKey;
  final http.Client _client;
  final DataCache _cache;

  bool get isConfigured => apiKey.isNotEmpty;

  static const hotelCategories = 'accommodation.hotel,accommodation.guest_house,'
      'accommodation.hostel,accommodation.motel,accommodation.apartment,'
      'accommodation.chalet,accommodation.hut';
  static const attractionCategories = 'tourism.attraction,tourism.sights,'
      'entertainment.museum,entertainment.culture,leisure.park,natural,heritage';
  static const foodCategories = 'catering.restaurant,catering.cafe';

  /// Places of [categories] within [radiusM] of a point, nearest first.
  /// [wheelchairOnly] asks Geoapify for places it knows are wheelchair friendly.
  Future<List<GeoPlace>?> places({
    required String categories,
    required double lat,
    required double lon,
    int radiusM = 8000,
    int limit = 30,
    bool wheelchairOnly = false,
  }) async {
    if (!isConfigured) return null;
    final key = 'geoapify.places.$categories.${lat.toStringAsFixed(3)}.${lon.toStringAsFixed(3)}.$radiusM.$limit.$wheelchairOnly';
    final json = await _cache.rememberJson(key, () async {
      final o = await httpGet(
        _client,
        Uri.https('api.geoapify.com', '/v2/places', {
          'categories': categories,
          'filter': 'circle:$lon,$lat,$radiusM',
          'bias': 'proximity:$lon,$lat',
          'limit': '$limit',
          if (wheelchairOnly) 'conditions': 'wheelchair',
          'apiKey': apiKey,
        }),
      );
      final m = o.map;
      return m?['features'];
    });
    return parseFeatures(json);
  }

  static List<GeoPlace>? parseFeatures(Object? features) {
    if (features is! List) return null;
    return [
      for (final f in features)
        if (GeoPlace.fromFeature(f) case final p?) p,
    ];
  }

  /// Turns free text into place candidates, best first. Used to validate a
  /// destination and to offer "did you mean…?" for unknown ones.
  Future<List<GeoCandidate>?> geocode(String text, {int limit = 5}) async {
    if (!isConfigured || text.trim().isEmpty) return null;
    final json = await _cache.rememberJson(
      'geoapify.geocode.${text.trim().toLowerCase()}.$limit',
      () async {
        final o = await httpGet(
          _client,
          Uri.https('api.geoapify.com', '/v1/geocode/search', {
            'text': text.trim(),
            'limit': '$limit',
            'format': 'json',
            'apiKey': apiKey,
          }),
        );
        return o.map?['results'];
      },
      ttl: const Duration(days: 30),
    );
    return parseCandidates(json);
  }

  static List<GeoCandidate>? parseCandidates(Object? results) {
    if (results is! List) return null;
    final out = <GeoCandidate>[];
    for (final r in results) {
      if (r is! Map<String, dynamic>) continue;
      final lat = asDouble(r['lat']);
      final lon = asDouble(r['lon']);
      if (lat == null || lon == null) continue;
      final rank = r['rank'] as Map<String, dynamic>?;
      out.add(
        GeoCandidate(
          label: (r['formatted'] as String?) ?? (r['name'] as String? ?? ''),
          lat: lat,
          lon: lon,
          city: (r['city'] ?? r['town'] ?? r['village']) as String?,
          state: r['state'] as String?,
          country: r['country'] as String?,
          type: r['result_type'] as String?,
          confidence: asDouble(rank?['confidence']),
        ),
      );
    }
    return out;
  }
}
