import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/routes.dart';
import '../../models/trip_models.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTrips();
    });
  }

  void _loadTrips() {
    if (!mounted) return;
    setState(() => _trips = AppScope.of(context).trips.getTrips());
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
          imageUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=400&auto=format&fit=crop&q=80',
          tags: ['Nature', 'Eco Friendly'],
          onTap: () => _openTripDetail(trip),
        )).toList();
      }
      return [
        _styledTripCard(
          context,
          title: 'Coorg Getaway',
          dateStr: '2–5 Nov 2026 • 4 days',
          imageUrl: 'https://images.unsplash.com/photo-1506744038136-46273834b3fb?w=400&auto=format&fit=crop&q=80',
          tags: ['Nature', 'Eco Friendly'],
          onTap: () => _quickPlan('Coorg'),
        ),
        _styledTripCard(
          context,
          title: 'Lonavala',
          dateStr: '28 Oct 2026 • 2 days',
          imageUrl: 'https://images.unsplash.com/photo-1570789210967-2cac24afeb00?w=400&auto=format&fit=crop&q=80',
          tags: ['Hill Station', 'Adventure'],
          onTap: () => _quickPlan('Lonavala'),
        ),
      ];
    } else if (_selectedFilter == 1) {
      if (past.isNotEmpty) {
        return past.map((trip) => _styledTripCard(
          context,
          title: trip.title,
          dateStr: '${trip.travelDates} • ${trip.durationDays} days',
          imageUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400&auto=format&fit=crop&q=80',
          tags: ['Beach', 'Relaxation'],
          onTap: () => _openTripDetail(trip),
        )).toList();
      }
      return [
        _styledTripCard(
          context,
          title: 'Alibaug',
          dateStr: '12 Nov 2026 • 3 days',
          imageUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400&auto=format&fit=crop&q=80',
          tags: ['Beach', 'Relaxation'],
          onTap: () => _quickPlan('Alibaug'),
        ),
      ];
    } else {
      return [
        _styledTripCard(
          context,
          title: 'Matheran',
          dateStr: '28 Dec 2026 • 2 days',
          imageUrl: 'https://images.unsplash.com/photo-1448375240586-882707db888b?w=400&auto=format&fit=crop&q=80',
          tags: ['Hill Station', 'Nature'],
          onTap: () => _quickPlan('Matheran'),
        ),
      ];
    }
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.surfaceLightBorder,
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
                color: AppColors.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }







}
