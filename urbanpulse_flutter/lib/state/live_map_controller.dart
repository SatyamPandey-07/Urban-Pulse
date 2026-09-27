import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/live_city_data.dart';
import '../models/map_category.dart';
import '../models/map_route.dart';
import '../services/live_location.dart';
import '../services/live_map_data.dart';

enum MapStyle { standard, dark, satellite }

enum RoutingStatus { idle, loading, ready, failed }

/// What the map view is asked to do with its camera.
sealed class CameraRequest {
  const CameraRequest();
}

class CameraMove extends CameraRequest {
  const CameraMove(this.center, {this.zoom});

  final LatLng center;
  final double? zoom;
}

class FitPlaces extends CameraRequest {
  const FitPlaces(this.points);

  final List<LatLng> points;
}

/// The state and behaviour of the Live Map: where you are, what you searched,
/// which place is chosen, the routes to it, and turn-by-turn progress once you
/// set off. The map widget only draws this and reports what the user does to it.
class LiveMapController extends ChangeNotifier {
  LiveMapController({required this.data, required this.location, Duration searchDelay = const Duration(milliseconds: 400), DateTime Function()? now})
    : _searchDelay = searchDelay,
      _now = now ?? DateTime.now;

  final LiveMapData data;
  final LiveLocation location;
  final Duration _searchDelay;
  final DateTime Function() _now;

  static const _defaultCenter = LatLng(20.5937, 78.9629); // the middle of India, until a position is known

  final _cameras = StreamController<CameraRequest>.broadcast();
  Stream<CameraRequest> get cameraRequests => _cameras.stream;

  // --- where the traveller is ---------------------------------------------------
  UserFix? user;
  LocationStatus locationStatus = LocationStatus.unknown;
  bool locating = false;

  // --- the map view ---------------------------------------------------------------
  MapStyle style = MapStyle.standard;
  bool traffic = false;
  LatLng viewCenter = _defaultCenter;
  double viewZoom = 5;

  // --- search ---------------------------------------------------------------------
  String query = '';
  bool searching = false;
  List<LivePoiResult> results = const [];
  MapCategory? category;

  /// Why the last search showed nothing, if it did.
  String? searchMessage;

  /// Where the results were searched from, to offer "Search this area".
  LatLng? _searchedAt;
  bool searchAreaOffered = false;

  // --- the chosen place -------------------------------------------------------------
  LivePoiResult? selected;

  // --- directions ---------------------------------------------------------------------
  NavMode mode = NavMode.drive;
  List<MapRoute> routes = const [];
  String? selectedRouteId;
  RoutingStatus routing = RoutingStatus.idle;
  String? routingMessage;

  // --- navigation -----------------------------------------------------------------------
  bool navigating = false;
  bool following = true;
  NavProgress? progress;

  /// Which set-off this is, so a stale reroute never overwrites a newer one.
  int _navToken = 0;
  DateTime? _lastReroute;
  bool _rerouting = false;
  StreamSubscription<UserFix>? _watch;

  Timer? _debounce;
  int _searchToken = 0;
  int _routeToken = 0;
  bool _disposed = false;

  MapRoute? get selectedRoute {
    for (final r in routes) {
      if (r.id == selectedRouteId) return r;
    }
    return routes.isEmpty ? null : routes.first;
  }

  /// Places shown as pins: a category, or the search results.
  List<LivePoiResult> get pins => results;

  bool get hasFix => user != null;

  /// Where searches should start: your position, or where the map is looking.
  LatLng get searchOrigin => user?.point ?? viewCenter;

  // ------------------------------------------------------------------------------------
  // location

  Future<void> start() => locate();

  Future<void> locate({bool recenter = true, double zoom = 15.5}) async {
    if (locating) return;
    locating = true;
    _notify();
    LocationResult r;
    try {
      r = await location.request();
    } catch (_) {
      r = const LocationResult(LocationStatus.unavailable);
    }
    locating = false;
    locationStatus = r.status;
    if (r.fix != null) {
      user = r.fix;
      if (recenter) _camera(CameraMove(r.fix!.point, zoom: zoom));
    }
    _notify();
  }

