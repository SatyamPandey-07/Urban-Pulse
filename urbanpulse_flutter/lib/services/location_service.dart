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

  /// Reverse-geocodes a fix to a place (the `Geocoder` locality /
  /// subAdminArea / adminArea chain from `YatriAiFragment`, plus the
  /// region/country line the app header shows). Returns null if nothing
  /// resolves, so callers can show an honest "unavailable" rather than a
  /// made-up city.
  Future<ResolvedPlace?> resolvePlace(double lat, double lon) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lon);
      if (placemarks.isEmpty) return null;
      final place = placemarks.first;

      final city = _firstNonEmpty([
        place.locality,
        place.subAdministrativeArea,
        place.administrativeArea,
      ]);
      if (city == null) return null;

      final region = [place.administrativeArea, place.country]
          .map((v) => v?.trim())
          .where((v) => v != null && v.isNotEmpty && v != city)
          .join(', ');

      return ResolvedPlace(city: city, region: region.isEmpty ? null : region);
    } catch (_) {
      return null;
    }
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final candidate in candidates) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}

/// A reverse-geocoded position.
class ResolvedPlace {
  const ResolvedPlace({required this.city, required this.region});

  final String city;
  final String? region;
}
