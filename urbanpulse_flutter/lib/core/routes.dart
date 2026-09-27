import 'package:flutter/material.dart';

import '../models/trip_models.dart';
import '../screens/achievements_screen.dart';
import '../screens/carbon_wallet_screen.dart';
import '../screens/green_route_planner_screen.dart';
import '../screens/home_screen.dart';
import '../screens/hospitality_screen.dart';
import '../screens/hotel_optimizer_screen.dart';
import '../screens/itinerary_screen.dart';
import '../screens/login_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/sos_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/sustainable_trips_hub_screen.dart';
import '../screens/trip_detail_screen.dart';
import '../screens/trip_pool_screen.dart';
import '../screens/weather_twin_screen.dart';
import '../screens/welcome_screen.dart';

/// Named routes, one per Activity in the original `AndroidManifest.xml`. The
/// navigation graph is a plain stack, so Flutter's own [Navigator] covers it —
/// no routing package needed.
abstract final class Routes {
  static const splash = '/';
  static const welcome = '/welcome';
  static const login = '/login';
  static const signup = '/signup';
  static const home = '/home';
  static const achievements = '/achievements';
  static const sos = '/sos';
  static const hospitality = '/hospitality';
  static const greenRoutePlanner = '/green-route-planner';
  static const hotelOptimizer = '/hotel-optimizer';
  static const carbonWallet = '/carbon-wallet';
  static const itinerary = '/itinerary';
  static const tripDetail = '/trip-detail';
  static const sustainableTripsHub = '/sustainable-trips-hub';
  static const weatherTwin = '/weather-twin';
  static const tripPool = '/trip-pool';
  static const notifications = '/notifications';

  static Map<String, WidgetBuilder> get table => {
    splash: (_) => const SplashScreen(),
    welcome: (_) => const WelcomeScreen(),
    login: (_) => const LoginScreen(),
    signup: (_) => const SignUpScreen(),
    home: (_) => const HomeScreen(),
    achievements: (_) => const AchievementsScreen(),
    sos: (_) => const SosScreen(),
    hospitality: (_) => const HospitalityScreen(),
    greenRoutePlanner: (_) => const GreenRoutePlannerScreen(),
    hotelOptimizer: (_) => const HotelOptimizerScreen(),
    carbonWallet: (_) => const CarbonWalletScreen(),
    itinerary: (_) => const ItineraryScreen(),
    sustainableTripsHub: (_) => const SustainableTripsHubScreen(),
    weatherTwin: (_) => const WeatherTwinScreen(),
    tripPool: (_) => const TripPoolScreen(),
    notifications: (_) => const NotificationsScreen(),
  };

  /// [tripDetail] is the one route that carries an argument.
  static Route<void>? onGenerateRoute(RouteSettings settings) {
    if (settings.name != tripDetail) return null;
    final trip = settings.arguments as TripPlan?;
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => TripDetailScreen(trip: trip),
    );
  }
}
