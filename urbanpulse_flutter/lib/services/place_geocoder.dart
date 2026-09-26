import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A place on the map: its centre, and how far it spreads when it is a region
/// (a state or district such as Goa or Kodagu) rather than a town.
class GeoArea {
  const GeoArea(this.center, {this.spanKm, this.isRegion = false});

  final LatLng center;

  /// Half the diagonal of the region's bounding box, when known.
  final double? spanKm;
  final bool isRegion;
}

/// Resolves a place name to coordinates, free and without keys. The planner is
/// India-first, so an Indian match is preferred ("Delhi" is not the one in
/// Ontario, "Goa" is not Genoa):
///
///  1. Open-Meteo restricted to India, accepted only for a real town or city
///     (it lists villages too, and has no states: "Goa" there is a hamlet);
///  2. OpenStreetMap Nominatim, which knows states and regions and their extent;
///  3. Open-Meteo worldwide, for trips abroad.
///
/// Slow answers are retried once. Results are cached, and every failure is just
/// `null`.
class PlaceGeocoder {
  PlaceGeocoder({http.Client? client}) : _client = client ?? http.Client();

  static const timeout = Duration(seconds: 10);
  static const _userAgent = 'UrbanPulseApp/1.0 (trip planner)';

  final http.Client _client;
  final Map<String, GeoArea> _cache = {};

  Future<LatLng?> lookup(String name) async => (await lookupArea(name))?.center;

  Future<GeoArea?> lookupArea(String name) async {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    final hit = _cache[key];
    if (hit != null) return hit;

    final area = await _openMeteo(name.trim(), india: true, significantOnly: true) ??
        await _nominatim(name.trim()) ??
        await _openMeteo(name.trim(), india: false, significantOnly: false);
    // Only successful lookups are cached, so a network blip can be retried.
    if (area != null) _cache[key] = area;
    return area;
  }

  Future<GeoArea?> _openMeteo(String name, {required bool india, required bool significantOnly}) async {
    final body = await _get(
      Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': name,
        'count': '10',
        'language': 'en',
        'format': 'json',
        if (india) 'countryCode': 'IN',
      }),
    );
    if (body == null) return null;
    final p = significantOnly ? parseSignificant(body, name) : parse(body);
    return p == null ? null : GeoArea(p);
  }

  Future<GeoArea?> _nominatim(String name) async {
    for (final q in [if (!name.toLowerCase().contains('india')) '$name, India', name]) {
      final body = await _get(
        Uri.https('nominatim.openstreetmap.org', '/search', {'q': q, 'format': 'json', 'limit': '1'}),
        headers: const {'User-Agent': _userAgent},
      );
      final a = body == null ? null : parseNominatim(body);
      if (a != null) return a;
    }
    return null;
  }

  Future<String?> _get(Uri uri, {Map<String, String> headers = const {}}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final r = await _client.get(uri, headers: headers).timeout(timeout);
        if (r.statusCode == 200) return r.body;
        if (r.statusCode < 500 && r.statusCode != 429) return null;
      } catch (_) {
        // slow or dropped: one more try
      }
    }
    return null;
  }

  /// The first result's coordinates, or null. Public for tests.
  static LatLng? parse(String body) {
    try {
      final decoded = jsonDecode(body);
      final results = decoded is Map<String, dynamic> ? decoded['results'] : null;
      if (results is! List || results.isEmpty) return null;
      final first = results.first as Map<String, dynamic>;
      final lat = (first['latitude'] as num?)?.toDouble();
      final lng = (first['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  /// The best Open-Meteo result that is a real town or city named [name]: an
  /// administrative seat or a population of at least 20,000. Null when there is
  /// none, so a hamlet that shares a famous name is never taken. Public for tests.
  static LatLng? parseSignificant(String body, String name) {
    try {
      final decoded = jsonDecode(body);
      final results = decoded is Map<String, dynamic> ? decoded['results'] : null;
      if (results is! List) return null;
      final want = _norm(name.split(',').first);
      Map<String, dynamic>? best;
      var bestPop = -1;
      for (final r in results.whereType<Map<String, dynamic>>()) {
        if (_norm(r['name'] as String? ?? '') != want) continue;
        final code = r['feature_code'] as String? ?? '';
        final pop = (r['population'] as num?)?.toInt() ?? 0;
        final seat = code == 'PPLC' || code == 'PPLA' || code == 'PPLA2';
        if (!seat && pop < 20000) continue;
        final rank = pop + (seat ? 1000000 : 0);
        if (rank > bestPop) {
          bestPop = rank;
          best = r;
        }
      }
      final lat = (best?['latitude'] as num?)?.toDouble();
      final lng = (best?['longitude'] as num?)?.toDouble();
      return lat == null || lng == null ? null : LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  /// Nominatim's first result, with the region's spread when it is a state,
  /// district or similar. Public for tests.
  static GeoArea? parseNominatim(String body) {
    try {
      final list = jsonDecode(body);
      if (list is! List || list.isEmpty) return null;
      final m = list.first as Map<String, dynamic>;
      final lat = double.tryParse('${m['lat']}');
      final lon = double.tryParse('${m['lon']}');
      if (lat == null || lon == null) return null;
      final type = '${m['addresstype'] ?? m['type'] ?? ''}';
      final region = const {'state', 'region', 'province', 'state_district', 'district', 'county', 'territory'}.contains(type);
      double? span;
      final bb = m['boundingbox'];
      if (bb is List && bb.length == 4) {
        final s = double.tryParse('${bb[0]}');
        final n = double.tryParse('${bb[1]}');
        final w = double.tryParse('${bb[2]}');
        final e = double.tryParse('${bb[3]}');
        if (s != null && n != null && w != null && e != null) {
          final dy = (n - s) * 111.0;
          final dx = (e - w) * 111.0 * math.cos(lat * math.pi / 180).abs();
          span = math.sqrt(dx * dx + dy * dy) / 2;
        }
      }
      return GeoArea(LatLng(lat, lon), spanKm: span, isRegion: region);
    } catch (_) {
      return null;
    }
  }

  static String _norm(String s) => s.trim().toLowerCase();
}
