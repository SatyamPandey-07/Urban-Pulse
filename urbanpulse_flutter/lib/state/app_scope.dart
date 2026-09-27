import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../agents/runtime/agent_toolkit.dart';
import '../models/trip_brief.dart';
import '../repositories/experience_repository.dart';
import '../repositories/facility_repository.dart';
import '../repositories/hospitality_repository.dart';
import '../repositories/hotel_metrics_repository.dart';
import '../repositories/itinerary_repository.dart';
import '../repositories/saved_places_repository.dart';
import '../services/place_suggestions.dart';
import '../repositories/traffic_history_repository.dart';
import '../repositories/trip_brief_repository.dart';
import '../repositories/trip_repository.dart';
import '../services/cloud/cloud_store.dart';
import '../services/cloud/user_sync.dart';
import '../services/location_service.dart';
import '../services/sos/sos_backend.dart';
import '../services/trip_pool/trip_pool_service.dart';
import '../services/voice/voice_service.dart';
import 'accessibility_controller.dart';
import 'activity_tracker.dart';
import 'auth_controller.dart';
import 'gamification_controller.dart';
import 'location_controller.dart';
import 'sos_controller.dart';
import 'map_requests.dart';
import 'theme_controller.dart';
import 'trip_plan_manager.dart';

/// The app's single composition root, exposed to the widget tree through an
/// [InheritedWidget]. This replaces the Kotlin singletons
/// (`GamificationManager`, `TripPlanManager`, `AccessibilityManager.getInstance`,
/// `AppDatabaseHelper.getInstance`) with one place that owns their lifetime,
/// which is also what makes the screens testable.
class AppServices {
  /// [supabase] turns on real accounts and cloud storage; without it the app
  /// keeps everything on the device, as before.
  factory AppServices(SharedPreferences prefs, {SupabaseClient? supabase}) {
    // Built once and shared: the gamification controller derives badge and
    // challenge progress from the same tracker the screens increment, and the
    // location controller wraps the same service the screens read fixes from.
    final cloud = CloudStore(prefs, supabase);
    final activity = ActivityTracker(prefs, cloud: cloud);
    final gamification = GamificationController(prefs, activity, cloud: cloud);
    final accessibility = AccessibilityController(prefs, cloud: cloud);
    final trips = TripRepository(prefs, cloud: cloud);
    final itineraries = ItineraryRepository(prefs, cloud: cloud);
    final tripBriefs = TripBriefRepository(prefs, cloud: cloud);
    final auth = AuthController(prefs, client: supabase);
    final sync = UserSync(
      prefs: prefs,
      cloud: cloud,
      briefs: tripBriefs,
      itineraries: itineraries,
      trips: trips,
      accessibility: accessibility,
      gamification: gamification,
      activity: activity,
    );
    final tripPool = TripPoolService(
      client: supabase,
      myName: () => auth.userName.isNotEmpty ? auth.userName : auth.userEmail.split('@').first,
      itineraries: itineraries,
    );
    final sos = SosController(
      prefs: prefs,
      myName: () => auth.userName.isNotEmpty ? auth.userName : auth.userEmail.split('@').first,
      backend: supabase == null ? null : SupabaseSosBackend(supabase),
    );
    auth
      // After the account's data is in place, bring Trip-pool requests (and the
      // itineraries they change) up to date, and start SOS (the power-button
      // watch and alerts from people nearby).
      ..onSignedIn = () async {
        await sync.onSignedIn();
        unawaited(tripPool.refresh());
        unawaited(sos.onSignedIn());
      }
      ..beforeSignOut = sync.beforeSignOut
      ..afterSignOut = () async {
        await sync.afterSignOut();
        await sos.onSignedOut();
      };
    final locationService = LocationService();
    final savedPlaces = SavedPlacesRepository(prefs);
    return AppServices._(
      prefs: prefs,
      cloud: cloud,
      auth: auth,
      theme: ThemeController(prefs),
      activity: activity,
      gamification: gamification,
      accessibility: accessibility,
      tripPlan: TripPlanManager(prefs),
      location: LocationController(locationService, places: savedPlaces),
      savedPlaces: savedPlaces,
      trips: trips,
      itineraries: itineraries,
      tripBriefs: tripBriefs,
      experiences: ExperienceRepository(),
      hospitality: HospitalityRepository(),
      hotelMetrics: HotelMetricsRepository(),
      facility: FacilityRepository(),
      trafficHistory: TrafficHistoryRepository(),
      locationService: locationService,
      tripPool: tripPool,
      sos: sos,
    );
  }

  AppServices._({
    required this.prefs,
    required this.cloud,
    required this.auth,
    required this.theme,
    required this.activity,
    required this.gamification,
    required this.accessibility,
    required this.tripPlan,
    required this.location,
    required this.savedPlaces,
    required this.trips,
    required this.itineraries,
    required this.tripBriefs,
    required this.experiences,
    required this.hospitality,
    required this.hotelMetrics,
    required this.facility,
    required this.trafficHistory,
    required this.locationService,
    required this.tripPool,
    required this.sos,
  });

  final SharedPreferences prefs;

  /// The traveller's account storage (does nothing without Supabase).
  final CloudStore cloud;
  final AuthController auth;
  final ThemeController theme;
  final GamificationController gamification;
  final ActivityTracker activity;
  final AccessibilityController accessibility;
  final TripPlanManager tripPlan;
  final LocationController location;

  /// Home, Work and the traveller's own addresses.
  final SavedPlacesRepository savedPlaces;

  /// Completions while typing a place.
  final PlaceSuggestions placeSuggestions = PlaceSuggestions();
  final TripRepository trips;
  final ItineraryRepository itineraries;
  final TripBriefRepository tripBriefs;
  final ExperienceRepository experiences;
  final HospitalityRepository hospitality;
  final HotelMetricsRepository hotelMetrics;
  final FacilityRepository facility;
  final TrafficHistoryRepository trafficHistory;
  final LocationService locationService;

  /// Trip-pooling: shared rides with travellers going the same way that day.
  final TripPoolService tripPool;

  /// Emergency SOS: yours (power button or SOS screen) and alerts from people nearby.
  final SosController sos;

  /// The app's navigator, so an SOS alert can open the SOS screen from anywhere.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// A trip brief handed to Yatri from elsewhere in the app (Surprise Me); the
  /// Yatri tab picks it up, opens it for review, and plans it.
  final ValueNotifier<TripBrief?> yatriInbox = ValueNotifier(null);
  /// Talking to the app (Groq speech to text, and replies read aloud); built on first use.
  late final VoiceService voice = VoiceService(prefs: prefs);

  /// Where the itinerary screen asks the Live Map to show a day of the trip.
  final MapRequests mapRequests = MapRequests();

  /// The planner's shared models, data clients and caches (built on first use).
  late final AgentToolkit agentToolkit = AgentToolkit.fromConfig(prefs: prefs);

  void dispose() {
    auth.dispose();
    theme.dispose();
    gamification.dispose();
    activity.dispose();
    accessibility.dispose();
    tripPlan.dispose();
    location.dispose();
    tripPool.dispose();
    sos.dispose();
    yatriInbox.dispose();
    mapRequests.dispose();
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
