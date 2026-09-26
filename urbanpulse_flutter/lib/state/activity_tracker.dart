import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cloud/cloud_store.dart';

/// Counters for things the traveler has actually done, incremented at the real
/// call sites (a question asked, a booking made, a report filed, a journey
/// confirmed, an itinerary saved, a trip planned).
///
/// The Kotlin `GamificationManager` returned badges and challenges with progress
/// values typed straight into the list (`progress = 5, target = 10`), so they
/// never moved. These counters are what the migrated badges and challenges are
/// computed from, so the progress bars mean something.
enum TrackedAction {
  aiQuestionsAsked('ai_questions_asked'),
  tripsPlanned('trips_planned'),
  tripsSaved('trips_saved'),
  experiencesBooked('experiences_booked'),
  accessibilityReportsFiled('accessibility_reports_filed'),
  greenJourneysConfirmed('green_journeys_confirmed'),
  itinerariesSaved('itineraries_saved'),
  experiencesPublished('experiences_published');

  const TrackedAction(this.key);

  final String key;
}

class ActivityTracker extends ChangeNotifier {
  ActivityTracker(this._prefs, {this.cloud});

  static const _prefix = 'urbanpulse_activity';

  final SharedPreferences _prefs;
  final CloudStore? cloud;

  int count(TrackedAction action) =>
      _prefs.getInt('$_prefix.${action.key}') ?? 0;

  Future<void> increment(TrackedAction action, [int by = 1]) async {
    await _prefs.setInt('$_prefix.${action.key}', count(action) + by);
    notifyListeners();
    await cloud?.saveProgress({'activity': snapshot()});
  }

  /// Every counter, keyed as in the account (`user_progress.activity`).
  Map<String, int> snapshot() => {for (final a in TrackedAction.values) a.key: count(a)};

  /// The device counters become the account's.
  Future<void> applyCloud(Map<String, dynamic> counts) async {
    for (final a in TrackedAction.values) {
      final v = counts[a.key];
      await _prefs.setInt('$_prefix.${a.key}', v is num ? v.toInt() : 0);
    }
    notifyListeners();
  }

  Future<void> clear() async {
    for (final a in TrackedAction.values) {
      await _prefs.remove('$_prefix.${a.key}');
    }
    notifyListeners();
  }
}
