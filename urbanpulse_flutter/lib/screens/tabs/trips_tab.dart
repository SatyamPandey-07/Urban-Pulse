import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../core/routes.dart';
import '../../models/trip_models.dart';
import '../../repositories/trip_repository.dart';
import '../../state/app_scope.dart';
import '../../widgets/common.dart';
import '../home_screen.dart';

/// Port of `TripsFragment` / `fragment_trips.xml`.
class TripsTab extends StatefulWidget {
  const TripsTab({super.key});

  @override
  State<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<TripsTab> {
  List<TripPlan> _trips = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTrips());
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

  /// The quick-plan shortcuts open a matching starter template when one exists,
  /// and otherwise hand the traveler to Yatri AI to plan it for real.
  void _quickPlan(String destination) {
    final template = TripRepository.getSampleTrips()
        .where(
          (t) =>
              t.destination.toLowerCase().contains(destination.toLowerCase()),
        )
        .firstOrNull;
    if (template != null) {
      _openTripDetail(template);
    } else {
      HomeTabController.maybeOf(context)?.switchToTab(3);
    }
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
          _suggestionCard(
            context,
            title: '🌲 Lonavala',
            subtitle: 'Waterfalls & Ridge • 83 km\nElectric Rail • AQI: 28',
            onPressed: () => _quickPlan('Lonavala'),
          ),
          _suggestionCard(
            context,
            title: '🏖️ Alibaug',
            subtitle: 'Coastal & Forts • 48 km\nHybrid Ferry • AQI: 34',
            onPressed: () => _quickPlan('Alibaug'),
          ),
          _suggestionCard(
            context,
            title: '🌿 Matheran',
            subtitle: 'Zero-Vehicle Hill Station • 80 km\nToy Train & E-Cart • AQI: 19',
            onPressed: () => HomeTabController.maybeOf(context)?.switchToTab(3),
          ),
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

  Widget _suggestionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        onTap: onPressed,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: onPressed,
              child: const Text('Plan Itinerary'),
            ),
          ],
        ),
      ),
    );
  }
}
