import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// One place for the runtime location-permission dance and the "last known, else
/// current" fix that `LiveMapFragment`, `YatriAiFragment` and
/// `GreenRoutePlannerActivity` each re-implemented against
/// `FusedLocationProviderClient`.
class LocationService {
  /// Mumbai city-center, the same default the Kotlin screens started from.
  static const defaultLat = 19.0760;
  static const defaultLon = 72.8777;

  /// Requests permission if needed and returns a fix, or null when the user
  /// declined, location services are off, or no fix is available.
  Future<Position?> currentPosition() async {
    if (!await ensurePermission()) return null;
    try {
      // Prefer the cached fix (the Kotlin code used `lastLocation`), then fall
      // back to an active read.
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// Reverse-geocodes a fix to a city name (the `Geocoder` locality /
  /// subAdminArea / adminArea chain from `YatriAiFragment`). Returns null if
  /// nothing resolves, so callers keep their previous value.
  Future<String?> resolveCityName(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isEmpty) return null;
      final place = placemarks.first;
      final detected = place.locality?.isNotEmpty == true
          ? place.locality
          : place.subAdministrativeArea?.isNotEmpty == true
          ? place.subAdministrativeArea
          : place.administrativeArea;
      return (detected?.trim().isNotEmpty ?? false) ? detected!.trim() : null;
    } catch (_) {
      return null;
    }
  }
}
