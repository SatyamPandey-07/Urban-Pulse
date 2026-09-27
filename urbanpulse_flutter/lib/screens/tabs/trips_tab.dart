import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../core/routes.dart';
import '../../models/app_notification.dart';
import '../../models/trip_models.dart';
import '../../repositories/trip_repository.dart';
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

class _TripsTabState extends State<TripsTab> {
  List<TripPlan> _trips = const [];
  TripRepository? _repo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A trip saved or edited from another tab (Yatri chat, pooling, SOS...)
      // shows up here without a manual pull-to-refresh.
      _repo = AppScope.of(context).trips..addListener(_loadTrips);
      _loadTrips();
    });
  }

  @override
  void dispose() {
    _repo?.removeListener(_loadTrips);
    super.dispose();
  }

  void _loadTrips() {
    if (!mounted) return;
    setState(() => _trips = _repo?.getTrips() ?? const []);
  }

  void _openTripDetail(TripPlan trip) {
    // A trip planned by the multi-agent planner reopens as the full itinerary.
    final services = AppScope.of(context);
    final full = services.itineraries.byId(trip.id);
    if (full != null) {
      Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => PlanItineraryScreen(
                itinerary: full,
                saved: true,
                toolkit: services.agentToolkit,
                // An edited trip replaces its saved copy, so My Trips shows one entry.
                onChanged: (updated) async {
                  await services.itineraries.save(updated);
                  await services.trips.upsertTrip(updated.toTripPlan(), itineraryClientId: updated.id);
                  await services.notifications.add(
                    kind: NotificationKind.tripUpdated,
                    title: 'Itinerary updated',
                    body: 'Plan for ${updated.destination.split(',').first.trim()} updated.',
                    target: const NotificationTarget.tab(2),
                  );
                },
              ),
            ),
          )
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

  int _selectedFilter = 0; // 0: Upcoming, 1: Past, 2: Saved

  @override
  Widget build(BuildContext context) {
    final upcoming = _trips.where((t) => !t.isCompleted).toList();
    final past = _trips.where((t) => t.isCompleted).toList();

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async => _loadTrips(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              // Header Row
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Trips',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Your planned & saved trips',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE8F8F0),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.eco_rounded,
                          color: Color(0xFF00A86B),
                          size: 20,
                        ),
                      ),
                      tooltip: 'Sustainable Trips Hub',
                      onPressed: () => Navigator.of(context).pushNamed(Routes.sustainableTripsHub),
                    ),
                  ],
                ),
              ),

              // Filter Pills Row
              Row(
                children: [
                  _filterPill(label: 'Upcoming', index: 0),
                  const SizedBox(width: 8),
                  _filterPill(label: 'Past', index: 1),
                  const SizedBox(width: 8),
                  _filterPill(label: 'Saved', index: 2),
                ],
              ),
              const SizedBox(height: 18),

              // Trip Cards List
              ..._buildTripsList(context, upcoming, past),
            ],
          ),
        ),

        // Pinned Bottom Button: "+ Plan New Trip"
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => HomeTabController.maybeOf(context)?.switchToTab(3),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                foregroundColor: Colors.white,
                elevation: 4,
                shadowColor: const Color(0xFF00A86B).withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 20, color: Colors.white),
              label: const Text(
                'Plan New Trip',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _filterPill({required String label, required int index}) {
    final isSelected = _selectedFilter == index;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = index),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00A86B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00A86B) : AppColors.surfaceLightBorder,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF00A86B).withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  static String _imageForDestination(String destination) {
    final lower = destination.toLowerCase();
    if (lower.contains('munnar')) {
      return 'https://images.unsplash.com/photo-1596176530529-78163a4f7af2?w=500&auto=format&fit=crop&q=80';
    } else if (lower.contains('rishikesh')) {
      return 'https://images.unsplash.com/photo-1600100397608-f010f4439c27?w=500&auto=format&fit=crop&q=80';
    } else if (lower.contains('goa')) {
      return 'https://images.unsplash.com/photo-1512343879784-a960bf40e7f2?w=500&auto=format&fit=crop&q=80';
    } else if (lower.contains('jaipur')) {
      return 'https://images.unsplash.com/photo-1603228254119-e6a528dc568c?w=500&auto=format&fit=crop&q=80';
    } else if (lower.contains('coorg')) {
      return 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=500&auto=format&fit=crop&q=80';
    } else if (lower.contains('lonavala')) {
      return 'https://images.unsplash.com/photo-1570789210967-2cac24afeb00?w=500&auto=format&fit=crop&q=80';
    } else if (lower.contains('alibaug')) {
      return 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=500&auto=format&fit=crop&q=80';
    } else if (lower.contains('manali')) {
      return 'https://images.unsplash.com/photo-1626621341517-bbf3d9990a23?w=500&auto=format&fit=crop&q=80';
    }
    return 'https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?w=500&auto=format&fit=crop&q=80';
  }

  List<Widget> _buildTripsList(
    BuildContext context,
    List<TripPlan> upcoming,
    List<TripPlan> past,
  ) {
    if (_selectedFilter == 0) {
      if (upcoming.isNotEmpty) {
        return upcoming.map((trip) => _styledTripCard(
          context,
          title: trip.title,
          dateStr: '${trip.travelDates} • ${trip.durationDays} days',
          imageUrl: _imageForDestination(trip.destination.isNotEmpty ? trip.destination : trip.title),
          tags: [
            '${fixed(trip.co2SavedKg, 1)} kg CO₂',
            if (trip.travelMode.isNotEmpty) trip.travelMode else 'Eco Friendly',
          ],
          onTap: () => _openTripDetail(trip),
        )).toList();
      }
      return _emptyStateWithInspirations(
        context,
        title: 'No upcoming trips planned yet',
        subtitle: 'Let Yatri AI create a personalized, sustainable itinerary for you!',
        inspirations: [
          _InspirationTrip(
            title: 'Coorg Coffee Hills',
            destination: 'Coorg',
            duration: '4 days',
            tags: const ['Nature', 'Eco Stays'],
          ),
          _InspirationTrip(
            title: 'Munnar Tea Trails',
            destination: 'Munnar',
            duration: '3 days',
            tags: const ['Shola Grasslands', 'Green Transit'],
          ),
          _InspirationTrip(
            title: 'Lonavala Ridge Escapade',
            destination: 'Lonavala',
            duration: '2 days',
            tags: const ['Hill Station', 'Electric Train'],
          ),
        ],
      );
    } else if (_selectedFilter == 1) {
      if (past.isNotEmpty) {
        return past.map((trip) => _styledTripCard(
          context,
          title: trip.title,
          dateStr: '${trip.travelDates} • ${trip.durationDays} days',
          imageUrl: _imageForDestination(trip.destination.isNotEmpty ? trip.destination : trip.title),
          tags: [
            'Completed',
            '${fixed(trip.co2SavedKg, 1)} kg CO₂ saved',
          ],
          onTap: () => _openTripDetail(trip),
        )).toList();
      }
      return _emptyStateWithInspirations(
        context,
        title: 'No past trips recorded',
        subtitle: 'Completed journeys with your logged carbon savings will appear here.',
        inspirations: [
          _InspirationTrip(
            title: 'Alibaug Coastal Retreat',
            destination: 'Alibaug',
            duration: '3 days',
            tags: const ['Beach', 'EV Ferry'],
          ),
          _InspirationTrip(
            title: 'Rishikesh Yoga Sanctuary',
            destination: 'Rishikesh',
            duration: '4 days',
            tags: const ['Wellness', 'Clean Air'],
          ),
        ],
      );
    } else {
      return _emptyStateWithInspirations(
        context,
        title: 'No saved trips bookmarked',
        subtitle: 'Save inspiring itineraries from Yatri AI to access them offline anytime.',
        inspirations: [
          _InspirationTrip(
            title: 'Goa Heritage & Spice Farms',
            destination: 'Goa',
            duration: '4 days',
            tags: const ['Eco Stays', 'Local Culture'],
          ),
          _InspirationTrip(
            title: 'Jaipur Solar & Heritage Circuit',
            destination: 'Jaipur',
            duration: '3 days',
            tags: const ['Heritage', 'Solar Transport'],
          ),
        ],
      );
    }
  }

  List<Widget> _emptyStateWithInspirations(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<_InspirationTrip> inspirations,
  }) {
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFFE8F8F0),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.travel_explore_rounded,
                color: Color(0xFF00A86B),
                size: 28,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Row(
          children: const [
            Icon(Icons.auto_awesome_rounded, size: 15, color: Color(0xFF00A86B)),
            SizedBox(width: 6),
            Text(
              'Recommended Destinations',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
      ...inspirations.map((item) => _styledTripCard(
        context,
        title: item.title,
        dateStr: 'Suggested • ${item.duration}',
        imageUrl: _imageForDestination(item.destination),
        tags: item.tags,
        onTap: () => _quickPlan(item.destination),
      )),
    ];
  }

  Widget _styledTripCard(
    BuildContext context, {
    required String title,
    required String dateStr,
    required String imageUrl,
    required List<String> tags,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFE2E8F0),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    width: 76,
                    height: 74,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 76,
                      height: 74,
                      color: const Color(0xFFE8F8F0),
                      child: const Icon(
                        Icons.landscape_rounded,
                        color: Color(0xFF00A86B),
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_rounded,
                            size: 12,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dateStr,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: tags.map((tag) {
                          return Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F8F0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                color: Color(0xFF00A86B),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InspirationTrip {
  const _InspirationTrip({
    required this.title,
    required this.destination,
    required this.duration,
    required this.tags,
  });

  final String title;
  final String destination;
  final String duration;
  final List<String> tags;
}
