import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/experience_repository.dart';
import '../repositories/hospitality_repository.dart';
import '../repositories/hotel_metrics_repository.dart';
import '../repositories/trip_repository.dart';
import '../services/location_service.dart';
import 'accessibility_controller.dart';
import 'auth_controller.dart';
import 'gamification_controller.dart';
import 'theme_controller.dart';
import 'trip_plan_manager.dart';

/// The app's single composition root, exposed to the widget tree through an
/// [InheritedWidget]. This replaces the Kotlin singletons
/// (`GamificationManager`, `TripPlanManager`, `AccessibilityManager.getInstance`,
/// `AppDatabaseHelper.getInstance`) with one place that owns their lifetime,
/// which is also what makes the screens testable.
class AppServices {
  AppServices(SharedPreferences prefs)
    : auth = AuthController(prefs),
      theme = ThemeController(prefs),
      gamification = GamificationController(prefs),
      accessibility = AccessibilityController(prefs),
      tripPlan = TripPlanManager(prefs),
      trips = TripRepository(prefs),
      experiences = ExperienceRepository(),
      hospitality = HospitalityRepository(),
      hotelMetrics = HotelMetricsRepository(),
      location = LocationService();

  final AuthController auth;
  final ThemeController theme;
  final GamificationController gamification;
  final AccessibilityController accessibility;
  final TripPlanManager tripPlan;
  final TripRepository trips;
  final ExperienceRepository experiences;
  final HospitalityRepository hospitality;
  final HotelMetricsRepository hotelMetrics;
  final LocationService location;

  void dispose() {
    auth.dispose();
    theme.dispose();
    gamification.dispose();
    accessibility.dispose();
    tripPlan.dispose();
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
