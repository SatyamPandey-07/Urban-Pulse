import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/trip_brief.dart';

/// How a route is drawn for a transport mode.
enum RouteStyle {
  /// A curved great-circle-style arc (flights).
  arc,

  /// A dashed line (rail).
  dashed,

  /// A solid road-style line (cabs, buses and everything else).
  solid,
}

/// Map presentation of a transport mode.
abstract final class RouteStyles {
  static RouteStyle styleFor(TripTransportMode? mode) => switch (mode) {
    TripTransportMode.flight => RouteStyle.arc,
    TripTransportMode.train || TripTransportMode.metroLocal => RouteStyle.dashed,
    _ => RouteStyle.solid,
  };

  /// Which selected mode to preview first: flights and trains are the most
  /// distinctive, then the rest in menu order.
  static TripTransportMode? preferred(Iterable<TripTransportMode> modes) {
    if (modes.isEmpty) return null;
    for (final m in const [TripTransportMode.flight, TripTransportMode.train]) {
      if (modes.contains(m)) return m;
    }
    return TripTransportMode.values.firstWhere(modes.contains);
  }
}

/// Points from [a] to [b] for [style], [steps] + 1 of them.
///
/// Arcs bow away from the straight line like a flight path; roads and rails
/// get a slight bend so they don't read as a ruler line.
List<LatLng> routePath(LatLng a, LatLng b, RouteStyle style, {int steps = 64}) {
  final bow = switch (style) {
    RouteStyle.arc => 0.28,
    RouteStyle.dashed => 0.07,
    RouteStyle.solid => 0.10,
  };

  final dLat = b.latitude - a.latitude;
  final dLng = b.longitude - a.longitude;
  // A control point pushed out perpendicular to the a-b line.
  final control = LatLng(
    (a.latitude + b.latitude) / 2 + dLng * bow,
    (a.longitude + b.longitude) / 2 - dLat * bow,
  );

  return [
    for (var i = 0; i <= steps; i++)
      () {
        final t = i / steps;
        final u = 1 - t;
        return LatLng(
          u * u * a.latitude + 2 * u * t * control.latitude + t * t * b.latitude,
          u * u * a.longitude + 2 * u * t * control.longitude + t * t * b.longitude,
        );
      }(),
  ];
}

/// Compass bearing in degrees (0 = north, clockwise) from [a] to [b].
double bearingDegrees(LatLng a, LatLng b) {
  final lat1 = a.latitudeInRad;
  final lat2 = b.latitudeInRad;
  final dLng = b.longitudeInRad - a.longitudeInRad;
  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}
