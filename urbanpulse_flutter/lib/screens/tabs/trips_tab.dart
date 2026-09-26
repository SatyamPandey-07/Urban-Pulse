import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../core/routes.dart';
import '../../domain/carbon_estimator.dart';
import '../../models/trip_models.dart';
import '../../services/open_meteo_service.dart';
import '../../state/app_scope.dart';
import '../../widgets/common.dart';
import '../home_screen.dart';
import '../plan_itinerary_screen.dart';

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
    required this.icon,
    required this.name,
    required this.blurb,
    this.distanceKm,
    this.usAqi,
  });

  final IconData icon;
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
    (Icons.forest_outlined, 'Lonavala', 'Waterfalls & ridge trails'),
    (Icons.beach_access_outlined, 'Alibaug', 'Coastal forts & mangroves'),
    (Icons.park_outlined, 'Matheran', 'Zero-vehicle hill station'),
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
    for (final (icon, name, blurb) in _destinations) {
      final (lat, lon) = CarbonEstimator.resolveCoordinates(name);
      final weather = await OpenMeteoService.getLiveWeatherAndAqi(lat, lon);
      resolved.add(
        _Suggestion(
          icon: icon,
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
    // A trip planned by the multi-agent planner reopens as the full itinerary.
    final full = AppScope.of(context).itineraries.byId(trip.id);
    if (full != null) {
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => PlanItineraryScreen(itinerary: full)))
          .then((_) => _loadTrips());
      return;
    }
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sustainable Trips Hub',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Evidence-backed green & step-free itineraries',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metricColumn(
                  icon: Icons.eco_rounded,
                  iconColor: AppColors.primaryGreen,
                  value: '${fixed(totalCo2)} kg',
                  label: 'CO2 avoided',
                ),
                Container(width: 1, height: 38, color: AppColors.surfaceBorder),
                _metricColumn(
                  icon: Icons.work_outline_rounded,
                  iconColor: AppColors.primaryBlue,
                  value: '${upcoming.length}',
                  label: 'Active trips',
                ),
                Container(width: 1, height: 38, color: AppColors.surfaceBorder),
                _metricColumn(
                  icon: Icons.star_rounded,
                  iconColor: AppColors.solidWarning,
                  value: '$totalPulse',
                  label: 'Pulse points',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () =>
                  HomeTabController.maybeOf(context)?.switchToTab(3),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: const Color(0xFF0B1015),
                elevation: 4,
                shadowColor: AppColors.primaryGreen.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text(
                'Plan New Trip with Yatri AI',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader(
            context,
            title: 'Upcoming Planned Trips',
            actionText: 'View all >',
            onAction: () {},
          ),
          if (upcoming.isEmpty)
            _defaultUpcomingTripCard(context)
          else
            for (final trip in upcoming) _tripCard(context, trip),
          const SizedBox(height: 24),
          _sectionHeader(
            context,
            title: 'Suggested Eco Destinations',
            actionText: 'See all >',
            onAction: () {},
          ),
          if (_suggestions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final suggestion in _suggestions)
              _suggestionCard(context, suggestion),
          if (past.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionHeader(
              context,
              title: 'Past Completed Trips (Carbon Certified)',
            ),
            for (final trip in past) _tripCard(context, trip),
          ],
        ],
      ),
    );
  }

  Widget _metricColumn({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, size: 22, color: iconColor),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    String? actionText,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (actionText != null)
            InkWell(
              onTap: onAction,
              child: Text(
                actionText,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _defaultUpcomingTripCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        padding: const EdgeInsets.all(12),
        onTap: () => HomeTabController.maybeOf(context)?.switchToTab(3),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 76,
                height: 76,
                color: AppColors.surfaceElevated,
                child: Image.network(
                  'https://images.unsplash.com/photo-1544735716-392fe2489ffa?w=300&q=80',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.temple_hindu_outlined, size: 30, color: AppColors.primaryGreen),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rishikesh',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '12-15 Oct 2026',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _badgeChip('Solo'),
                      const SizedBox(width: 6),
                      _badgeChip('Step-free'),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _badgeChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.surfaceBorder, width: 0.8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

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
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hotel_outlined, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      trip.hotelName,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.star_rounded, size: 13, color: theme.colorScheme.primary),
                    Text(
                      '${trip.hotelRating}',
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      trip.isStepFreeAccessible ? Icons.accessible_outlined : Icons.not_accessible_outlined,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      trip.isStepFreeAccessible ? "Step-Free" : "Standard",
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.train_outlined, size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      '${trip.travelMode} • ${rupees(trip.totalBudgetInr)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
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
    final photoUrl = switch (suggestion.name.toLowerCase()) {
      'lonavala' => 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=300&q=80',
      'alibaug' => 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=300&q=80',
      _ => 'https://images.unsplash.com/photo-1448375240586-882707db888b?w=300&q=80',
    };

    final aqi = suggestion.usAqi ?? 76;
    final km = suggestion.distanceKm != null
        ? '${fixed(suggestion.distanceKm!, 0)} km away'
        : '28 km away';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        padding: const EdgeInsets.all(12),
        onTap: () => _quickPlan(suggestion.name),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 64,
                height: 64,
                color: AppColors.surfaceElevated,
                child: Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(suggestion.icon, size: 24, color: AppColors.primaryGreen),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    suggestion.blurb,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$km • AQI $aqi',
                    style: const TextStyle(
                      color: AppColors.primaryGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 32,
              child: OutlinedButton(
                onPressed: () => _quickPlan(suggestion.name),
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.surfaceElevated,
                  side: const BorderSide(color: AppColors.surfaceBorder, width: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  foregroundColor: AppColors.textPrimary,
                ),
                child: const Text('Plan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
