import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/saved_place.dart';
import 'location_service.dart';
import 'tomtom_service.dart';

typedef SuggestFn = Future<List<PlaceSuggestion>> Function(String query, double? nearLat, double? nearLon);
typedef CityFn = Future<String?> Function(double lat, double lon);

/// Completions for an address or place typed by the traveller, and the city a
/// point lies in. Real services only (TomTom when a key exists, else
/// OpenStreetMap); nothing is made up and every failure is an empty answer.
class PlaceSuggestions {
  PlaceSuggestions({SuggestFn? suggest, CityFn? cityOf, http.Client? client})
    : _client = client ?? http.Client(),
      _suggest = suggest,
      _cityOf = cityOf;

  final http.Client _client;
  final SuggestFn? _suggest;
  final CityFn? _cityOf;
  final Map<String, List<PlaceSuggestion>> _cache = {};

  Future<List<PlaceSuggestion>> suggest(String query, {double? nearLat, double? nearLon}) async {
    final q = query.trim();
    if (q.length < 2 || q.length > 120) return const [];
    final key = '${q.toLowerCase()}|${nearLat?.toStringAsFixed(1)}|${nearLon?.toStringAsFixed(1)}';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final found = await (_suggest ?? _defaultSuggest)(q, nearLat, nearLon);
      if (found.isNotEmpty) _cache[key] = found;
      return found;
    } catch (_) {
      return const [];
    }
  }

  Future<List<PlaceSuggestion>> _defaultSuggest(String q, double? lat, double? lon) async {
    final results = await TomTomService.searchPlacesBounded(q, lat: lat ?? LocationService.defaultLat, lon: lon ?? LocationService.defaultLon, radiusKm: lat == null ? 400 : 120, limit: 7);
    final seen = <String>{};
    final out = <PlaceSuggestion>[];
    for (final r in results) {
      final title = r.name.trim();
      if (title.isEmpty) continue;
      var sub = r.address.trim();
      if (sub.toLowerCase().startsWith(title.toLowerCase())) sub = sub.substring(title.length).replaceFirst(RegExp(r'^[,\s]+'), '');
      if (!seen.add('$title|$sub')) continue;
      out.add(PlaceSuggestion(title: title, subtitle: sub, lat: r.lat, lon: r.lon));
    }
    return out;
  }

  /// The city a point lies in: what a trip starts from.
  Future<String?> cityOf(double lat, double lon) async {
    try {
      if (_cityOf != null) return await _cityOf(lat, lon);
      final res = await _client
          .get(Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&addressdetails=1&zoom=10&lat=$lat&lon=$lon'), headers: const {'User-Agent': 'UrbanPulseApp/1.0'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final j = jsonDecode(res.body);
      final a = j is Map ? j['address'] : null;
      if (a is! Map) return null;
      for (final k in const ['city', 'town', 'municipality', 'village', 'city_district', 'state_district', 'county']) {
        final v = a[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    } catch (_) {}
    return null;
  }
}
