import 'package:flutter/foundation.dart';

import '../services/location_service.dart';

/// Where the traveler actually is, resolved once and shared by every screen.
///
/// This replaces the per-screen copies of the "ask for permission, read the fix,
/// reverse-geocode it" dance — and the hardcoded `Mumbai` / `19.0760, 72.8777`
/// constants the Kotlin screens fell back to — with one resolved position the UI
/// can also render an honest pending/unavailable state for.
class LocationController extends ChangeNotifier {
  LocationController(this._service);

  final LocationService _service;

  double? _latitude;
  double? _longitude;
  String? _city;
  String? _region;
  bool _hasAttempted = false;

  /// The in-flight resolve, so concurrent callers await the same lookup instead
  /// of racing past it and reading the fallback coordinates.
  Future<void>? _inFlight;

  bool get isResolving => _inFlight != null;

  /// True once a real device fix has been read.
  bool get hasFix => _latitude != null && _longitude != null;

  double? get latitude => _latitude;

  double? get longitude => _longitude;

  String? get city => _city;

  String? get region => _region;

  /// What the header shows: the real place name, or an honest status.
  String get displayTitle =>
      _city ?? (isResolving ? 'Locating…' : 'Location off');

  String get displaySubtitle {
    if (_region != null) return _region!;
    if (isResolving) return 'Reading your position…';
    if (hasFix) return 'Position found, place name unavailable';
    return 'Enable location for live data';
  }

  /// Coordinates for a query, falling back to the app's documented city-center
  /// default only when no real fix is available.
  (double, double) get coordinatesOrDefault => (
    _latitude ?? LocationService.defaultLat,
    _longitude ?? LocationService.defaultLon,
  );

  /// Origin city for trip planning. Null until a real place name is known, so
  /// callers can decide rather than silently claiming "Mumbai".
  String? get originCity => _city;

  /// Resolves once per session unless [force] is set. Concurrent callers share
  /// the same lookup and all await its completion, so none of them races past it
  /// and reads the fallback coordinates.
  Future<void> resolve({bool force = false}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    if (_hasAttempted && !force) return Future.value();
    return _inFlight = _resolve().whenComplete(() {
      _inFlight = null;
      notifyListeners();
    });
  }

  Future<void> _resolve() async {
    _hasAttempted = true;
    notifyListeners();

    final position = await _service.currentPosition();
    if (position == null) return;

    _latitude = position.latitude;
    _longitude = position.longitude;
    final place = await _service.resolvePlace(
      position.latitude,
      position.longitude,
    );
    _city = place?.city;
    _region = place?.region;
  }
}
