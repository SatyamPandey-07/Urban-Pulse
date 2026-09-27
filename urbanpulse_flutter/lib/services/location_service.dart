import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

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
      // back to an active read. Browsers have no cached fix to ask for.
      if (!kIsWeb) {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return last;
      }
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
    if (kIsWeb) return _resolveOnWeb(lat, lon);
    try {
      final placemarks =
          await Geocoding().placemarkFromCoordinates(lat, lon);
      if (placemarks.isEmpty) return null;
      final place = placemarks.first;

      final city = _firstNonEmpty([
        place.locality,
        place.subAdministrativeArea,
        place.administrativeArea,
      ]);
      if (city == null) return null;

      final regionList = <String>[];
      final admin = place.administrativeArea?.trim();
      if (admin != null && admin.isNotEmpty && admin != city) {
        regionList.add(admin);
      }
      final country = place.country?.trim();
      if (country != null && country.isNotEmpty && country != city) {
        regionList.add(country);
      }
      final region = regionList.join(', ');

      return ResolvedPlace(city: city, region: region.isEmpty ? null : region);
    } catch (_) {
      return null;
    }
  }

  /// Browsers have no platform geocoder: OpenStreetMap's Nominatim answers
  /// the same question (and allows requests from web pages).
  Future<ResolvedPlace?> _resolveOnWeb(double lat, double lon) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '$lat',
        'lon': '$lon',
        // Street-level detail names the city itself ("Jaipur"); coarser zooms
        // name the civic body ("Jaipur Municipal Corporation").
        'zoom': '14',
        'addressdetails': '1',
        'accept-language': 'en',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final address = (jsonDecode(res.body) as Map<String, dynamic>)['address'];
      if (address is! Map<String, dynamic>) return null;
      String? at(String k) => address[k] is String ? _tidy(address[k] as String) : null;
      final city = _firstNonEmpty([at('city'), at('town'), at('village'), at('state_district'), at('county'), at('state')]);
      if (city == null) return null;
      final region = [
        for (final r in [at('state'), at('country')])
          if (r != null && r.trim().isNotEmpty && r.trim() != city) r.trim(),
      ].join(', ');
      return ResolvedPlace(city: city, region: region.isEmpty ? null : region);
    } catch (_) {
      return null;
    }
  }

  /// "Pune Municipal Corporation" -> "Pune", "Jaipur Tehsil" -> "Jaipur".
  static String _tidy(String name) => name
      .replaceAll(RegExp(r'\s+(Municipal Corporation|Municipal Council|Nagar Nigam|Nagar Palika|Cantonment Board|Tehsil|Taluka|District)$', caseSensitive: false), '')
      .trim();

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
