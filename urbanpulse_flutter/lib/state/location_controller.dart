import 'package:flutter/foundation.dart';

import '../models/saved_place.dart';
import '../repositories/saved_places_repository.dart';

import '../services/location_service.dart';

/// Where the traveler actually is, resolved once and shared by every screen.
///
/// This replaces the per-screen copies of the "ask for permission, read the fix,
/// reverse-geocode it" dance — and the hardcoded `Mumbai` / `19.0760, 72.8777`
/// constants the Kotlin screens fell back to — with one resolved position the UI
/// can also render an honest pending/unavailable state for.
class LocationController extends ChangeNotifier {
  /// [places] adds the traveller's saved addresses: when one is chosen the whole
  /// app works from it instead of the device position.
  LocationController(this._service, {SavedPlacesRepository? places}) : _places = places {
    _places?.addListener(_placesChanged);
  }

  final LocationService _service;
  final SavedPlacesRepository? _places;

  void _placesChanged() => notifyListeners();

  /// The saved address in use, or null when the app follows the device.
  SavedPlace? get chosen => _places?.active;

  bool get usingSavedPlace => chosen != null;

  /// The device's own position and place name, whatever address is chosen.
  double? get gpsLatitude => _latitude;
  double? get gpsLongitude => _longitude;
  String? get gpsCity => _city;

  /// Back to following the device, and reads a fresh position.
  Future<void> useCurrentLocation() async {
    await _places?.setActive(null);
    await resolve(force: true);
  }

  /// Works from a saved address.
  Future<void> useSavedPlace(SavedPlace place) async {
    await _places?.setActive(place);
  }

  @override
  void dispose() {
    _places?.removeListener(_placesChanged);
    super.dispose();
  }

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
  bool get hasFix => chosen != null || (_latitude != null && _longitude != null);

  double? get latitude => chosen?.lat ?? _latitude;

  double? get longitude => chosen?.lon ?? _longitude;

  String? get city {
    final c = chosen;
    if (c != null && c.city.isNotEmpty) return c.city;
    return c != null ? null : _city;
  }

  String? get region => chosen != null ? chosen!.address : _region;

  /// What the header shows: the real place name, or an honest status.
  String get displayTitle {
    final c = chosen;
    if (c != null) return c.label;
    return _city ?? (isResolving ? 'Locating…' : 'Location off');
  }

  String get displaySubtitle {
    final c = chosen;
    if (c != null) return c.address.isNotEmpty ? c.address : c.city;
    if (_region != null) return _region!;
    if (isResolving) return 'Reading your position…';
    if (hasFix) return 'Position found, place name unavailable';
    return 'Enable location for live data';
  }

  /// Coordinates for a query, falling back to the app's documented city-center
  /// default only when no real fix is available.
  (double, double) get coordinatesOrDefault => (
    latitude ?? LocationService.defaultLat,
    longitude ?? LocationService.defaultLon,
  );

  /// Origin city for trip planning. Null until a real place name is known, so
  /// callers can decide rather than silently claiming "Mumbai".
  String? get originCity => city;

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
