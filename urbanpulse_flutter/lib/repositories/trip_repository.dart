import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_models.dart';
import '../services/cloud/cloud_store.dart';

/// The traveler's saved trips, kept on the device as JSON and in their account.
/// Port of `TripRepository.kt`.
class TripRepository {
  TripRepository(this._prefs, {this.cloud});

  final SharedPreferences _prefs;
  final CloudStore? cloud;

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

  /// Saves [trip]; [itineraryClientId] links it to the full itinerary it came from.
  Future<void> addTrip(TripPlan trip, {String? itineraryClientId}) async {
    await replaceAll([trip, ...getTrips()]);
    await cloud?.saveTrip(trip, itineraryClientId: itineraryClientId);
  }

  /// Saves [trip], replacing the saved trip with the same id (an edited plan
  /// stays one entry), or adding it if there is none.
  Future<void> upsertTrip(TripPlan trip, {String? itineraryClientId}) async {
    final list = getTrips();
    final i = list.indexWhere((t) => t.id == trip.id);
    if (i < 0) {
      await replaceAll([trip, ...list]);
    } else {
      await replaceAll([...list.take(i), trip, ...list.skip(i + 1)]);
    }
    await cloud?.saveTrip(trip, itineraryClientId: itineraryClientId);
  }

  /// The device copy becomes [trips] (the account's, after sign-in).
  Future<void> replaceAll(List<TripPlan> trips) => _prefs.setString(
    _keyTrips,
    jsonEncode(trips.map((t) => t.toJson()).toList()),
  );

  Future<void> clear() => _prefs.remove(_keyTrips);
}
