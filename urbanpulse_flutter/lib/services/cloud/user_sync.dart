import 'package:shared_preferences/shared_preferences.dart';

import '../../models/itinerary/itinerary.dart';
import '../../models/trip_brief.dart';
import '../../models/trip_models.dart';
import '../../repositories/itinerary_repository.dart';
import '../../repositories/trip_brief_repository.dart';
import '../../repositories/trip_repository.dart';
import '../../state/accessibility_controller.dart';
import '../../state/activity_tracker.dart';
import '../../state/gamification_controller.dart';
import 'cloud_store.dart';

/// Keeps the device cache in step with the signed-in traveller's account.
///
/// The repositories and controllers read from the device (instant, and it
/// works offline) and write through to [CloudStore]. After sign-in this makes
/// the cache the traveller's own: data made on this phone before accounts
/// existed is adopted into the account; another traveller's cached data is
/// cleared; then the account is read back and the cache replaced with it.
class UserSync {
  UserSync({
    required this.prefs,
    required this.cloud,
    required this.briefs,
    required this.itineraries,
    required this.trips,
    required this.accessibility,
    required this.gamification,
    required this.activity,
  });

  final SharedPreferences prefs;
  final CloudStore cloud;
  final TripBriefRepository briefs;
  final ItineraryRepository itineraries;
  final TripRepository trips;
  final AccessibilityController accessibility;
  final GamificationController gamification;
  final ActivityTracker activity;

  /// Whose data the device cache holds; absent before accounts existed.
  static const _ownerKey = 'cloud.cache_owner';

  Future<void> onSignedIn() async {
    final uid = cloud.userId;
    if (uid == null) return;
    final owner = prefs.getString(_ownerKey);
    if (owner == null) {
      await _adoptLocal();
    } else if (owner != uid) {
      await _clearLocal();
    }
    await prefs.setString(_ownerKey, uid);
    await cloud.flush();
    final snap = await cloud.pull();
    if (snap != null) await _apply(snap);
  }

  /// Before signing out: send what is still queued, then forget the
  /// traveller's data on this device. (Anything that could not be sent stays
  /// queued under their account and goes up when they sign in again.)
  Future<void> beforeSignOut() async {
    await cloud.flush();
  }

  Future<void> afterSignOut() async {
    await _clearLocal();
    await prefs.remove(_ownerKey);
  }

  /// Trips, briefs, itineraries, settings and progress made on this device
  /// before sign-in become the account's.
  Future<void> _adoptLocal() async {
    for (final b in briefs.getBriefs().reversed) {
      await cloud.saveBrief(b);
    }
    for (final i in itineraries.all().reversed) {
      await cloud.saveItinerary(i, saved: true);
    }
    for (final t in trips.getTrips().reversed) {
      await cloud.saveTrip(t);
    }
    await cloud.saveSettings(accessibility.snapshot());
    await cloud.saveProgress({...gamification.snapshot(), 'activity': activity.snapshot()});
  }

  Future<void> _clearLocal() async {
    await briefs.clear();
    await itineraries.clear();
    await trips.clear();
    await accessibility.clear();
    await gamification.clear();
    await activity.clear();
  }

  Future<void> _apply(CloudSnapshot s) async {
    await briefs.replaceAll([
      for (final j in s.briefs)
        if (_try(() => TripBrief.fromJson(j)) case final b?) b,
    ]);
    await itineraries.replaceAll([
      for (final j in s.itineraries)
        if (_try(() => Itinerary.fromJson(j)) case final i?) i,
    ]);
    await trips.replaceAll([
      for (final j in s.trips)
        if (_try(() => TripPlan.fromJson(j)) case final t?) t,
    ]);
    final settings = s.settings;
    if (settings != null) await accessibility.applyCloud(settings);
    final progress = s.progress;
    if (progress != null) {
      await gamification.applyCloud(progress);
      final counts = progress['activity'];
      if (counts is Map) await activity.applyCloud(Map<String, dynamic>.from(counts));
    }
  }

  static T? _try<T>(T Function() parse) {
    try {
      return parse();
    } catch (_) {
      return null;
    }
  }
}
