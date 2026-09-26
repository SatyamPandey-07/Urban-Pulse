import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../domain/carbon_estimator.dart';
import '../models/live_city_data.dart';

/// Real TomTom REST calls: POI search, traffic flow and route calculation.
///
/// Consolidates `LiveCityIntelligenceService.searchNearbyPoi` /
/// `getLiveTraffic`, the two inline `calculateRoute` fetches in
/// `LiveMapFragment`, and `CarbonEstimator.fetchRealRouteDistanceKm`. Every call
/// returns null/empty rather than throwing, so the UI always has a fallback.
///
/// Note: the Kotlin app additionally linked the native `com.tomtom.sdk.search`
/// module for map-search autocomplete. That SDK has no Flutter equivalent, so
/// search now goes through the same TomTom *REST* POI endpoint the rest of the
/// app already used — identical data, one fewer SDK.
abstract final class TomTomService {
  static const _timeout = Duration(seconds: 15);
  static const _routeTimeout = Duration(seconds: 6);

  static Future<List<LivePoiResult>> searchNearbyPoi(
    String query,
    double lat,
    double lon, {
    int radiusMeters = 12000,
    int limit = 8,
  }) async {
    if (!AppConfig.hasTomTomKey) return const [];
    final encoded = Uri.encodeComponent(query);
    final uri = Uri.parse(
      'https://api.tomtom.com/search/2/poiSearch/$encoded.json'
      '?lat=$lat&lon=$lon&radius=$radiusMeters&limit=$limit&key=${AppConfig.tomtomApiKey}',
    );

    final json = await _getJson(uri, _timeout);
    final results = json?['results'] as List<dynamic>?;
    if (results == null) return const [];

    final list = <LivePoiResult>[];
    for (final raw in results) {
      final item = raw as Map<String, dynamic>;
      final poi = item['poi'] as Map<String, dynamic>?;
      final address = item['address'] as Map<String, dynamic>?;
      final position = item['position'] as Map<String, dynamic>?;
      final categories = poi?['categories'] as List<dynamic>?;

      list.add(
        LivePoiResult(
          name: poi?['name'] as String? ?? 'Medical Facility',
          address: address?['freeformAddress'] as String? ?? '',
          distanceMeters: (item['dist'] as num?)?.toDouble() ?? 0.0,
          phone: poi?['phone'] as String?,
          lat: (position?['lat'] as num?)?.toDouble() ?? lat,
          lon: (position?['lon'] as num?)?.toDouble() ?? lon,
          category: categories != null && categories.isNotEmpty
              ? categories.first as String?
              : null,
        ),
      );
    }
    list.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return list;
  }

  static Future<LiveTrafficData?> getLiveTraffic(double lat, double lon) async {
    if (!AppConfig.hasTomTomKey) return null;
    final uri = Uri.parse(
      'https://api.tomtom.com/traffic/services/4/flowSegmentData/relative0/10/json'
      '?point=$lat,$lon&key=${AppConfig.tomtomApiKey}',
    );

    final json = await _getJson(uri, _timeout);
    final flow = json?['flowSegmentData'] as Map<String, dynamic>?;
    if (flow == null) return null;

    final coordinates = flow['coordinates'] as List<dynamic>?;
    final firstCoord = coordinates != null && coordinates.isNotEmpty
        ? coordinates.first
        : null;

    return LiveTrafficData(
      roadName:
          (firstCoord is Map<String, dynamic>
              ? firstCoord['roadName'] as String?
              : null) ??
          'Nearby Arterial Road',
      currentSpeedKmh: (flow['currentSpeed'] as num?)?.toInt() ?? 35,
      freeFlowSpeedKmh: (flow['freeFlowSpeed'] as num?)?.toInt() ?? 50,
      delaySeconds: (flow['currentDelay'] as num?)?.toInt() ?? 0,
      confidence: (flow['confidence'] as num?)?.toDouble() ?? 0.9,
    );
  }

  /// Calculates one route between two points. [routeType] is TomTom's own
  /// parameter — `eco` for the green corridor, `fastest` for the petrol-cab
  /// baseline, matching the two calls the Live Map made.
  static Future<RouteResult?> calculateRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required String routeType,
    required bool traffic,
    String? travelMode,
  }) async {
    if (!AppConfig.hasTomTomKey) return null;
    final modeParam = travelMode == null ? '' : '&travelMode=$travelMode';
    final uri = Uri.parse(
      'https://api.tomtom.com/routing/1/calculateRoute/$fromLat,$fromLon:$toLat,$toLon/json'
      '?key=${AppConfig.tomtomApiKey}&routeType=$routeType&traffic=$traffic$modeParam',
    );

    final json = await _getJson(uri, _timeout);
    final routes = json?['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;

    final first = routes.first as Map<String, dynamic>;
    final summary = first['summary'] as Map<String, dynamic>?;
    final lengthMeters =
        (summary?['lengthInMeters'] as num?)?.toDouble() ?? 0.0;
    final travelSeconds =
        (summary?['travelTimeInSeconds'] as num?)?.toInt() ?? 0;

    final points = <List<double>>[];
    final legs = first['legs'] as List<dynamic>?;
    if (legs != null && legs.isNotEmpty) {
      final legPoints =
          (legs.first as Map<String, dynamic>)['points'] as List<dynamic>?;
      for (final p in legPoints ?? const []) {
        final point = p as Map<String, dynamic>;
        points.add([
          (point['latitude'] as num).toDouble(),
          (point['longitude'] as num).toDouble(),
        ]);
      }
    }

    return RouteResult(
      points: points,
      distanceKm: lengthMeters / 1000.0,
      durationMin: travelSeconds ~/ 60,
    );
  }

  /// Fetches a real road-network distance for the resolved origin/destination
  /// text. Returns null (caller falls back to
  /// [CarbonEstimator.estimateDistanceKm]'s haversine+detour-factor estimate) if
  /// the key is missing or the call fails.
  static Future<double?> fetchRealRouteDistanceKm(
    String originText,
    String destinationText,
  ) async {
    if (!AppConfig.hasTomTomKey) return null;
    final (lat1, lng1) = CarbonEstimator.resolveCoordinates(originText);
    final (lat2, lng2) = CarbonEstimator.resolveCoordinates(destinationText);

    final uri = Uri.parse(
      'https://api.tomtom.com/routing/1/calculateRoute/$lat1,$lng1:$lat2,$lng2/json'
      '?key=${AppConfig.tomtomApiKey}&routeType=eco&traffic=true',
    );
    final json = await _getJson(uri, _routeTimeout);
    final routes = json?['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;

    final summary =
        (routes.first as Map<String, dynamic>)['summary']
            as Map<String, dynamic>?;
    final lengthMeters =
        (summary?['lengthInMeters'] as num?)?.toDouble() ?? 0.0;
    return lengthMeters > 0 ? lengthMeters / 1000.0 : null;
  }

  static Future<Map<String, dynamic>?> _getJson(
    Uri uri,
    Duration timeout,
  ) async {
    try {
      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
