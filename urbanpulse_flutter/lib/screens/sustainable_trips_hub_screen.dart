import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/formatting.dart';
import '../core/routes.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

/// Screen 6: "Sustainable Trips Hub"
/// Travel greener, Leave a better tomorrow.
class SustainableTripsHubScreen extends StatelessWidget {
  const SustainableTripsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final trips = AppScope.of(context).trips.getTrips();
    final upcoming = trips.where((t) => !t.isCompleted).toList();
    final totalCo2 = trips.fold<double>(0, (sum, t) => sum + t.co2SavedKg);
    final totalPulse = trips.fold<int>(0, (sum, t) => sum + t.pulsePointsEarned);

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sustainable Trips Hub',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Travel greener, Leave a better tomorrow.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.surfaceLightBorder, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // 3-Metric Stats Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceLightBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _metricColumn(
                  icon: Icons.eco_rounded,
                  iconColor: const Color(0xFF00A86B),
                  value: '${fixed(totalCo2, 1)} kg',
                  label: 'CO2 avoided',
                ),
                Container(width: 1, height: 38, color: AppColors.surfaceLightBorder),
                _metricColumn(
                  icon: Icons.park_rounded,
                  iconColor: const Color(0xFF00A86B),
                  value: '${upcoming.length}',
                  label: 'Active trips',
                ),
                Container(width: 1, height: 38, color: AppColors.surfaceLightBorder),
                _metricColumn(
                  icon: Icons.star_rounded,
                  iconColor: const Color(0xFFFB8C00),
                  value: '$totalPulse',
                  label: 'Pulse points',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Plan New Trip with Yatri AI Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
                HomeTabController.maybeOf(context)?.switchToTab(3);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18, color: Colors.white),
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

          // Why Sustainable Travel? Section
          const Text(
            'Why Sustainable Travel?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _pillarCard(
                  context,
                  title: 'Eco Stays',
                  subtitle: 'Verified green hotels',
                  icon: Icons.eco_rounded,
                  iconColor: const Color(0xFF00A86B),
                  iconBg: const Color(0xFFE8F8F0),
                  route: Routes.hospitality,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _pillarCard(
                  context,
                  title: 'Green Routes',
                  subtitle: 'Low emission routes',
                  icon: Icons.alt_route_rounded,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  route: Routes.greenRoutePlanner,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _pillarCard(
                  context,
                  title: 'Green Transport',
                  subtitle: 'Public & EV options',
                  icon: Icons.directions_bus_rounded,
                  iconColor: const Color(0xFF059669),
                  iconBg: const Color(0xFFECFDF5),
                  route: Routes.greenRoutePlanner,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _pillarCard(
                  context,
                  title: 'Local Impact',
                  subtitle: 'Support local communities',
                  icon: Icons.people_alt_rounded,
                  iconColor: const Color(0xFF0D9488),
                  iconBg: const Color(0xFFCCFBF1),
                  route: Routes.achievements,
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),

          // Featured Eco Destinations Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Featured Eco Destinations',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              InkWell(
                onTap: () {
                  showToast(context, 'Explore all verified eco destinations');
                },
                child: const Text(
                  'See all >',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF00A86B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Lonavala Featured Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.surfaceLightBorder, width: 1),
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
                    'https://images.unsplash.com/photo-1570789210967-2cac24afeb00?w=600&auto=format&fit=crop&q=80',
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 72,
                      height: 72,
                      color: const Color(0xFFE8F8F0),
                      child: const Icon(Icons.terrain_rounded, color: Color(0xFF00A86B), size: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Lonavala',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Waterfalls & ridge trails',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: const [
                          Icon(Icons.location_on_rounded, size: 12, color: Color(0xFF00A86B)),
                          SizedBox(width: 3),
                          Text(
                            '28 km away • AQI 67',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF00A86B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    HomeTabController.maybeOf(context)?.switchToTab(3);
                    showToast(context, 'Ask Yatri AI: "Plan a trip to Lonavala"');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00A86B),
                    side: const BorderSide(color: Color(0xFF00A86B), width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  child: const Text(
                    'Plan',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
        Icon(icon, color: iconColor, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _pillarCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String route,
  }) {
    return InkWell(
      onTap: () => Navigator.of(context).pushNamed(route),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceLightBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
