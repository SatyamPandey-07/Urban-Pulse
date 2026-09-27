import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/models/map_route.dart';
import 'package:urbanpulse/services/routing_service.dart';

/// A route going north from (10, 77) in 0.001 degree steps (about 111 m each).
MapRoute northRoute({int steps = 20, List<RouteInstruction>? instructions}) {
  final pts = [for (var i = 0; i <= steps; i++) LatLng(10 + i * 0.001, 77)];
  final geo = RouteGeometry(pts);
  return MapRoute(
    id: 'r',
    label: 'Fastest',
    mode: NavMode.drive,
    points: pts,
    distanceM: geo.totalM,
    durationS: 600,
    instructions: instructions ??
        [
          RouteInstruction(text: 'Head north', atMeters: 0, point: pts.first, kind: ManeuverKind.depart),
          RouteInstruction(text: 'Turn left onto Park Road', atMeters: 1000, point: pts[9], kind: ManeuverKind.left),
          RouteInstruction(text: 'You have arrived', atMeters: geo.totalM, point: pts.last, kind: ManeuverKind.arrive),
        ],
  );
}

void main() {
  group('route geometry', () {
    test('distances add up along the route', () {
      final g = RouteGeometry([const LatLng(10, 77), const LatLng(10.001, 77), const LatLng(10.002, 77)]);
      expect(g.totalM, closeTo(222, 3));
      expect(g.cumulative.length, 3);
    });

    test('a point on the road is at its distance along it, with no offset', () {
      final r = northRoute();
      final fix = r.geometry.project(const LatLng(10.005, 77));
      expect(fix.alongM, closeTo(556, 5));
      expect(fix.offRouteM, lessThan(1));
    });

    test('a point beside the road reports how far off it is', () {
      final r = northRoute();
      final fix = r.geometry.project(const LatLng(10.005, 77.001)); // about 110 m east
      expect(fix.offRouteM, closeTo(110, 6));
      expect(fix.alongM, closeTo(556, 8));
    });

    test('before the start and beyond the end stay on the route', () {
      final r = northRoute();
      expect(r.geometry.project(const LatLng(9.99, 77)).alongM, 0);
      expect(r.geometry.project(const LatLng(10.5, 77)).alongM, closeTo(r.geometry.totalM, 0.5));
    });

    test('empty and single-point routes never throw', () {
      expect(RouteGeometry(const []).project(const LatLng(1, 1)).offRouteM, double.infinity);
      expect(RouteGeometry(const [LatLng(1, 1)]).project(const LatLng(1, 1)).offRouteM, 0);
      expect(RouteGeometry(const []).totalM, 0);
    });
  });

  group('progress along a route', () {
    test('what is left, and the step coming up, at the start', () {
      final r = northRoute();
      final p = NavProgress.of(r, const LatLng(10.0005, 77));
      expect(p.arrived, isFalse);
      expect(p.remainingM, closeTo(r.geometry.totalM - 55, 8));
      expect(p.remainingS, inInclusiveRange(560, 600));
      expect(p.next?.text, 'Turn left onto Park Road');
      expect(p.nextInM, closeTo(1000 - 55, 15));
    });

    test('the next step moves on once one is passed', () {
      final r = northRoute();
      final p = NavProgress.of(r, const LatLng(10.0095, 77)); // past the 1000 m turn
      expect(p.next?.text, 'You have arrived');
    });

    test('near the end is arrival', () {
      final r = northRoute();
      final p = NavProgress.of(r, const LatLng(10.0199, 77));
      expect(p.arrived, isTrue);
      expect(p.remainingM, 0);
      expect(p.next, isNull);
    });

    test('off the road is reported', () {
      final r = northRoute();
      expect(NavProgress.of(r, const LatLng(10.005, 77.003)).offRouteM, greaterThan(300));
    });
  });

  group('routes that are the same road', () {
    test('same distance and time within a little is the same route', () {
      final a = northRoute();
      final b = MapRoute(id: 'b', label: 'Eco', mode: NavMode.drive, points: a.points, distanceM: a.distanceM + 10, durationS: a.durationS + 20);
      expect(a.sameAs(b), isTrue);
      final c = MapRoute(id: 'c', label: 'Eco', mode: NavMode.drive, points: a.points, distanceM: a.distanceM * 1.2, durationS: a.durationS + 200);
      expect(a.sameAs(c), isFalse);
    });

    test('walking emits nothing; driving is estimated from the distance', () {
      final drive = northRoute();
      expect(drive.estimatedCo2Grams, (drive.distanceKm * 160).round());
      final walk = MapRoute(id: 'w', label: 'Walking', mode: NavMode.walk, points: drive.points, distanceM: drive.distanceM, durationS: 1800);
      expect(walk.estimatedCo2Grams, 0);
    });
  });

  group('reading the TomTom response', () {
    Map<String, Object?> body({Object? points, Object? guidance, Object? summary}) => {
      'routes': [
        {
          'summary': summary ?? {'lengthInMeters': 2500, 'travelTimeInSeconds': 420},
          'legs': [
            {'points': points ?? [{'latitude': 10.0, 'longitude': 77.0}, {'latitude': 10.01, 'longitude': 77.0}]},
          ],
          'guidance': guidance,
        },
      ],
    };

    test('a normal response', () {
      final r = RoutingService.parseTomTom(
        body(guidance: {
          'instructions': [
            {'routeOffsetInMeters': 0, 'point': {'latitude': 10.0, 'longitude': 77.0}, 'maneuver': 'DEPART', 'message': 'Leave from MG Road'},
            {'routeOffsetInMeters': 900, 'point': {'latitude': 10.008, 'longitude': 77.0}, 'maneuver': 'TURN_LEFT', 'message': 'Turn left onto Park Road'},
          ],
        }),
        mode: NavMode.drive,
        id: 'a',
        label: 'Fastest',
      )!;
      expect(r.distanceM, 2500);
      expect(r.minutes, 7);
      expect(r.points.length, 2);
      expect(r.instructions.map((s) => s.kind), [ManeuverKind.depart, ManeuverKind.left]);
      expect(r.trafficAware, isTrue);
      expect(r.source, 'TomTom');
    });

    test('garbage in, nothing out', () {
      for (final bad in <Object?>[null, 5, 'x', <Object?>[], {}, {'routes': []}, {'routes': [5]}, {'routes': [{}]}, body(summary: {'lengthInMeters': 0, 'travelTimeInSeconds': 5}), body(points: [{'latitude': 1, 'longitude': 2}])]) {
        expect(RoutingService.parseTomTom(bad, mode: NavMode.drive, id: 'x', label: 'x'), isNull, reason: '$bad');
      }
    });

    test('a step with missing parts is skipped, not fatal', () {
      final r = RoutingService.parseTomTom(
        body(guidance: {
          'instructions': [
            {'routeOffsetInMeters': 10},
            {'routeOffsetInMeters': 20, 'point': {'latitude': 'x'}, 'message': 'a'},
            {'routeOffsetInMeters': 30, 'point': {'latitude': 10.001, 'longitude': 77.0}, 'message': 'Continue', 'maneuver': 'STRAIGHT'},
          ],
        }),
        mode: NavMode.drive,
        id: 'a',
        label: 'Fastest',
      )!;
      expect(r.instructions.length, 1);
    });
  });

  group('reading the OpenStreetMap routing response', () {
    Map<String, Object?> osrm({int routes = 1}) => {
      'code': 'Ok',
      'routes': [
        for (var i = 0; i < routes; i++)
          {
            'distance': 3000.0 + i * 400,
            'duration': 500.0 + i * 90,
            'geometry': {
              'coordinates': [[77.0, 10.0], [77.0, 10.01], [77.01, 10.02]],
            },
            'legs': [
              {
                'steps': [
                  {'distance': 1100.0, 'name': 'MG Road', 'maneuver': {'type': 'depart', 'location': [77.0, 10.0]}},
                  {'distance': 1900.0, 'name': 'Park Road', 'maneuver': {'type': 'turn', 'modifier': 'left', 'location': [77.0, 10.01]}},
                  {'distance': 0.0, 'name': '', 'maneuver': {'type': 'arrive', 'location': [77.01, 10.02]}},
                ],
              },
            ],
          },
      ],
    };

    test('routes, best first, with steps whose distances accumulate', () {
      final r = RoutingService.parseOsrm(osrm(routes: 2), mode: NavMode.drive);
      expect(r.length, 2);
      expect(r.first.label, 'Fastest');
      expect(r.last.label, 'Alternative');
      expect(r.first.points.first, const LatLng(10.0, 77.0)); // longitude and latitude are swapped back
      expect(r.first.instructions.map((s) => s.atMeters), [0, 1100, 3000]);
      expect(r.first.instructions[1].text, 'Turn left onto Park Road');
      expect(r.first.instructions.last.kind, ManeuverKind.arrive);
      expect(r.first.source, 'OpenStreetMap routing');
    });

    test('walking is one route called Walking', () {
      expect(RoutingService.parseOsrm(osrm(), mode: NavMode.walk).single.label, 'Walking');
    });

    test('an error code, or nonsense, is no route', () {
      for (final bad in <Object?>[null, 'x', {'code': 'NoRoute'}, {'code': 'Ok'}, {'code': 'Ok', 'routes': [5]}, {'code': 'Ok', 'routes': [{'distance': 1, 'duration': 1, 'geometry': {}}]}]) {
        expect(RoutingService.parseOsrm(bad, mode: NavMode.drive), isEmpty, reason: '$bad');
      }
    });
  });
}
