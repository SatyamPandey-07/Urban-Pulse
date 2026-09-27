import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/config.dart';
import '../models/map_route.dart';

/// Real routes between two points. TomTom (with live traffic) when a key is
/// configured; otherwise, or if it is unreachable, the open OpenStreetMap
/// routing services. When neither answers the result is an empty list: nothing
/// is ever invented.
class RoutingService {
  RoutingService({http.Client? client, Duration timeout = const Duration(seconds: 12)}) : _client = client ?? http.Client(), _timeout = timeout;

  final http.Client _client;
  final Duration _timeout;

  Future<List<MapRoute>> routes(LatLng from, LatLng to, NavMode mode) async {
    if (!_valid(from) || !_valid(to)) return const [];
    if (AppConfig.hasTomTomKey) {
      final tt = await _tomtom(from, to, mode);
      if (tt.isNotEmpty) return tt;
    }
    return _osrm(from, to, mode);
  }

  static double? _d(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
  static int? _i(Object? v) => v is num && v.isFinite ? v.toInt() : null;

  static bool _valid(LatLng p) => p.latitude.isFinite && p.longitude.isFinite && p.latitude.abs() <= 90 && p.longitude.abs() <= 180;

  // --- TomTom ---------------------------------------------------------------

  Future<List<MapRoute>> _tomtom(LatLng from, LatLng to, NavMode mode) async {
    Uri uri(String type) => Uri.parse(
      'https://api.tomtom.com/routing/1/calculateRoute/${from.latitude},${from.longitude}:${to.latitude},${to.longitude}/json'
      '?key=${AppConfig.tomtomApiKey}&routeType=$type&traffic=${mode == NavMode.drive}'
      '&travelMode=${mode == NavMode.drive ? 'car' : 'pedestrian'}&instructionsType=text&language=en-GB',
    );
    final types = mode == NavMode.drive ? const ['fastest', 'eco'] : const ['fastest'];
    final bodies = await Future.wait([for (final t in types) _get(uri(t))]);
    final out = <MapRoute>[];
    for (var i = 0; i < types.length; i++) {
      final r = parseTomTom(bodies[i], mode: mode, id: 'tt_${types[i]}', label: mode == NavMode.walk ? 'Walking' : (types[i] == 'eco' ? 'Eco' : 'Fastest'));
      if (r == null) continue;
      // The eco route is often the very same road: show it once.
      if (out.any((o) => o.sameAs(r))) continue;
      out.add(r);
    }
    return out;
  }

  /// A TomTom `calculateRoute` response as a route, or null if it holds none.
  static MapRoute? parseTomTom(Object? body, {required NavMode mode, required String id, required String label}) {
    if (body is! Map) return null;
    final routes = body['routes'];
    if (routes is! List || routes.isEmpty || routes.first is! Map) return null;
    final first = routes.first as Map;
    final summary = first['summary'];
    if (summary is! Map) return null;
    final length = _d(summary['lengthInMeters']);
    final secs = _i(summary['travelTimeInSeconds']);
    if (length == null || secs == null || length <= 0) return null;

    final points = <LatLng>[];
    final legs = first['legs'];
    if (legs is List) {
      for (final leg in legs) {
        if (leg is! Map || leg['points'] is! List) continue;
        for (final p in leg['points'] as List) {
          if (p is! Map) continue;
          final la = _d(p['latitude']);
          final lo = _d(p['longitude']);
          if (la == null || lo == null) continue;
          points.add(LatLng(la, lo));
        }
      }
    }
    if (points.length < 2) return null;

    final steps = <RouteInstruction>[];
    final guidance = first['guidance'];
    final list = guidance is Map ? guidance['instructions'] : null;
    if (list is List) {
      for (final s in list) {
        if (s is! Map) continue;
        final at = _d(s['routeOffsetInMeters']);
        final pt = s['point'];
        final text = s['message'] is String ? (s['message'] as String).trim() : null;
        if (at == null || pt is! Map || text == null || text.isEmpty) continue;
        final la = _d(pt['latitude']);
        final lo = _d(pt['longitude']);
        if (la == null || lo == null) continue;
        steps.add(RouteInstruction(text: text, atMeters: at, point: LatLng(la, lo), kind: _tomtomKind('${s['maneuver'] ?? ''}')));
      }
    }
    return MapRoute(id: id, label: label, mode: mode, points: points, distanceM: length, durationS: secs, instructions: steps, trafficAware: mode == NavMode.drive, source: 'TomTom');
  }

  static ManeuverKind _tomtomKind(String m) {
    final s = m.toUpperCase();
    if (s.contains('ARRIVE')) return ManeuverKind.arrive;
    if (s.contains('DEPART')) return ManeuverKind.depart;
    if (s.contains('ROUNDABOUT')) return ManeuverKind.roundabout;
    if (s.contains('UTURN') || s.contains('U_TURN')) return ManeuverKind.uTurn;
    if (s.contains('SHARP_LEFT')) return ManeuverKind.sharpLeft;
    if (s.contains('SHARP_RIGHT')) return ManeuverKind.sharpRight;
    if (s.contains('BEAR_LEFT') || s.contains('SLIGHT_LEFT')) return ManeuverKind.slightLeft;
    if (s.contains('BEAR_RIGHT') || s.contains('SLIGHT_RIGHT')) return ManeuverKind.slightRight;
    if (s.contains('KEEP') || s.contains('FORK') || s.contains('SEPARATE')) return ManeuverKind.fork;
    if (s.contains('MERGE') || s.contains('ENTER_MOTORWAY') || s.contains('ENTER_FREEWAY')) return ManeuverKind.merge;
    if (s.contains('LEFT')) return ManeuverKind.left;
    if (s.contains('RIGHT')) return ManeuverKind.right;
    return ManeuverKind.straight;
  }

  // --- OpenStreetMap routing (OSRM) -------------------------------------------

  Future<List<MapRoute>> _osrm(LatLng from, LatLng to, NavMode mode) async {
    final coords = '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
    final base = mode == NavMode.drive ? 'https://router.project-osrm.org/route/v1/driving' : 'https://routing.openstreetmap.de/routed-foot/route/v1/driving';
    final body = await _get(Uri.parse('$base/$coords?overview=full&geometries=geojson&steps=true&alternatives=${mode == NavMode.drive}'));
    return parseOsrm(body, mode: mode);
  }

  /// An OSRM `route` response as routes (the best first), or none.
  static List<MapRoute> parseOsrm(Object? body, {required NavMode mode}) {
    if (body is! Map || body['code'] != 'Ok') return const [];
    final routes = body['routes'];
    if (routes is! List) return const [];
    final out = <MapRoute>[];
    for (var i = 0; i < routes.length && out.length < 3; i++) {
      final r = routes[i];
      if (r is! Map) continue;
      final dist = _d(r['distance']);
      final secs = _d(r['duration']);
      final geo = r['geometry'];
      if (dist == null || secs == null || dist <= 0 || geo is! Map || geo['coordinates'] is! List) continue;
      final pts = <LatLng>[];
      for (final c in geo['coordinates'] as List) {
        if (c is! List || c.length < 2) continue;
        final lo = _d(c[0]);
        final la = _d(c[1]);
        if (la == null || lo == null) continue;
        pts.add(LatLng(la, lo));
      }
      if (pts.length < 2) continue;

      final steps = <RouteInstruction>[];
      var run = 0.0;
      final legs = r['legs'];
      if (legs is List) {
        for (final leg in legs) {
          if (leg is! Map || leg['steps'] is! List) continue;
          for (final s in leg['steps'] as List) {
            if (s is! Map) continue;
            final m = s['maneuver'];
            if (m is! Map) continue;
            final loc = m['location'];
            if (loc is! List || loc.length < 2) continue;
            final lo = _d(loc[0]);
            final la = _d(loc[1]);
            if (la == null || lo == null) continue;
            final kind = _osrmKind('${m['type']}', '${m['modifier'] ?? ''}');
            steps.add(RouteInstruction(text: _osrmText('${m['type']}', '${m['modifier'] ?? ''}', '${s['name'] ?? ''}', _i(m['exit'])), atMeters: run, point: LatLng(la, lo), kind: kind));
            run += _d(s['distance']) ?? 0;
          }
        }
      }
      out.add(MapRoute(
        id: 'osrm_$i',
        label: mode == NavMode.walk ? 'Walking' : (i == 0 ? 'Fastest' : 'Alternative'),
        mode: mode,
        points: pts,
        distanceM: dist,
        durationS: secs.round(),
        instructions: steps,
        source: 'OpenStreetMap routing',
      ));
    }
    return out;
  }

  static ManeuverKind _osrmKind(String type, String mod) {
    if (type == 'arrive') return ManeuverKind.arrive;
    if (type == 'depart') return ManeuverKind.depart;
    if (type.contains('roundabout') || type == 'rotary') return ManeuverKind.roundabout;
    if (type == 'merge') return ManeuverKind.merge;
    if (type == 'fork') return ManeuverKind.fork;
    return switch (mod) {
      'left' => ManeuverKind.left,
      'right' => ManeuverKind.right,
      'slight left' => ManeuverKind.slightLeft,
      'slight right' => ManeuverKind.slightRight,
      'sharp left' => ManeuverKind.sharpLeft,
      'sharp right' => ManeuverKind.sharpRight,
      'uturn' => ManeuverKind.uTurn,
      _ => ManeuverKind.straight,
    };
  }

  static String _osrmText(String type, String mod, String name, int? exit) {
    final road = name.trim().isEmpty ? '' : ' onto ${name.trim()}';
    final on = name.trim().isEmpty ? '' : ' on ${name.trim()}';
    switch (type) {
      case 'depart':
        return 'Head out${on.isEmpty ? '' : on}';
      case 'arrive':
        return 'You have arrived';
      case 'roundabout':
      case 'rotary':
      case 'roundabout turn':
        return exit == null ? 'Go through the roundabout$road' : 'At the roundabout, take exit $exit$road';
      case 'merge':
        return 'Merge${mod.isEmpty ? '' : ' $mod'}$road';
      case 'fork':
        return 'Keep ${mod.contains('left') ? 'left' : mod.contains('right') ? 'right' : 'straight'} at the fork$road';
      case 'end of road':
      case 'turn':
      case 'new name':
      case 'continue':
      case 'on ramp':
      case 'off ramp':
        if (mod == 'uturn') return 'Make a U-turn$on';
        if (mod.isEmpty || mod == 'straight') return 'Continue straight$on';
        return 'Turn $mod$road';
      default:
        return mod.isEmpty ? 'Continue$on' : 'Turn $mod$road';
    }
  }

  Future<Object?> _get(Uri uri) async {
    try {
      final res = await _client.get(uri, headers: const {'User-Agent': 'UrbanPulseApp/1.0'}).timeout(_timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return jsonDecode(res.body);
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
