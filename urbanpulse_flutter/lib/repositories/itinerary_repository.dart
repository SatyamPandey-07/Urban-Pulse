import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/itinerary/itinerary.dart';
import '../services/cloud/cloud_store.dart';

/// Saved multi-agent itineraries, kept beside the simpler saved trips so a trip
/// in My Trips can be reopened as the full plan (and, later, edited). Read from
/// the device; every save also goes to the traveller's account.
class ItineraryRepository {
  ItineraryRepository(this._prefs, {this.cloud});

  final SharedPreferences _prefs;
  final CloudStore? cloud;

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
    await replaceAll(list);
    await cloud?.saveItinerary(itinerary, saved: true);
  }

  /// The device copy becomes [list] (the account's, after sign-in).
  Future<void> replaceAll(List<Itinerary> list) =>
      _prefs.setString(_key, jsonEncode([for (final i in list.take(maxSaved)) i.toJson()]));

  Future<void> clear() => _prefs.remove(_key);
}
