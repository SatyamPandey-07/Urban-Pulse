import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  ActivityTracker(this._prefs);

  static const _prefix = 'urbanpulse_activity';

  final SharedPreferences _prefs;

  int count(TrackedAction action) =>
      _prefs.getInt('$_prefix.${action.key}') ?? 0;

  Future<void> increment(TrackedAction action, [int by = 1]) async {
    await _prefs.setInt('$_prefix.${action.key}', count(action) + by);
    notifyListeners();
  }
}