  Future<void> openLocationSettings() => location.openSettings(locationStatus);

  /// Puts the camera back on you, and (while navigating) keeps it there.
  Future<void> recenter() async {
    following = true;
    final u = user;
    if (u != null) {
      _camera(CameraMove(u.point, zoom: navigating ? 17 : 15.5));
      _notify();
      return;
    }
    await locate();
  }

  // ------------------------------------------------------------------------------------
  // the view

  void viewMoved(LatLng center, double zoom, {required bool byUser}) {
    viewCenter = center;
    viewZoom = zoom;
    if (byUser && navigating && following) {
      following = false;
      _notify();
      return;
    }
    final from = _searchedAt;
    if (from != null && (category != null || query.trim().isNotEmpty) && selected == null && routes.isEmpty) {
      final far = const Distance().as(LengthUnit.Meter, from, center) > 1500;
      if (far != searchAreaOffered) {
        searchAreaOffered = far;
        _notify();
      }
    }
  }

  void setStyle(MapStyle s) {
    if (style == s) return;
    style = s;
    _notify();
  }

  void setTraffic(bool on) {
    if (traffic == on) return;
    traffic = on && data.trafficTiles != null;
    _notify();
  }

  // ------------------------------------------------------------------------------------
  // search

  void queryChanged(String text) {
    query = text;
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      _searchToken++;
      searching = false;
      searchMessage = null;
      if (category == null) results = const [];
      _notify();
      return;
    }
    if (q.length < 2) {
      _notify();
      return;
    }
    searching = true;
    _notify();
    _debounce = Timer(_searchDelay, () => search(q));
  }

  Future<void> search(String text, {bool fit = true}) async {
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) return;
    query = text;
    category = null;
    final token = ++_searchToken;
    searching = true;
    searchMessage = null;
    _notify();
    final origin = searchOrigin;
    List<LivePoiResult> found;
    try {
      found = await data.search(q, origin);
    } catch (_) {
      found = const [];
    }
    if (_disposed || token != _searchToken) return;
    searching = false;
    results = found;
    _searchedAt = origin;
    searchAreaOffered = false;
    searchMessage = found.isEmpty ? 'No places matched “$q”. Try another spelling or a nearby landmark.' : null;
    _notify();
    if (fit && found.isNotEmpty) _fit([for (final p in found) LatLng(p.lat, p.lon)]);
  }

  Future<void> toggleCategory(MapCategory c) async {
    if (category == c) {
      clearResults();
      return;
    }
    _debounce?.cancel();
    category = c;
    query = '';
    final token = ++_searchToken;
    searching = true;
    searchMessage = null;
    selected = null;
    _clearRoutes();
    _notify();
    final origin = viewCenterOrUser();
    List<LivePoiResult> found;
    try {
      found = await data.nearby(c, origin);
    } catch (_) {
      found = const [];
    }
    if (_disposed || token != _searchToken) return;
    searching = false;
    results = found;
    _searchedAt = origin;
    searchAreaOffered = false;
    searchMessage = found.isEmpty ? 'No ${c.label.toLowerCase()} found around here.' : null;
    _notify();
    if (found.isNotEmpty) _fit([origin, ...found.take(12).map((p) => LatLng(p.lat, p.lon))]);
  }

  /// The user's position when the map is still looking near it, else the view.
  LatLng viewCenterOrUser() {
    final u = user;
    if (u == null) return viewCenter;
    return const Distance().as(LengthUnit.Meter, u.point, viewCenter) < 3000 ? u.point : viewCenter;
  }

  Future<void> searchThisArea() async {
    final c = category;
    final q = query.trim();
    searchAreaOffered = false;
    if (c != null) {
      final token = ++_searchToken;
      searching = true;
      searchMessage = null;
      _notify();
      final origin = viewCenter;
      List<LivePoiResult> found;
      try {
        found = await data.nearby(c, origin);
      } catch (_) {
        found = const [];
      }
      if (_disposed || token != _searchToken) return;
      searching = false;
      results = found;
      _searchedAt = origin;
      searchMessage = found.isEmpty ? 'No ${c.label.toLowerCase()} found in this area.' : null;
      _notify();
    } else if (q.isNotEmpty) {
      final token = ++_searchToken;
      searching = true;
      _notify();
      final origin = viewCenter;
      List<LivePoiResult> found;
      try {
        found = await data.search(q, origin);
      } catch (_) {
        found = const [];
      }
      if (_disposed || token != _searchToken) return;
      searching = false;
      results = found;
      _searchedAt = origin;
      searchMessage = found.isEmpty ? 'No places matched “$q” in this area.' : null;
      _notify();
    }
  }

  void clearResults() {
    _debounce?.cancel();
    _searchToken++;
    category = null;
    query = '';
    results = const [];
    searching = false;
    searchMessage = null;
    searchAreaOffered = false;
    _searchedAt = null;
    _notify();
  }

  // ------------------------------------------------------------------------------------
  // the chosen place

  void select(LivePoiResult place, {bool fly = true}) {
    if (navigating) return;
    selected = place;
    _clearRoutes();
    _notify();
    if (fly) _camera(CameraMove(LatLng(place.lat, place.lon), zoom: viewZoom < 15 ? 16 : null));
  }

  /// A place chosen by pressing on the map.
  Future<void> dropPin(LatLng at) async {
    if (navigating) return;
    if (!at.latitude.isFinite || !at.longitude.isFinite) return;
    final u = user;
    final pin = LivePoiResult(
      name: 'Dropped pin',
      address: '${at.latitude.toStringAsFixed(5)}, ${at.longitude.toStringAsFixed(5)}',
      distanceMeters: u == null ? 0 : const Distance().as(LengthUnit.Meter, u.point, at),
      lat: at.latitude,
      lon: at.longitude,
      category: 'pin',
    );
    select(pin, fly: false);
    String? name;
    try {
      name = await data.describe(at);
    } catch (_) {}
    final cur = selected;
    if (_disposed || name == null || cur == null || cur.lat != pin.lat || cur.lon != pin.lon || cur.category != 'pin') return;
    selected = LivePoiResult(name: name.split(',').first.trim().isEmpty ? 'Dropped pin' : name.split(',').first.trim(), address: name, distanceMeters: pin.distanceMeters, lat: pin.lat, lon: pin.lon, category: 'pin');
    _notify();
  }

  void clearSelection() {
    if (navigating) return;
    selected = null;
    _clearRoutes();
    _notify();
  }

  // ------------------------------------------------------------------------------------
  // directions

  void _clearRoutes() {
    _routeToken++;
    routes = const [];
    selectedRouteId = null;
    routing = RoutingStatus.idle;
    routingMessage = null;
  }

  Future<void> directions({NavMode? withMode}) async {
    final dest = selected;
    if (dest == null || navigating) return;
    if (withMode != null) mode = withMode;
    final token = ++_routeToken;
    routing = RoutingStatus.loading;
    routingMessage = null;
    routes = const [];
    selectedRouteId = null;
    _notify();

    if (user == null) await locate(recenter: false);
    if (_disposed || token != _routeToken) return;
    final from = user?.point;
    if (from == null) {
      routing = RoutingStatus.failed;
      routingMessage = switch (locationStatus) {
        LocationStatus.serviceOff => 'Location is switched off. Turn it on to get directions from where you are.',
        LocationStatus.denied || LocationStatus.deniedForever => 'Location permission is needed to get directions from where you are.',
        _ => 'Your position is not available yet, so directions cannot start from where you are.',
      };
      _notify();
      return;
    }

    List<MapRoute> found;
    try {
      found = await data.routes(from, LatLng(dest.lat, dest.lon), mode);
    } catch (_) {
      found = const [];
    }
    if (_disposed || token != _routeToken) return;
    if (found.isEmpty) {
      routing = RoutingStatus.failed;
      routingMessage = 'No route could be measured right now. Check your connection and try again.';
      _notify();
      return;
    }
    routes = found;
    selectedRouteId = found.first.id;
    routing = RoutingStatus.ready;
    _notify();
    _fit([from, ...found.expand((r) => r.points)]);
  }

  Future<void> setMode(NavMode m) async {
    if (m == mode && routing != RoutingStatus.failed) return;
    await directions(withMode: m);
  }

  void selectRoute(String id) {
    if (navigating || routes.every((r) => r.id != id)) return;
    selectedRouteId = id;
    _notify();
  }

  // ------------------------------------------------------------------------------------
  // navigation

  Future<void> startNavigation() async {
    final route = selectedRoute;
    if (route == null || navigating) return;
    navigating = true;
    following = true;
    final token = ++_navToken;
    _lastReroute = null;
    final u = user;
    progress = u == null ? null : NavProgress.of(route, u.point);
    _notify();
    if (u != null) _camera(CameraMove(u.point, zoom: 17));
    await _watch?.cancel();
    _watch = location.watch(distanceFilterM: 5).listen(
      (fix) {
        if (token == _navToken) _onFix(fix);
      },
      onError: (_) {},
    );
  }

  /// A new position while navigating (public so the device stream and tests use one path).
  void onFix(UserFix fix) => _onFix(fix);

  void _onFix(UserFix fix) {
    if (_disposed) return;
    user = fix;
    locationStatus = LocationStatus.ok;
    final route = selectedRoute;
    if (!navigating || route == null) {
      _notify();
      return;
    }
    final p = NavProgress.of(route, fix.point);
    progress = p;
    if (p.arrived) {
      _watch?.cancel();
      _watch = null;
      _notify();
      return;
    }
    if (following) _camera(CameraMove(fix.point, zoom: viewZoom < 16.5 ? 17 : null));
    _notify();
    if (p.offRouteM > 60) unawaited(_reroute(fix));
  }

  Future<void> _reroute(UserFix fix) async {
    final dest = selected;
    if (dest == null || _rerouting) return;
    final now = _now();
    final last = _lastReroute;
    if (last != null && now.difference(last) < const Duration(seconds: 15)) return;
    _lastReroute = now;
    _rerouting = true;
    final token = _navToken;
    try {
      final found = await data.routes(fix.point, LatLng(dest.lat, dest.lon), mode);
      if (_disposed || token != _navToken || !navigating || found.isEmpty) return;
      routes = found;
      selectedRouteId = found.first.id;
      progress = NavProgress.of(found.first, fix.point);
      _notify();
    } catch (_) {
      // keep the old route; the next position tries again
    } finally {
      _rerouting = false;
    }
  }

  Future<void> stopNavigation({bool keepRoutes = true}) async {
    if (!navigating && _watch == null) return;
    _navToken++;
    navigating = false;
    following = true;
    progress = null;
    await _watch?.cancel();
    _watch = null;
    if (!keepRoutes) _clearRoutes();
    _notify();
  }

  /// Leaves directions and goes back to the chosen place.
  void closeDirections() {
    if (navigating) return;
    _clearRoutes();
    _notify();
  }

  // ------------------------------------------------------------------------------------

  void _fit(List<LatLng> points) => _camera(FitPlaces(points));

  void _camera(CameraRequest r) {
    if (_disposed) return;
    // The controller knows where the camera is going before the map has moved.
    if (r is CameraMove) {
      viewCenter = r.center;
      if (r.zoom != null) viewZoom = r.zoom!;
    }
    _cameras.add(r);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _watch?.cancel();
    _cameras.close();
    super.dispose();
  }
}
