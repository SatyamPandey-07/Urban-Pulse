import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/itinerary/itinerary.dart';

/// Saved multi-agent itineraries, kept beside the simpler saved trips so a trip
/// in My Trips can be reopened as the full plan (and, later, edited).
class ItineraryRepository {
  ItineraryRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'urbanpulse_itineraries.json';
  static const maxSaved = 30;

  List<Itinerary> all() {
    final json = _prefs.getString(_key);
    if (json == null) return const [];
    try {
      return [
        for (final e in jsonDecode(json) as List<dynamic>)
          if (e is Map<String, dynamic>) Itinerary.fromJson(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  Itinerary? byId(String id) {
    for (final i in all()) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Saves [itinerary], replacing any with the same id; the newest first.
  Future<void> save(Itinerary itinerary) async {
    final list = [itinerary, for (final i in all()) if (i.id != itinerary.id) i];
    await _prefs.setString(_key, jsonEncode([for (final i in list.take(maxSaved)) i.toJson()]));
  }
}
