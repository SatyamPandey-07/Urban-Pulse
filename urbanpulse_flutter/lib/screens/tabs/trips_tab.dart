import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../core/routes.dart';
import '../../domain/carbon_estimator.dart';
import '../../models/trip_models.dart';
import '../../services/open_meteo_service.dart';
import '../../state/app_scope.dart';
import '../../widgets/common.dart';
import '../home_screen.dart';

/// Port of `TripsFragment` / `fragment_trips.xml`.
class TripsTab extends StatefulWidget {
  const TripsTab({super.key});

  @override
  State<TripsTab> createState() => _TripsTabState();
}

/// A nearby destination the app can plan for, with its measured distance and a
/// live air-quality reading.
class _Suggestion {
  const _Suggestion({
    required this.emoji,
    required this.name,
    required this.blurb,
    this.distanceKm,
    this.usAqi,
  });

  final String emoji;
  final String name;
  final String blurb;
  final double? distanceKm;
  final int? usAqi;
}

class _TripsTabState extends State<TripsTab> {
  /// The destinations the quick-plan row offers. Only the identity and the
  /// one-line description are fixed here — distance and air quality are measured
  /// at runtime, and tapping one runs the real planner.
  static const _destinations = [
    ('🌲', 'Lonavala', 'Waterfalls & ridge trails'),
    ('🏖️', 'Alibaug', 'Coastal forts & mangroves'),
    ('🌿', 'Matheran', 'Zero-vehicle hill station'),
  ];

  List<TripPlan> _trips = const [];
  List<_Suggestion> _suggestions = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTrips();
      _loadSuggestions();
    });
  }

  /// Measures the real distance from the traveler's position to each
  /// destination and reads the live AQI there.
  Future<void> _loadSuggestions() async {
    final services = AppScope.of(context);
    await services.location.resolve();

    final resolved = <_Suggestion>[];
    for (final (emoji, name, blurb) in _destinations) {
      final (lat, lon) = CarbonEstimator.resolveCoordinates(name);
      final weather = await OpenMeteoService.getLiveWeatherAndAqi(lat, lon);
      resolved.add(
        _Suggestion(
          emoji: emoji,
          name: name,
          blurb: blurb,
          distanceKm: services.location.hasFix
              ? CarbonEstimator.haversineKm(
                  services.location.latitude!,
                  services.location.longitude!,
                  lat,
                  lon,
                )
              : null,
          usAqi: weather?.usAqi,
        ),
      );
    }

    if (!mounted) return;
    setState(() => _suggestions = resolved);
  }

  void _loadTrips() {
    if (!mounted) return;
    setState(() => _trips = AppScope.of(context).trips.getTrips());
  }

  void _openTripDetail(TripPlan trip) {
    Navigator.of(context)
        .pushNamed(Routes.tripDetail, arguments: trip)
        .then((_) => _loadTrips());
  }

  /// Hands the destination to Yatri AI, which runs the real planner. The Kotlin
  /// version opened one of three fully hand-written trips instead.
  void _quickPlan(String destination) {
    HomeTabController.maybeOf(context)?.switchToTab(3);
    showToast(context, 'Ask Yatri AI: "Plan a trip to $destination"');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcoming = _trips.where((t) => !t.isCompleted).toList();
    final past = _trips.where((t) => t.isCompleted).toList();
    final totalCo2 = _trips.fold<double>(0, (sum, t) => sum + t.co2SavedKg);
    final totalPulse = _trips.fold<int>(
      0,
      (sum, t) => sum + t.pulsePointsEarned,
    );

    return RefreshIndicator(
      onRefresh: () async => _loadTrips(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Sustainable Trips Hub',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Evidence-backed green & step-free itineraries',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StatTile(
                    label: 'TOTAL CO2 AVOIDED',
                    value: '${fixed(totalCo2)} kg CO2e',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'ACTIVE TRIPS',
                    value: '${upcoming.length} Upcoming',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'PULSE POINTS',
                    value: '+$totalPulse PTS',
                    valueColor: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: () =>
                  HomeTabController.maybeOf(context)?.switchToTab(3),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Plan New Trip with Yatri AI'),
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel(context, 'Upcoming Planned Trips'),
          if (upcoming.isEmpty)
            const EmptyState(
              message:
                  'No trips planned yet. Ask Yatri AI to build one, or start from a '
                  'suggested destination below.',
              icon: Icons.luggage_outlined,
            )
          else
            for (final trip in upcoming) _tripCard(context, trip),
          const SizedBox(height: 24),
          _sectionLabel(context, 'Suggested Eco Destinations (1-Tap Plan)'),
          if (_suggestions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final suggestion in _suggestions)
              _suggestionCard(context, suggestion),
          const SizedBox(height: 24),
          _sectionLabel(context, 'Past Completed Trips (Carbon Certified)'),
          if (past.isEmpty)
            const EmptyState(
              message: 'Completed trips will appear here once you finish one.',
              icon: Icons.verified_outlined,
            )
          else
            for (final trip in past) _tripCard(context, trip),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.bold),
    ),
  );

  Widget _tripCard(BuildContext context, TripPlan trip) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        onTap: () => _openTripDetail(trip),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    trip.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '-${trip.co2SavedKg} kg CO2',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${trip.travelDates} • ${trip.durationDays} Days',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '🏨 ${trip.hotelName} (★ ${trip.hotelRating}) • '
              '♿ ${trip.isStepFreeAccessible ? "Step-Free" : "Standard"}',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              '🚆 ${trip.travelMode} • Budget: ${rupees(trip.totalBudgetInr)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: () => _openTripDetail(trip),
                child: const Text('Open Itinerary'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionCard(BuildContext context, _Suggestion suggestion) {
    final theme = Theme.of(context);
    final facts = [
      if (suggestion.distanceKm != null)
        '${fixed(suggestion.distanceKm!, 0)} km away'
      else
        'Distance needs location access',
      if (suggestion.usAqi != null)
        'AQI ${suggestion.usAqi} now'
      else
        'AQI unavailable',
    ].join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        onTap: () => _quickPlan(suggestion.name),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${suggestion.emoji} ${suggestion.name}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    suggestion.blurb,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    facts,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: () => _quickPlan(suggestion.name),
              child: const Text('Plan Itinerary'),
            ),
          ],
        ),
      ),
    );
  }
}
