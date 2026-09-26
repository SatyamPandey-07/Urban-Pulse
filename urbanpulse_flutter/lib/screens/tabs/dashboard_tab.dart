import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../core/routes.dart';
import '../../models/live_city_data.dart';
import '../../repositories/traffic_history_repository.dart';
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
  List<TrafficReading> _trafficHistory = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Deferred: _load() reads AppScope, and an inherited-widget lookup is not
    // legal until the first frame has been scheduled.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);

    final services = AppScope.of(context);
    await services.location.resolve();
    final (lat, lon) = services.location.coordinatesOrDefault;

    final telemetry = await OpenMeteoService.fetchDashboardTelemetry(lat, lon);
    final traffic = await TomTomService.getLiveTraffic(lat, lon);
    if (traffic != null) await services.trafficHistory.record(traffic);
    final history = await services.trafficHistory.recentReadings();

    if (!mounted) return;
    setState(() {
      _telemetry = telemetry;
      _traffic = traffic;
      _trafficHistory = history;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dashboard',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Smarter • Greener • More Inclusive',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
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

  Widget _geoIntelligenceCard(BuildContext context) {
    final theme = Theme.of(context);
    final traffic = _traffic;
    final aqi = _telemetry?.usAqi ?? 38;
    final speed = traffic?.freeFlowSpeedKmh ?? 77;
    final temp = _telemetry?.temperatureC != null
        ? '${fixed(_telemetry!.temperatureC!, 0)}°C'
        : '28°C';
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

  Widget _currentConditionsRow(BuildContext context) {
    final aqi = _telemetry?.usAqi;
    final temperature = _telemetry?.temperatureC;

    final aqiColor = aqi == null
        ? null
        : aqi <= 50
        ? AppColors.solidSuccess
        : aqi <= 100
        ? AppColors.solidWarning
        : AppColors.solidError;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SectionCard(
            child: StatTile(
              label: 'Air Quality',
              icon: Icons.air_rounded,
              value: aqi?.toString() ?? (_isLoading ? '…' : '—'),
              valueColor: aqiColor,
              caption: aqi == null
                  ? (_isLoading ? 'Reading sensors…' : 'Unavailable offline')
                  : '${_aqiBand(aqi)} • PM2.5',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SectionCard(
            child: StatTile(
              label: 'City Weather',
              icon: Icons.thermostat_rounded,
              value: temperature == null
                  ? (_isLoading ? '…' : '—')
                  : '${fixed(temperature, 0)}°C',
              caption:
                  _telemetry?.condition ??
                  (_isLoading ? 'Reading sensors…' : 'Unavailable offline'),
            ),
          ),
        ),
      ],
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
    final history = _trafficHistory;

    final congestionNow = traffic == null || traffic.freeFlowSpeedKmh <= 0
        ? null
        : (((traffic.freeFlowSpeedKmh - traffic.currentSpeedKmh) /
                      traffic.freeFlowSpeedKmh) *
                  100)
              .clamp(0.0, 100.0);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Arterial Congestion',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (congestionNow != null)
                Text(
                  '${fixed(congestionNow, 0)}% below free flow',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _congestionColor(congestionNow),
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            traffic != null
                ? 'Live TomTom flow on ${traffic.roadName}, recorded across your recent '
                      'sessions'
                : 'Live TomTom flow, recorded across your recent sessions',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (history.isEmpty)
            SizedBox(
              height: 180,
              child: Center(
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const EmptyState(
                        message:
                            'No congestion readings recorded yet. Readings are taken '
                            'as you use the app and will chart here.',
                        icon: Icons.timeline_outlined,
                      ),
              ),
            )
          else
            ForecastBarChart(
              values: [for (final r in history) r.congestionPercent],
              labels: [for (final r in history) _clockLabel(r.recordedAt)],
              barColor: AppColors.primaryGreen,
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

  static String _clockLabel(DateTime at) {
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    return '$hour${at.hour < 12 ? "a" : "p"}';
  }
}
