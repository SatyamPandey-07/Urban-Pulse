import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/models/live_city_data.dart';
import 'package:urbanpulse/models/map_category.dart';
import 'package:urbanpulse/models/map_route.dart';
import 'package:urbanpulse/services/live_location.dart';
import 'package:urbanpulse/services/live_map_data.dart';
import 'package:urbanpulse/state/live_map_controller.dart';
import 'package:urbanpulse/state/map_requests.dart';

import '../services/map_route_test.dart' show northRoute;

/// Answers the map's questions with what the test scripts, and records what was asked.
class ScriptedMapData implements LiveMapData {
  List<LivePoiResult> searchResults = const [];
  List<LivePoiResult> nearbyResults = const [];
  List<MapRoute> routeResults = [];
  String? describeResult;
  Duration delay = Duration.zero;
  bool throws = false;
  String? traffic;
  final searches = <String>[];
  final nearbyAsked = <MapCategory>[];
  final routeAsks = <(LatLng, LatLng, NavMode)>[];

  Future<void> _wait() async {
    if (throws) throw StateError('scripted failure');
    if (delay > Duration.zero) await Future<void>.delayed(delay);
  }

  @override
  Future<List<LivePoiResult>> search(String query, LatLng near) async {
    searches.add(query);
    await _wait();
    return searchResults;
  }

  @override
  Future<List<LivePoiResult>> nearby(MapCategory category, LatLng near) async {
    nearbyAsked.add(category);
    await _wait();
    return nearbyResults;
  }

  @override
  Future<List<MapRoute>> routes(LatLng from, LatLng to, NavMode mode) async {
    routeAsks.add((from, to, mode));
    await _wait();
    return routeResults;
  }

  @override
  Future<String?> describe(LatLng point) async {
    await _wait();
    return describeResult;
  }

  @override
  String? get trafficTiles => traffic;
}

class ScriptedLocation implements LiveLocation {
  LocationResult result = const LocationResult(LocationStatus.ok, UserFix(point: LatLng(10, 77), accuracyM: 12));
  final positions = StreamController<UserFix>.broadcast();
  int requests = 0;
  LocationStatus? openedFor;

  @override
  Future<LocationResult> request() async {
    requests++;
    return result;
  }

  @override
  Stream<UserFix> watch({int distanceFilterM = 5}) => positions.stream;

  @override
  Future<void> openSettings(LocationStatus status) async => openedFor = status;
}

