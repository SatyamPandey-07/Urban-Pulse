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
import '../repositories/traffic_history_repository.dart';
import '../repositories/trip_brief_repository.dart';
import '../repositories/trip_repository.dart';
import '../services/cloud/cloud_store.dart';
import '../services/cloud/user_sync.dart';
import '../services/emergency/emergency_contacts.dart';
import '../services/emergency/emergency_sms.dart';
import '../services/live_location.dart';
import '../services/location_service.dart';
import '../services/trip_pool/trip_pool_service.dart';
import '../services/watch/method_channel_watch_link.dart';
import '../services/watch/watch_link.dart';
import '../services/watch/watch_service.dart';
import 'accessibility_controller.dart';
import 'activity_tracker.dart';
import 'auth_controller.dart';
import 'gamification_controller.dart';
import 'location_controller.dart';
import 'sos_controller.dart';
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
  /// [watchLink] and [emergencySms] are injected by the tests; the app builds
  /// the real platform-channel implementations.
  factory AppServices(
    SharedPreferences prefs, {
    SupabaseClient? supabase,
    WatchLink? watchLink,
    EmergencySms? emergencySms,
    LiveLocation? emergencyLocation,
  }) {
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
    auth
      // After the account's data is in place, bring Trip-pool requests (and the
      // itineraries they change) up to date.
      ..onSignedIn = () async {
        await sync.onSignedIn();
        unawaited(tripPool.refresh());
      }
      ..beforeSignOut = sync.beforeSignOut
      ..afterSignOut = sync.afterSignOut;
    final locationService = LocationService();
    return AppServices._(
      prefs: prefs,
      cloud: cloud,
      auth: auth,
      theme: ThemeController(prefs),
      activity: activity,
      gamification: gamification,
      accessibility: accessibility,
      tripPlan: TripPlanManager(prefs),
      location: LocationController(locationService),
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
      emergencyContacts: EmergencyContactsRepository(prefs),
      watchLink: watchLink ?? MethodChannelWatchLink(),
      emergencySms: emergencySms ?? PlatformEmergencySms(),
      emergencyLocation: emergencyLocation ?? const DeviceLocation(),
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
    required this.emergencyContacts,
    required WatchLink watchLink,
    required EmergencySms emergencySms,
    required LiveLocation emergencyLocation,
  }) : _watchLink = watchLink,
       _emergencySms = emergencySms,
       _emergencyLocation = emergencyLocation;

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

  /// The people an SOS reaches.
  final EmergencyContactsRepository emergencyContacts;

  final WatchLink _watchLink;
  final EmergencySms _emergencySms;
  final LiveLocation _emergencyLocation;

  /// The SOS sequence, shared by the SOS screen and the watch. Built on first
  /// use, and before [watch] so the watch can push its acknowledgements here.
  late final SosController sos = SosController(
    contacts: emergencyContacts,
    sms: _emergencySms,
    location: _emergencyLocation,
  );

  WatchService? _watch;

  /// The Garmin link, its mirror and the two settings toggles.
  ///
  /// Lazy on purpose: building it subscribes to the platform channel, so a
  /// traveller who never opens the Garmin row never starts the Connect IQ SDK.
  WatchService get watch => _watch ??= WatchService(
    link: _watchLink,
    prefs: prefs,
    sos: sos,
  );

  /// Builds [watch] if needed, then probes for the device.
  Future<void> startWatchLink() => watch.connect();

  /// A trip brief handed to Yatri from elsewhere in the app (Surprise Me); the
  /// Yatri tab picks it up, opens it for review, and plans it.
  final ValueNotifier<TripBrief?> yatriInbox = ValueNotifier(null);

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
    // Only if something actually asked for it; building one here would start
    // the SDK on the way out.
    _watch?.dispose();
    sos.dispose();
    emergencyContacts.dispose();
    yatriInbox.dispose();
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
