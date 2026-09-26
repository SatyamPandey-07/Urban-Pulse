import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/experience_repository.dart';
import '../repositories/facility_repository.dart';
import '../repositories/hospitality_repository.dart';
import '../repositories/hotel_metrics_repository.dart';
import '../repositories/traffic_history_repository.dart';
import '../repositories/trip_repository.dart';
import '../services/location_service.dart';
import 'accessibility_controller.dart';
import 'activity_tracker.dart';
import 'auth_controller.dart';
import 'gamification_controller.dart';
import 'location_controller.dart';
import 'theme_controller.dart';
import 'trip_plan_manager.dart';

/// The app's single composition root, exposed to the widget tree through an
/// [InheritedWidget]. This replaces the Kotlin singletons
/// (`GamificationManager`, `TripPlanManager`, `AccessibilityManager.getInstance`,
/// `AppDatabaseHelper.getInstance`) with one place that owns their lifetime,
/// which is also what makes the screens testable.
class AppServices {
  factory AppServices(SharedPreferences prefs) {
    // Built once and shared: the gamification controller derives badge and
    // challenge progress from the same tracker the screens increment, and the
    // location controller wraps the same service the screens read fixes from.
    final activity = ActivityTracker(prefs);
    final locationService = LocationService();
    return AppServices._(
      auth: AuthController(prefs),
      theme: ThemeController(prefs),
      activity: activity,
      gamification: GamificationController(prefs, activity),
      accessibility: AccessibilityController(prefs),
      tripPlan: TripPlanManager(prefs),
      location: LocationController(locationService),
      trips: TripRepository(prefs),
      experiences: ExperienceRepository(),
      hospitality: HospitalityRepository(),
      hotelMetrics: HotelMetricsRepository(),
      facility: FacilityRepository(),
      trafficHistory: TrafficHistoryRepository(),
      locationService: locationService,
    );
  }

  AppServices._({
    required this.auth,
    required this.theme,
    required this.activity,
    required this.gamification,
    required this.accessibility,
    required this.tripPlan,
    required this.location,
    required this.trips,
    required this.experiences,
    required this.hospitality,
    required this.hotelMetrics,
    required this.facility,
    required this.trafficHistory,
    required this.locationService,
  });

  final AuthController auth;
  final ThemeController theme;
  final GamificationController gamification;
  final ActivityTracker activity;
  final AccessibilityController accessibility;
  final TripPlanManager tripPlan;
  final LocationController location;
  final TripRepository trips;
  final ExperienceRepository experiences;
  final HospitalityRepository hospitality;
  final HotelMetricsRepository hotelMetrics;
  final FacilityRepository facility;
  final TrafficHistoryRepository trafficHistory;
  final LocationService locationService;

  void dispose() {
    auth.dispose();
    theme.dispose();
    gamification.dispose();
    activity.dispose();
    accessibility.dispose();
    tripPlan.dispose();
    location.dispose();
  }
}

class AppScope extends InheritedWidget {
  const AppScope({required this.services, required super.child, super.key});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing from the widget tree');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
