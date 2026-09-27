import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/config.dart';
import '../domain/carbon_estimator.dart';
import '../models/live_city_data.dart';
import '../models/map_category.dart';
import '../models/map_route.dart';
import 'data/overpass_client.dart';
import 'routing_service.dart';
import 'tomtom_service.dart';

/// Everything the Live Map asks of the outside world, behind one interface so
/// the map can be driven in tests. Every method answers with what the services
/// returned, or with nothing: no result is ever made up.
abstract class LiveMapData {
  /// Places matching the words, nearest to [near] first.
  Future<List<LivePoiResult>> search(String query, LatLng near);

  /// Places of one kind around [near], nearest first.
  Future<List<LivePoiResult>> nearby(MapCategory category, LatLng near);

  /// Routes from [from] to [to], the best first; empty if none could be had.
  Future<List<MapRoute>> routes(LatLng from, LatLng to, NavMode mode);

  /// A name for a point on the map (a dropped pin), or null.
  Future<String?> describe(LatLng point);

  /// The URL template of live traffic tiles, or null when there is no key.
  String? get trafficTiles;
}

class ServiceLiveMapData implements LiveMapData {
  ServiceLiveMapData({RoutingService? routing, OverpassClient? overpass, http.Client? client})
    : _routing = routing ?? RoutingService(),
      _overpass = overpass ?? OverpassClient(),
      _client = client ?? http.Client();

  final RoutingService _routing;
  final OverpassClient _overpass;
  final http.Client _client;

  @override
  Future<List<LivePoiResult>> search(String query, LatLng near) => TomTomService.searchPlacesBounded(query, lat: near.latitude, lon: near.longitude, radiusKm: 60, limit: 8);

  @override
  Future<List<LivePoiResult>> nearby(MapCategory category, LatLng near) async {
    if (AppConfig.hasTomTomKey) {
      final tt = await TomTomService.searchNearbyPoi(category.query, near.latitude, near.longitude, radiusMeters: 6000, limit: 20);
      if (tt.isNotEmpty) return tt;
    }
    final osm = await _overpass.nearby(category.name, category.osmFilters, near.latitude, near.longitude, radiusM: 5000, limit: 30);
    if (osm == null) return const [];
    final out = [
      for (final p in osm)
        LivePoiResult(
          name: p.name,
          address: [p.tags['addr:street'], p.tags['addr:city']].whereType<String>().join(', '),
          distanceMeters: CarbonEstimator.haversineKm(near.latitude, near.longitude, p.lat, p.lon) * 1000,
          lat: p.lat,
          lon: p.lon,
          phone: p.phone,
          category: category.label,
        ),
    ]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return out.take(20).toList();
  }

  @override
  Future<List<MapRoute>> routes(LatLng from, LatLng to, NavMode mode) => _routing.routes(from, to, mode);

  @override
  Future<String?> describe(LatLng p) async {
    try {
      final marks = await Geocoding().placemarkFromCoordinates(p.latitude, p.longitude);
      if (marks.isNotEmpty) {
        final m = marks.first;
        final line = [m.name, m.subLocality, m.locality].where((s) => s != null && s.trim().isNotEmpty).map((s) => s!.trim()).toSet().join(', ');
        if (line.isNotEmpty) return line;
      }
    } catch (_) {}
    try {
      final res = await _client
          .get(Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${p.latitude}&lon=${p.longitude}&zoom=18'), headers: const {'User-Agent': 'UrbanPulseApp/1.0'})
          .timeout(const Duration(seconds: 6));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final j = jsonDecode(res.body);
        if (j is Map && j['display_name'] is String) {
          final parts = (j['display_name'] as String).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
          return parts.take(3).join(', ');
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  String? get trafficTiles => AppConfig.hasTomTomKey ? 'https://api.tomtom.com/traffic/map/4/tile/flow/relative0/{z}/{x}/{y}.png?key=${AppConfig.tomtomApiKey}' : null;
}
