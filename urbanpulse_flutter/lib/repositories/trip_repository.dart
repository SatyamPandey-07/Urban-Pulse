import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_models.dart';

/// The traveler's saved trips, persisted as JSON in shared preferences.
/// Port of `TripRepository.kt`.
class TripRepository {
  TripRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _keyTrips = 'urbanpulse_trips.saved_trips_json';

  /// The user's real saved trips — starts empty on first run, not pre-seeded
  /// with sample data.
  List<TripPlan> getTrips() {
    final json = _prefs.getString(_keyTrips);
    if (json == null) return const [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .map((t) => TripPlan.fromJson(t as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> addTrip(TripPlan trip) async {
    final list = [trip, ...getTrips()];
    await _prefs.setString(
      _keyTrips,
      jsonEncode(list.map((t) => t.toJson()).toList()),
    );
  }
}
