import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// How the traveller moves on the Live Map.
enum NavMode {
  drive('Drive'),
  walk('Walk');

  const NavMode(this.label);
  final String label;
}

/// One spoken-style step of a route ("Turn left onto MG Road").
class RouteInstruction {
  const RouteInstruction({required this.text, required this.atMeters, required this.point, this.kind = ManeuverKind.straight});

  final String text;

  /// How far along the route this step happens, in metres from the start.
  final double atMeters;
  final LatLng point;
  final ManeuverKind kind;
}

enum ManeuverKind { depart, straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn, roundabout, merge, fork, arrive }

/// One way to get from A to B, as measured by a routing service.
class MapRoute {
  MapRoute({
    required this.id,
    required this.label,
    required this.mode,
    required this.points,
    required this.distanceM,
    required this.durationS,
    this.instructions = const [],
    this.trafficAware = false,
    this.source = '',
  }) : geometry = RouteGeometry(points);

  final String id;

  /// "Fastest", "Eco", "Alternative", "Walking".
  final String label;
  final NavMode mode;
  final List<LatLng> points;
  final double distanceM;
  final int durationS;
  final List<RouteInstruction> instructions;

  /// Whether the time includes live traffic.
  final bool trafficAware;

  /// Who measured it ("TomTom", "OpenStreetMap routing").
  final String source;
  final RouteGeometry geometry;

  double get distanceKm => distanceM / 1000;
  int get minutes => math.max(1, (durationS / 60).round());

  /// Grams of CO₂ for the trip: an estimate from the distance and the mode
  /// (a petrol car; walking emits none). It is not measured.
  int get estimatedCo2Grams => mode == NavMode.walk ? 0 : (distanceKm * 160).round();

  /// Two routes that are the same road for all practical purposes.
  bool sameAs(MapRoute o) => mode == o.mode && (distanceM - o.distanceM).abs() <= math.max(50, distanceM * 0.01) && (durationS - o.durationS).abs() <= 60;
}

/// Where a traveller is along a route, and how far from it.
class RouteFix {
  const RouteFix({required this.alongM, required this.offRouteM, required this.segment});

  final double alongM;
  final double offRouteM;
  final int segment;
}

/// The shape of a route: distances along it, and where a point falls on it.
class RouteGeometry {
  RouteGeometry(List<LatLng> points) : points = List.unmodifiable(points) {
    var run = 0.0;
    final cum = <double>[0];
    for (var i = 1; i < points.length; i++) {
      run += _dist.as(LengthUnit.Meter, points[i - 1], points[i]);
      cum.add(run);
    }
    cumulative = cum;
  }

  static const _dist = Distance();

  final List<LatLng> points;
  late final List<double> cumulative;

  double get totalM => cumulative.isEmpty ? 0 : cumulative.last;

  /// The nearest point on the route to [p]: the distance travelled along the
  /// route to it, and how far [p] is from the road. Works in a local flat
  /// projection, which is exact enough for the few hundred metres around a point.
  RouteFix project(LatLng p) {
    if (points.isEmpty) return const RouteFix(alongM: 0, offRouteM: double.infinity, segment: 0);
    if (points.length == 1) return RouteFix(alongM: 0, offRouteM: _dist.as(LengthUnit.Meter, p, points.first), segment: 0);
    final cosLat = math.cos(p.latitudeInRad);
    const mPerDeg = 111320.0;
    double x(LatLng q) => (q.longitude - p.longitude) * mPerDeg * cosLat;
    double y(LatLng q) => (q.latitude - p.latitude) * mPerDeg;

    var best = double.infinity;
    var bestAlong = 0.0;
    var bestSeg = 0;
    for (var i = 0; i < points.length - 1; i++) {
      final ax = x(points[i]), ay = y(points[i]);
      final bx = x(points[i + 1]), by = y(points[i + 1]);
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      // The point is at the origin: the parameter of its closest approach.
      var t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2);
      t = t.clamp(0.0, 1.0);
      final cx = ax + t * dx, cy = ay + t * dy;
      final d = math.sqrt(cx * cx + cy * cy);
      if (d < best) {
        best = d;
        bestSeg = i;
        bestAlong = cumulative[i] + t * (cumulative[i + 1] - cumulative[i]);
      }
    }
    return RouteFix(alongM: bestAlong, offRouteM: best, segment: bestSeg);
  }
}

/// Live progress of a trip: what is left, and the step coming up.
class NavProgress {
  const NavProgress({required this.remainingM, required this.remainingS, required this.offRouteM, required this.arrived, this.next, this.nextInM});

  final double remainingM;
  final int remainingS;
  final double offRouteM;
  final bool arrived;
  final RouteInstruction? next;
  final double? nextInM;

  /// Works out progress for a traveller at [at] on [route].
  static NavProgress of(MapRoute route, LatLng at, {double arriveWithinM = 30}) {
    final fix = route.geometry.project(at);
    final total = route.geometry.totalM;
    final remaining = math.max(0.0, total - fix.alongM);
    final endDistance = route.points.isEmpty ? double.infinity : const Distance().as(LengthUnit.Meter, at, route.points.last);
    final arrived = endDistance <= arriveWithinM || remaining <= arriveWithinM / 2;
    // Time left scales with the distance left along the route as measured.
    final secs = total <= 0 ? 0 : (route.durationS * (remaining / total)).round();
    RouteInstruction? next;
    for (final s in route.instructions) {
      if (s.kind == ManeuverKind.depart) continue;
      if (s.atMeters > fix.alongM + 8) {
        next = s;
        break;
      }
    }
    return NavProgress(
      remainingM: arrived ? 0 : remaining,
      remainingS: arrived ? 0 : secs,
      offRouteM: fix.offRouteM,
      arrived: arrived,
      next: arrived ? null : next,
      nextInM: next == null ? null : math.max(0.0, next.atMeters - fix.alongM),
    );
  }
}
