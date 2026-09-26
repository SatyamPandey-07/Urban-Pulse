import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Resolves a place name to coordinates with Open-Meteo's free geocoding API
/// (no key), for the route preview on the Yatri map. Results are cached, and
/// every failure is just `null`: the map is a nicety, never a blocker.
class PlaceGeocoder {
  PlaceGeocoder({http.Client? client}) : _client = client ?? http.Client();

  static const timeout = Duration(seconds: 6);

  final http.Client _client;
  final Map<String, LatLng?> _cache = {};

  Future<LatLng?> lookup(String name) async {
    final key = name.trim().toLowerCase();
    if (key.isEmpty) return null;
    if (_cache.containsKey(key)) return _cache[key];

    LatLng? point;
    try {
      final response = await _client
          .get(
            Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
              'name': name.trim(),
              'count': '1',
              'language': 'en',
              'format': 'json',
            }),
          )
          .timeout(timeout);
      if (response.statusCode == 200) {
        point = parse(response.body);
      }
    } catch (_) {
      point = null;
    }
    // Only successful lookups are cached, so a network blip can be retried.
    if (point != null) _cache[key] = point;
    return point;
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
}
