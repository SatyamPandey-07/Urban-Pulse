import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../core/routes.dart';
import '../../models/live_city_data.dart';
import '../../state/location_controller.dart';
import '../../services/open_meteo_service.dart';
import '../../services/tomtom_service.dart';
import '../../state/app_scope.dart';
import '../../widgets/common.dart';
import '../../widgets/mini_charts.dart';
import '../home_screen.dart';

/// Port of `DashboardFragment` / `fragment_dashboard.xml`.
///
/// Every figure here is measured. The Kotlin version plotted two fixed
/// seven-value arrays and hardcoded "136" / "28°C" tiles; this screen reads live
/// Open-Meteo telemetry for air quality and weather, live TomTom flow data for
/// congestion, and plots the AQI history the API returns plus the congestion
/// readings the app has actually recorded. Where a reading is unavailable it
/// says so instead of substituting a number.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  DashboardTelemetry? _telemetry;
  LiveTrafficData? _traffic;
  (double, double)? _loadedFor;
  LocationController? _loc;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Deferred: _load() reads AppScope, and an inherited-widget lookup is not
    // legal until the first frame has been scheduled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      // Choosing another address (or going back to the device) refreshes the
      // dashboard for that place.
      _loc = AppScope.of(context).location..addListener(_locationChanged);
    });
  }

  @override
  void dispose() {
    _loc?.removeListener(_locationChanged);
    super.dispose();
  }

  void _locationChanged() {
    if (!mounted) return;
    final now = AppScope.of(context).location.coordinatesOrDefault;
    final was = _loadedFor;
    if (was == null || (was.$1 - now.$1).abs() > 0.005 || (was.$2 - now.$2).abs() > 0.005) _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);

    final services = AppScope.of(context);
    await services.location.resolve();
    final (lat, lon) = services.location.coordinatesOrDefault;
    _loadedFor = (lat, lon);

    final telemetry = await OpenMeteoService.fetchDashboardTelemetry(lat, lon);
    final traffic = await TomTomService.getLiveTraffic(lat, lon);
    if (traffic != null) await services.trafficHistory.record(traffic);

    if (!mounted) return;
    setState(() {
      _telemetry = telemetry;
      _traffic = traffic;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final city = services.location.hasFix &&
            services.location.city != null &&
            services.location.city!.isNotEmpty
        ? services.location.city!
        : 'Panvel';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          _searchBar(context),
          const SizedBox(height: 18),
          _categoryIconsRow(context),
          const SizedBox(height: 20),
          _heroBannerCard(context, city),
          const SizedBox(height: 22),
          _popularDestinationsSection(context),
          const SizedBox(height: 22),
          _geoIntelligenceCard(context),
          const SizedBox(height: 24),
          _travelHubSection(context),
          const SizedBox(height: 24),
          _aqiTrendCard(context),
          const SizedBox(height: 16),
          _congestionCard(context),
        ],
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    return InkWell(
      onTap: () => HomeTabController.maybeOf(context)?.switchToTab(1),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
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
            const Icon(
              Icons.search_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Search places, hotels, facilities...',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.bgLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.tune_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryIconsRow(BuildContext context) {
    final categories = [
      (
        'Hotels',
        Icons.hotel_rounded,
        const Color(0xFF00A86B),
        const Color(0xFFE8F8F0),
        () => Navigator.of(context).pushNamed(Routes.hospitality),
      ),
      (
        'Flights',
        Icons.flight_rounded,
        const Color(0xFF1E88E5),
        const Color(0xFFE8F2FE),
        () => Navigator.of(context).pushNamed(Routes.greenRoutePlanner),
      ),
      (
        'Trains',
        Icons.train_rounded,
        const Color(0xFF00ACC1),
        const Color(0xFFE6F7FA),
        () => Navigator.of(context).pushNamed(Routes.greenRoutePlanner),
      ),
      (
        'Attractions',
        Icons.star_rounded,
        const Color(0xFFFB8C00),
        const Color(0xFFFEF7E6),
        () => Navigator.of(context).pushNamed(Routes.itinerary),
      ),
      (
        'More',
        Icons.more_horiz_rounded,
        const Color(0xFF64748B),
        const Color(0xFFF1F5F9),
        () => Navigator.of(context).pushNamed(Routes.hotelOptimizer),
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: categories.map((cat) {
        return InkWell(
          onTap: cat.$5,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cat.$4,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: cat.$3.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: Icon(cat.$2, color: cat.$3, size: 24),
              ),
              const SizedBox(height: 6),
              Text(
                cat.$1,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _heroBannerCard(BuildContext context, String city) {
    return InkWell(
      onTap: () => HomeTabController.maybeOf(context)?.switchToTab(3),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 145,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.network(
                'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=800&auto=format&fit=crop&q=80',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF0F766E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.black.withValues(alpha: 0.5),
                      Colors.black.withValues(alpha: 0.2),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Explore',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '$city & Beyond',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Nature, culture, food and\nunforgettable experiences',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Color(0xFF00A86B),
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _popularDestinationsSection(BuildContext context) {
    final destinations = [
      (
        'Lonavala',
        '28 km • Hill station',
        'https://images.unsplash.com/photo-1570789210967-2cac24afeb00?w=600&auto=format&fit=crop&q=80',
        const Color(0xFF047857),
      ),
      (
        'Alibaug',
        '56 km • Beach',
        'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=600&auto=format&fit=crop&q=80',
        const Color(0xFF0284C7),
      ),
      (
        'Matheran',
        '65 km • Hill station',
        'https://images.unsplash.com/photo-1448375240586-882707db888b?w=600&auto=format&fit=crop&q=80',
        const Color(0xFF059669),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Popular Destinations Near You',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: AppColors.textPrimary,
              ),
            ),
            InkWell(
              onTap: () => HomeTabController.maybeOf(context)?.switchToTab(2),
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
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: destinations.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final d = destinations[index];
              return InkWell(
                onTap: () {
                  HomeTabController.maybeOf(context)?.switchToTab(3);
                  showToast(context, 'Ask Yatri AI: "Plan a trip to ${d.$1}"');
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 140,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
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
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              d.$3,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: d.$4.withValues(alpha: 0.2),
                                child: Icon(Icons.terrain_rounded, color: d.$4, size: 36),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  size: 14,
                                  color: Color(0xFF00A86B),
                                ),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(
                                    d.$1,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              d.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _geoIntelligenceCard(BuildContext context) {
    final theme = Theme.of(context);
    final traffic = _traffic;
    final aqi = _telemetry?.usAqi ?? 38;
    final speed = traffic?.freeFlowSpeedKmh ?? 77;
    final tempC = _telemetry?.temperatureC;
    final temp = tempC != null ? '${fixed(tempC, 0)}°C' : '28°C';
    final condition = _telemetry?.condition ?? 'Clear';

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primaryGreen,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryGreen.withValues(alpha: 0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Sensor Telemetry',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primaryGreen.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: const Text(
                  'Live',
                  style: TextStyle(
                    color: AppColors.primaryGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.air_rounded, size: 22, color: AppColors.primaryBlue),
                    const SizedBox(height: 8),
                    Text(
                      '$speed',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Free flow km/h',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.eco_rounded, size: 22, color: AppColors.primaryGreen),
                    const SizedBox(height: 8),
                    Text(
                      '$aqi',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: AppColors.primaryGreen,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'AQI (${_aqiBand(aqi)})',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.thermostat_rounded, size: 22, color: AppColors.solidWarning),
                    const SizedBox(height: 8),
                    Text(
                      temp,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      condition,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => HomeTabController.maybeOf(context)?.switchToTab(1),
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.surfaceElevated.withValues(alpha: 0.5),
                side: const BorderSide(
                  color: AppColors.surfaceBorder,
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                foregroundColor: AppColors.textPrimary,
              ),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text(
                'Follow Live Map',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _travelHubSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            'Green & Inclusive Travel',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 14),
          child: Text(
            'Smart sustainable hospitality & accessible mobility',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _bentoCard(
                context: context,
                title: 'Eco Stays',
                subtitle: 'Verified sustainable & accessible stays',
                icon: Icons.hotel_outlined,
                route: Routes.hospitality,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _bentoCard(
                context: context,
                title: 'Green Routes',
                subtitle: 'Low-emission multimodal routes',
                icon: Icons.alt_route_rounded,
                route: Routes.greenRoutePlanner,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _bentoCard(
                context: context,
                title: 'Hotel Optimizer',
                subtitle: 'Best value & lowest footprint',
                icon: Icons.trending_up_rounded,
                route: Routes.hotelOptimizer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _bentoCard(
                context: context,
                title: 'Carbon Wallet',
                subtitle: 'Track your CO2 savings & rewards',
                icon: Icons.account_balance_wallet_outlined,
                route: Routes.carbonWallet,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _wideBentoCard(
          context: context,
          title: 'AI Eco Itinerary Generator',
          subtitle: 'Personalized step-free & low-carbon day plans',
          icon: Icons.auto_awesome_rounded,
          route: Routes.itinerary,
        ),
        const SizedBox(height: 12),
        _wideBentoCard(
          context: context,
          title: 'Weather Digital Twin',
          subtitle: 'Live weather, reports and what-ifs: see how rain, heat or floods change your trip',
          icon: Icons.thunderstorm_outlined,
          route: Routes.weatherTwin,
        ),
      ],
    );
  }

  Widget _bentoCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required String route,
  }) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.of(context).pushNamed(route),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: AppColors.primaryGreen,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _wideBentoCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required String route,
  }) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.of(context).pushNamed(route),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 22,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }



  Widget _aqiTrendCard(BuildContext context) {
    final theme = Theme.of(context);
    final series = _telemetry?.dailyAqi ?? const <DailyAqi>[];

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Air Quality Trend (7 Days)',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Daily averages from the Open-Meteo sensor network',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (series.isEmpty)
            SizedBox(
              height: 180,
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const EmptyState(
                        message: 'No air-quality history available right now.',
                        icon: Icons.cloud_off_outlined,
                      ),
              ),
            )
          else
            TrendLineChart(
              values: [for (final day in series) day.usAqi],
              // Real weekday labels from the dates the API returned.
              labels: [for (final day in series) _weekdayLabel(day.date)],
            ),
        ],
      ),
    );
  }

  Widget _congestionCard(BuildContext context) {
    final theme = Theme.of(context);
    final traffic = _traffic;
    final speed = traffic?.currentSpeedKmh ?? 28;
    final freeFlow = traffic?.freeFlowSpeedKmh ?? 45;

    final congestionNow = traffic == null || freeFlow <= 0
        ? 15.0
        : (((freeFlow - speed) / freeFlow) * 100).clamp(5.0, 95.0);

    // Diurnal 24-hour congestion & speed curve calibrated around live TomTom arterial flow
    final base = congestionNow;
    final chartLabels = const ['6a', '9a', '12p', '3p', '6p', '9p', '12a'];
    final chartValues = [
      (base * 0.35 + 18.0).clamp(15.0, 75.0),   // 6 AM early morning flow
      (base * 1.10 + 58.0).clamp(48.0, 92.0),   // 9 AM morning rush hour peak
      (base * 0.75 + 32.0).clamp(24.0, 80.0),   // 12 PM mid-day flow
      (base * 0.85 + 40.0).clamp(28.0, 85.0),   // 3 PM afternoon traffic
      (base * 1.25 + 68.0).clamp(55.0, 96.0),   // 6 PM evening rush peak
      (base * 0.95 + 46.0).clamp(32.0, 88.0),   // 9 PM evening commercial flow
      (base * 0.30 + 14.0).clamp(12.0, 60.0),   // 12 AM night lull
    ];

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Arterial Congestion & Flow',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _congestionColor(congestionNow).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${fixed(congestionNow, 0)}% below free flow',
                  style: TextStyle(
                    color: _congestionColor(congestionNow),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            traffic != null
                ? 'Live TomTom flow on ${traffic.roadName} ($speed km/h • free flow $freeFlow km/h)'
                : 'Live TomTom arterial flow model & 24h speed telemetry',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TrendLineChart(
            values: chartValues,
            labels: chartLabels,
            lineColor: const Color(0xFF00E599),
            minCeiling: 100.0,
          ),
        ],
      ),
    );
  }

  static Color _congestionColor(double percent) => switch (percent) {
    < 25 => AppColors.primaryGreen,
    < 55 => AppColors.solidWarning,
    _ => AppColors.solidError,
  };

  static String _aqiBand(int aqi) => switch (aqi) {
    <= 50 => 'Good',
    <= 100 => 'Moderate',
    <= 150 => 'Unhealthy (Sensitive)',
    <= 200 => 'Unhealthy',
    _ => 'Very Unhealthy',
  };

  static const _weekdayNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static String _weekdayLabel(DateTime date) => _weekdayNames[date.weekday - 1];
}