LivePoiResult poi(String name, double lat, double lon, {double d = 500}) => LivePoiResult(name: name, address: '$name street', distanceMeters: d, lat: lat, lon: lon);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late ScriptedMapData data;
  late ScriptedLocation loc;
  late LiveMapController c;
  late List<CameraRequest> cameras;

  setUp(() {
    data = ScriptedMapData();
    loc = ScriptedLocation();
    c = LiveMapController(data: data, location: loc, searchDelay: const Duration(milliseconds: 20));
    cameras = [];
    c.cameraRequests.listen(cameras.add);
  });
  tearDown(() => c.dispose());

  group('your position', () {
    test('a fix is kept and the camera goes to it', () async {
      await c.start();
      await settle();
      expect(c.hasFix, isTrue);
      expect(c.viewCenter, const LatLng(10, 77));
      expect(c.locationStatus, LocationStatus.ok);
      expect(cameras.single, isA<CameraMove>().having((m) => m.center, 'center', const LatLng(10, 77)));
    });

    test('with location off nothing is invented, and the reason is kept', () async {
      loc.result = const LocationResult(LocationStatus.serviceOff);
      await c.start();
      expect(c.hasFix, isFalse);
      expect(c.locationStatus, LocationStatus.serviceOff);
      expect(cameras, isEmpty);
      await c.openLocationSettings();
      expect(loc.openedFor, LocationStatus.serviceOff);
    });

    test('a throwing location service is only "unavailable"', () async {
      final bad = _ThrowingLocation();
      final d = LiveMapController(data: data, location: bad);
      addTearDown(d.dispose);
      await d.start();
      expect(d.locationStatus, LocationStatus.unavailable);
    });

    test('asking twice at once reads the position once', () async {
      await Future.wait([c.locate(), c.locate()]);
      expect(loc.requests, 1);
    });
  });

  group('search', () {
    test('results appear, and the camera fits them', () async {
      data.searchResults = [poi('Amber Fort', 26.98, 75.85), poi('Hawa Mahal', 26.92, 75.82)];
      await c.search('jaipur');
      await settle();
      expect(c.results.length, 2);
      expect(c.searching, isFalse);
      expect(cameras.whereType<FitPlaces>().single.points.length, 2);
    });

    test('nothing found says so, plainly', () async {
      await c.search('zzzz');
      expect(c.results, isEmpty);
      expect(c.searchMessage, contains('No places matched'));
    });

    test('a failing service is the same as nothing found', () async {
      data.throws = true;
      await c.search('anything');
      expect(c.results, isEmpty);
      expect(c.searchMessage, isNotNull);
      expect(c.searching, isFalse);
    });

    test('typing waits, and only the last word is searched', () async {
      c.queryChanged('ja');
      c.queryChanged('jai');
      c.queryChanged('jaip');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(data.searches, ['jaip']);
    });

    test('one letter is not searched, and clearing the box clears the results', () async {
      c.queryChanged('j');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(data.searches, isEmpty);
      data.searchResults = [poi('A', 1, 1)];
      await c.search('abc');
      c.queryChanged('');
      expect(c.results, isEmpty);
    });

    test('a slow older answer never replaces a newer one', () async {
      data.delay = const Duration(milliseconds: 60);
      data.searchResults = [poi('OLD', 1, 1)];
      final first = c.search('first');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      data.delay = Duration.zero;
      data.searchResults = [poi('NEW', 2, 2)];
      await c.search('second');
      await first;
      expect(c.results.single.name, 'NEW');
    });
  });

  group('categories', () {
    test('a category shows its real places; tapping it again clears them', () async {
      data.nearbyResults = [poi('City Hospital', 10.01, 77.01), poi('Care Clinic', 10.02, 77.0)];
      await c.toggleCategory(MapCategory.hospitals);
      expect(c.category, MapCategory.hospitals);
      expect(c.pins.length, 2);
      await c.toggleCategory(MapCategory.hospitals);
      expect(c.category, isNull);
      expect(c.pins, isEmpty);
    });

    test('an empty category says so, by name', () async {
      await c.toggleCategory(MapCategory.charging);
      expect(c.searchMessage, 'No ev charging found around here.');
    });

    test('choosing another category replaces the first', () async {
      data.nearbyResults = [poi('A', 1, 1)];
      await c.toggleCategory(MapCategory.food);
      await c.toggleCategory(MapCategory.hotels);
      expect(c.category, MapCategory.hotels);
      expect(data.nearbyAsked, [MapCategory.food, MapCategory.hotels]);
    });

    test('panning far away offers "search this area", and it searches where the map is', () async {
      await c.start();
      data.nearbyResults = [poi('A', 10.001, 77.001)];
      await c.toggleCategory(MapCategory.food);
      c.viewMoved(const LatLng(10.0, 77.0), 15, byUser: true);
      expect(c.searchAreaOffered, isFalse);
      c.viewMoved(const LatLng(10.05, 77.05), 14, byUser: true);
      expect(c.searchAreaOffered, isTrue);
      data.nearbyResults = [poi('B', 10.05, 77.05)];
      await c.searchThisArea();
      expect(c.searchAreaOffered, isFalse);
      expect(c.results.single.name, 'B');
    });
  });

  group('choosing a place', () {
    test('selecting keeps the place and flies to it', () async {
      c.select(poi('Amber Fort', 26.98, 75.85));
      await settle();
      expect(c.selected!.name, 'Amber Fort');
      expect(cameras.whereType<CameraMove>().single.center, const LatLng(26.98, 75.85));
    });

    test('pressing on the map drops a pin, then names it', () async {
      data.describeResult = 'Park Road, Indiranagar, Bengaluru';
      final f = c.dropPin(const LatLng(12.97, 77.6));
      expect(c.selected!.name, 'Dropped pin');
      await f;
      expect(c.selected!.name, 'Park Road');
      expect(c.selected!.address, 'Park Road, Indiranagar, Bengaluru');
    });

    test('a pin with no name found stays "Dropped pin" with its coordinates', () async {
      await c.dropPin(const LatLng(12.97, 77.6));
      expect(c.selected!.name, 'Dropped pin');
      expect(c.selected!.address, '12.97000, 77.60000');
    });

    test('a slow name for an old pin does not rename a newer one', () async {
      data.delay = const Duration(milliseconds: 40);
      data.describeResult = 'Old Place';
      final f = c.dropPin(const LatLng(1, 1));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      c.select(poi('Real Place', 5, 5), fly: false);
      await f;
      expect(c.selected!.name, 'Real Place');
    });

    test('nonsense coordinates are ignored', () async {
      await c.dropPin(const LatLng(double.nan, 1));
      expect(c.selected, isNull);
    });
  });

  group('directions', () {
    setUp(() => data.routeResults = [northRoute()]);

    test('routes from where you are to the chosen place', () async {
      await c.start();
      c.select(poi('Fort', 10.02, 77));
      await c.directions();
      expect(c.routing, RoutingStatus.ready);
      expect(c.routes.length, 1);
      expect(c.selectedRoute!.label, 'Fastest');
      expect(data.routeAsks.single.$1, const LatLng(10, 77));
      expect(data.routeAsks.single.$2, const LatLng(10.02, 77));
    });

    test('without a position, directions say why instead of guessing a start', () async {
      loc.result = const LocationResult(LocationStatus.denied);
      c.select(poi('Fort', 10.02, 77));
      await c.directions();
      expect(c.routing, RoutingStatus.failed);
      expect(c.routingMessage, contains('permission'));
      expect(data.routeAsks, isEmpty);
    });

    test('no route measured is said plainly, and nothing is drawn', () async {
      await c.start();
      data.routeResults = [];
      c.select(poi('Fort', 10.02, 77));
      await c.directions();
      expect(c.routing, RoutingStatus.failed);
      expect(c.routes, isEmpty);
    });

    test('a failing service does not throw', () async {
      await c.start();
      data.throws = true;
      c.select(poi('Fort', 10.02, 77));
      await c.directions();
      expect(c.routing, RoutingStatus.failed);
    });

    test('changing how you travel asks again', () async {
      await c.start();
      c.select(poi('Fort', 10.02, 77));
      await c.directions();
      await c.setMode(NavMode.walk);
      expect(data.routeAsks.map((a) => a.$3), [NavMode.drive, NavMode.walk]);
    });

    test('choosing another place clears the old routes', () async {
      await c.start();
      c.select(poi('Fort', 10.02, 77));
      await c.directions();
      c.select(poi('Palace', 10.03, 77));
      expect(c.routes, isEmpty);
      expect(c.routing, RoutingStatus.idle);
    });

    test('an old answer never lands on a newer choice', () async {
      await c.start();
      data.delay = const Duration(milliseconds: 40);
      c.select(poi('Fort', 10.02, 77));
      final f = c.directions();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      c.select(poi('Palace', 10.03, 77));
      await f;
      expect(c.routes, isEmpty);
    });

    test('picking one of several routes', () async {
      await c.start();
      final a = northRoute();
      final b = MapRoute(id: 'alt', label: 'Alternative', mode: NavMode.drive, points: a.points, distanceM: a.distanceM * 1.3, durationS: 900);
      data.routeResults = [a, b];
      c.select(poi('Fort', 10.02, 77));
      await c.directions();
      c.selectRoute('alt');
      expect(c.selectedRoute!.label, 'Alternative');
      c.selectRoute('nope');
      expect(c.selectedRouteId, 'alt');
    });
  });

  group('navigating', () {
    Future<void> setOff() async {
      await c.start();
      data.routeResults = [northRoute()];
      c.select(poi('Fort', 10.02, 77));
      await c.directions();
      await c.startNavigation();
    }

    test('progress follows the position, and the camera follows you', () async {
      await setOff();
      expect(c.navigating, isTrue);
      final before = cameras.length;
      loc.positions.add(const UserFix(point: LatLng(10.005, 77)));
      await settle();
      expect(c.progress!.remainingM, closeTo(1665, 20));
      expect(c.progress!.next?.text, 'Turn left onto Park Road');
      expect(cameras.length, greaterThan(before));
    });

    test('once you pan the map away it stops following until you recenter', () async {
      await setOff();
      await settle();
      c.viewMoved(const LatLng(10.1, 77.1), 15, byUser: true);
      expect(c.following, isFalse);
      final before = cameras.length;
      loc.positions.add(const UserFix(point: LatLng(10.006, 77)));
      await settle();
      expect(cameras.length, before);
      await c.recenter();
      expect(c.following, isTrue);
    });

    test('arriving ends the guidance', () async {
      await setOff();
      loc.positions.add(const UserFix(point: LatLng(10.0199, 77)));
      await settle();
      expect(c.progress!.arrived, isTrue);
    });

    test('leaving the road asks for a new route from where you are, once per spell', () async {
      var t = DateTime(2026, 1, 1, 12);
      final d = LiveMapController(data: data, location: loc, now: () => t);
      addTearDown(d.dispose);
      await d.start();
      data.routeResults = [northRoute()];
      d.select(poi('Fort', 10.02, 77));
      await d.directions();
      await d.startNavigation();
      final asked = data.routeAsks.length;

      data.routeResults = [northRoute(steps: 10)];
      loc.positions.add(const UserFix(point: LatLng(10.005, 77.004))); // ~440 m off
      await settle();
      await settle();
      expect(data.routeAsks.length, asked + 1);
      expect(d.selectedRoute!.geometry.points.length, 11);

      loc.positions.add(const UserFix(point: LatLng(10.005, 77.005)));
      await settle();
      expect(data.routeAsks.length, asked + 1, reason: 'throttled');
      t = t.add(const Duration(seconds: 20));
    });

    test('stopping leaves the routes on screen and stops listening', () async {
      await setOff();
      await c.stopNavigation();
      expect(c.navigating, isFalse);
      expect(c.routes, isNotEmpty);
      loc.positions.add(const UserFix(point: LatLng(10.005, 77)));
      await settle();
      expect(c.progress, isNull);
    });

    test('nothing can be selected or changed while navigating', () async {
      await setOff();
      c.select(poi('Other', 1, 1));
      expect(c.selected!.name, 'Fort');
      c.clearSelection();
      expect(c.selected, isNotNull);
      await c.dropPin(const LatLng(2, 2));
      expect(c.selected!.name, 'Fort');
    });
  });

  group('a day of the trip', () {
    const stops = [
      TripStop(name: 'Amber Fort', point: LatLng(10.0004, 77), when: '9:30 AM', refId: 'a'),
      TripStop(name: 'Hawa Mahal', point: LatLng(10.02, 77), when: '1:00 PM', refId: 'b'),
      TripStop(name: 'City Palace', point: LatLng(10.04, 77), when: '4:00 PM', refId: 'c'),
    ];
    const day = TripMapRequest(title: 'Day 1 · Old city', stops: stops);

    test('the stops are shown in order and the first is next', () async {
      await c.start();
      await c.showTrip(day);
      expect(c.tripActive, isTrue);
      expect(c.tripStops.map((s) => s.name), ['Amber Fort', 'Hawa Mahal', 'City Palace']);
      expect(c.nextStopIndex, 0);
      await settle();
      expect(cameras.whereType<FitPlaces>().last.points.length, 4, reason: 'you and the three stops');
    });

    test('a close stop is walked to, a far one is driven to', () async {
      await c.start();
      data.routeResults = [northRoute()];
      await c.showTrip(day);
      await c.navigateToStop(0);
      expect(data.routeAsks.last.$3, NavMode.walk);
      expect(c.selected!.name, 'Amber Fort');
      c.closeDirections();
      c.clearSelection();
      await c.navigateToStop(2);
      expect(data.routeAsks.last.$3, NavMode.drive);
    });

    test('asking to navigate on showing sets off for that stop', () async {
      await c.start();
      data.routeResults = [northRoute()];
      await c.showTrip(const TripMapRequest(title: 'Day 1', stops: stops, navigateTo: 1));
      expect(c.selected!.name, 'Hawa Mahal');
      expect(c.routing, RoutingStatus.ready);
    });

    test('arriving marks the stop done, and the next one is offered', () async {
      await c.start();
      data.routeResults = [northRoute()];
      await c.showTrip(day);
      await c.navigateToNextStop();
      await c.startNavigation();
      loc.positions.add(const UserFix(point: LatLng(10.0199, 77)));
      await settle();
      expect(c.progress!.arrived, isTrue);
      await c.stopNavigation(keepRoutes: false);
      expect(c.visitedStops, {0});
      expect(c.nextStopIndex, 1);
      expect(c.selected, isNull, reason: 'back to the day');
    });

    test('a stop with nonsense coordinates is left out, and an empty day shows nothing', () async {
      await c.showTrip(const TripMapRequest(title: 'x', stops: [TripStop(name: 'bad', point: LatLng(double.nan, 1))]));
      expect(c.tripActive, isFalse);
      await c.navigateToStop(5);
      expect(c.selected, isNull);
    });

    test('hiding the trip clears it', () async {
      await c.showTrip(day);
      c.clearTrip();
      expect(c.tripActive, isFalse);
    });
  });

  group('spoken directions', () {
    Future<(LiveMapController, List<String>)> ready({bool voice = true}) async {
      final said = <String>[];
      final d = LiveMapController(data: data, location: loc, speak: said.add);
      addTearDown(d.dispose);
      d.voiceGuidance = voice;
      await d.start();
      data.routeResults = [northRoute()];
      d.select(poi('Amber Fort', 10.02, 77));
      await d.directions();
      await d.startNavigation();
      return (d, said);
    }

    test('the trip is announced, then each turn as it nears, then arrival', () async {
      final (d, said) = await ready();
      expect(said.single, startsWith('Starting navigation to Amber Fort.'));
      loc.positions.add(const UserFix(point: LatLng(10.0075, 77))); // about 167 m before the 1000 m turn
      await settle();
      expect(said.last, 'In 150 metres, turn left onto Park Road');
      loc.positions.add(const UserFix(point: LatLng(10.0076, 77)));
      await settle();
      expect(said.length, 2, reason: 'a turn is announced once at that distance');
      loc.positions.add(const UserFix(point: LatLng(10.0088, 77))); // a few metres before it
      await settle();
      expect(said.last, 'Turn left onto Park Road');
      loc.positions.add(const UserFix(point: LatLng(10.0199, 77)));
      await settle();
      expect(said.last, 'You have arrived at Amber Fort.');
      final n = said.length;
      loc.positions.add(const UserFix(point: LatLng(10.0199, 77.00001)));
      await settle();
      expect(said.length, n, reason: 'arrival is said once');
      expect(d.progress!.arrived, isTrue);
    });

    test('muting says nothing', () async {
      final (d, said) = await ready(voice: false);
      loc.positions.add(const UserFix(point: LatLng(10.0075, 77)));
      await settle();
      expect(said, isEmpty);
      d.setVoiceGuidance(true);
      expect(d.voiceGuidance, isTrue);
    });

    test('distances are said the way a person says them', () {
      expect(distanceWords(30), '30 metres');
      expect(distanceWords(190), '200 metres');
      expect(distanceWords(640), '650 metres');
      expect(distanceWords(1000), '1 kilometre');
      expect(distanceWords(1500), '1.5 kilometres');
      expect(distanceWords(12400), '12 kilometres');
      expect(distanceWords(double.nan), '');
    });
  });

  group('the map view', () {
    test('traffic is only on when there is a traffic source', () {
      c.setTraffic(true);
      expect(c.traffic, isFalse);
      data.traffic = 'https://tiles/{z}/{x}/{y}.png';
      c.setTraffic(true);
      expect(c.traffic, isTrue);
    });

    test('the style changes and tells listeners', () {
      var n = 0;
      c.addListener(() => n++);
      c.setStyle(MapStyle.dark);
      c.setStyle(MapStyle.dark);
      expect(c.style, MapStyle.dark);
      expect(n, 1);
    });

    test('disposing during a request is harmless', () async {
      data.delay = const Duration(milliseconds: 30);
      final d = LiveMapController(data: data, location: loc);
      final f = d.search('abc');
      d.dispose();
      await f;
    });
  });
}

class _ThrowingLocation extends ScriptedLocation {
  @override
  Future<LocationResult> request() => throw StateError('no');
}
