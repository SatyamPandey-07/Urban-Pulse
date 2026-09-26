import 'dart:convert';
import 'dart:math' as math;

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
abstract final class TomTomService {
  static const _timeout = Duration(seconds: 15);
  static const _routeTimeout = Duration(seconds: 6);

  /// Searches for places (POIs, landmarks, localities, addresses, stations)
  /// bounded to a geographic region centered at [lat], [lon].
  ///
  /// Uses an explicit bounding box around ([lat], [lon]) with [radiusKm] (default 60 km).
  /// Falls back to country-wide search if no results exist locally, and falls
  /// back to OpenStreetMap Nominatim with viewbox if TomTom key is unavailable
  /// or fails.
  static Future<List<LivePoiResult>> searchPlacesBounded(
    String query, {
    required double lat,
    required double lon,
    double radiusKm = 60.0,
    int limit = 6,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    // Calculate bounding box:
    // 1 deg lat ~ 111.0 km; 1 deg lon ~ 111.0 * cos(lat)
    final deltaLat = (radiusKm / 111.0).clamp(0.05, 5.0);
    final cosLat = math.cos(lat * math.pi / 180.0).abs();
    final deltaLon =
        (radiusKm / (111.0 * (cosLat < 0.01 ? 1.0 : cosLat))).clamp(0.05, 5.0);
    final topLat = (lat + deltaLat).clamp(-90.0, 90.0);
    final btmLat = (lat - deltaLat).clamp(-90.0, 90.0);
    final leftLon = (lon - deltaLon).clamp(-180.0, 180.0);
    final rightLon = (lon + deltaLon).clamp(-180.0, 180.0);

    if (AppConfig.hasTomTomKey) {
      final encoded = Uri.encodeComponent(cleanQuery);
      final radiusMeters = (radiusKm * 1000).toInt();

      // 1. Try TomTom Fuzzy Search with explicit bounding box & geoBias
      final boundedUri = Uri.parse(
        'https://api.tomtom.com/search/2/search/$encoded.json'
        '?lat=$lat&lon=$lon&radius=$radiusMeters'
        '&topLeft=$topLat,$leftLon&btmRight=$btmLat,$rightLon'
        '&countrySet=IN&limit=$limit&key=${AppConfig.tomtomApiKey}',
      );
      final boundedJson = await _getJson(boundedUri, _timeout);
      final parsedBounded = _parseTomTomResults(boundedJson, lat, lon);
      if (parsedBounded.isNotEmpty) {
        return parsedBounded;
      }

      // 2. Try TomTom POI search if it was a category
      final poiUri = Uri.parse(
        'https://api.tomtom.com/search/2/poiSearch/$encoded.json'
        '?lat=$lat&lon=$lon&radius=$radiusMeters&limit=$limit&key=${AppConfig.tomtomApiKey}',
      );
      final poiJson = await _getJson(poiUri, _timeout);
      final parsedPoi = _parseTomTomResults(poiJson, lat, lon);
      if (parsedPoi.isNotEmpty) {
        return parsedPoi;
      }

      // 3. If bounded search found 0 results locally, try country-wide fuzzy search
      final nationwideUri = Uri.parse(
        'https://api.tomtom.com/search/2/search/$encoded.json'
        '?lat=$lat&lon=$lon&countrySet=IN&limit=$limit&key=${AppConfig.tomtomApiKey}',
      );
      final nationwideJson = await _getJson(nationwideUri, _timeout);
      final parsedNationwide = _parseTomTomResults(nationwideJson, lat, lon);
      if (parsedNationwide.isNotEmpty) {
        return parsedNationwide;
      }
    }

    // 4. OpenStreetMap Nominatim fallback with viewbox bounding
    try {
      final osmEncoded = Uri.encodeComponent(cleanQuery);
      final osmUri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=$osmEncoded&format=json&limit=$limit&countrycodes=in'
        '&viewbox=$leftLon,$topLat,$rightLon,$btmLat&bounded=0',
      );
      final osmRes = await http.get(
        osmUri,
        headers: {'User-Agent': 'UrbanPulseApp/1.0 (contact@urbanpulse.ai)'},
      ).timeout(const Duration(seconds: 5));
      if (osmRes.statusCode >= 200 && osmRes.statusCode < 300) {
        final list = jsonDecode(osmRes.body) as List<dynamic>?;
        if (list != null && list.isNotEmpty) {
          final osmResults = <LivePoiResult>[];
          for (final item in list) {
            final m = item as Map<String, dynamic>;
            final rLat = double.tryParse(m['lat']?.toString() ?? '') ?? lat;
            final rLon = double.tryParse(m['lon']?.toString() ?? '') ?? lon;
            final distM =
                CarbonEstimator.haversineKm(lat, lon, rLat, rLon) * 1000.0;
            final name = (m['name'] as String?)?.isNotEmpty == true
                ? m['name'] as String
                : (m['display_name'] as String?)?.split(',').first.trim() ??
                    cleanQuery;
            osmResults.add(
              LivePoiResult(
                name: name,
                address: m['display_name'] as String? ?? '',
                distanceMeters: distM,
                lat: rLat,
                lon: rLon,
                category: m['type'] as String?,
              ),
            );
          }
          osmResults.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
          return osmResults;
        }
      }
    } catch (_) {}

    return const [];
  }

  static Future<List<LivePoiResult>> searchNearbyPoi(
    String query,
    double lat,
    double lon, {
    int radiusMeters = 12000,
    int limit = 8,
  }) async {
    if (!AppConfig.hasTomTomKey) {
      return searchPlacesBounded(
        query,
        lat: lat,
        lon: lon,
        radiusKm: radiusMeters / 1000.0,
        limit: limit,
      );
    }
    final encoded = Uri.encodeComponent(query);
    final uri = Uri.parse(
      'https://api.tomtom.com/search/2/poiSearch/$encoded.json'
      '?lat=$lat&lon=$lon&radius=$radiusMeters&limit=$limit&key=${AppConfig.tomtomApiKey}',
    );

    final json = await _getJson(uri, _timeout);
    final list = _parseTomTomResults(json, lat, lon);
    if (list.isNotEmpty) return list;

    // Fallback to bounded places search if POI category search yielded no matches
    return searchPlacesBounded(
      query,
      lat: lat,
      lon: lon,
      radiusKm: radiusMeters / 1000.0,
      limit: limit,
    );
  }

  static List<LivePoiResult> _parseTomTomResults(
    Map<String, dynamic>? json,
    double userLat,
    double userLon,
  ) {
    final results = json?['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return const [];

    final list = <LivePoiResult>[];
    for (final raw in results) {
      final item = raw as Map<String, dynamic>;
      final poi = item['poi'] as Map<String, dynamic>?;
      final address = item['address'] as Map<String, dynamic>?;
      final position = item['position'] as Map<String, dynamic>?;
      final categories = poi?['categories'] as List<dynamic>?;

      final resLat = (position?['lat'] as num?)?.toDouble() ?? userLat;
      final resLon = (position?['lon'] as num?)?.toDouble() ?? userLon;
      final rawDist = (item['dist'] as num?)?.toDouble();
      final distMeters = rawDist ??
          (CarbonEstimator.haversineKm(userLat, userLon, resLat, resLon) *
              1000.0);

      String name;
      if (poi != null && (poi['name'] as String?)?.isNotEmpty == true) {
        name = poi['name'] as String;
      } else if ((address?['municipalitySubdivision'] as String?)?.isNotEmpty ==
          true) {
        name = address!['municipalitySubdivision'] as String;
      } else if ((address?['municipality'] as String?)?.isNotEmpty == true) {
        name = address!['municipality'] as String;
      } else if ((address?['streetName'] as String?)?.isNotEmpty == true) {
        name = address!['streetName'] as String;
      } else {
        name = address?['freeformAddress'] as String? ?? 'Location';
      }

      list.add(
        LivePoiResult(
          name: name,
          address: address?['freeformAddress'] as String? ?? '',
          distanceMeters: distMeters,
          phone: poi?['phone'] as String?,
          lat: resLat,
          lon: resLon,
          category: categories != null && categories.isNotEmpty
              ? categories.first as String?
              : item['type'] as String?,
        ),
      );
    }
    list.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return list;
  }

  static Future<LiveTrafficData?> getLiveTraffic(
    double lat,
    double lon,
  ) async => (await getLiveTrafficSegment(lat, lon))?.data;

  /// The live flow segment *and* its real road geometry, so the map can draw the
  /// actual corridor the reading describes rather than an invented polyline.
  static Future<LiveTrafficSegment?> getLiveTrafficSegment(
    double lat,
    double lon,
  ) async {
    if (!AppConfig.hasTomTomKey) return null;
    final uri = Uri.parse(
      'https://api.tomtom.com/traffic/services/4/flowSegmentData/relative0/10/json'
      '?point=$lat,$lon&key=${AppConfig.tomtomApiKey}',
    );

    final json = await _getJson(uri, _timeout);
    final flow = json?['flowSegmentData'] as Map<String, dynamic>?;
    if (flow == null) return null;

    // TomTom returns the segment shape under coordinates.coordinate.
    final wrapper = flow['coordinates'];
    final rawPoints = wrapper is Map<String, dynamic>
        ? wrapper['coordinate'] as List<dynamic>?
        : wrapper as List<dynamic>?;
    final geometry = <List<double>>[
      for (final p in rawPoints ?? const [])
        if (p is Map<String, dynamic> &&
            p['latitude'] != null &&
            p['longitude'] != null)
          [
            (p['latitude'] as num).toDouble(),
            (p['longitude'] as num).toDouble(),
          ],
    ];

    final currentSpeed = (flow['currentSpeed'] as num?)?.toInt();
    final freeFlowSpeed = (flow['freeFlowSpeed'] as num?)?.toInt();
    // Without both speeds there is no congestion reading to report.
    if (currentSpeed == null || freeFlowSpeed == null) return null;

    return LiveTrafficSegment(
      data: LiveTrafficData(
        roadName: flow['frc'] as String? ?? 'Current corridor',
        currentSpeedKmh: currentSpeed,
        freeFlowSpeedKmh: freeFlowSpeed,
        delaySeconds:
            (flow['currentTravelTime'] as num?)?.toInt() != null &&
                (flow['freeFlowTravelTime'] as num?)?.toInt() != null
            ? ((flow['currentTravelTime'] as num).toInt() -
                      (flow['freeFlowTravelTime'] as num).toInt())
                  .clamp(0, 1 << 30)
            : 0,
        confidence: (flow['confidence'] as num?)?.toDouble() ?? 0.9,
      ),
      geometry: geometry,
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
