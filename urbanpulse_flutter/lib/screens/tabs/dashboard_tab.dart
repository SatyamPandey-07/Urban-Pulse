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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 24),
            child: Text(
              'Dashboard',
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _geoIntelligenceCard(context),
          const SizedBox(height: 16),
          _travelHubCard(context),
          const SizedBox(height: 16),
          _currentConditionsRow(context),
          const SizedBox(height: 16),
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
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Real-Time Geo-Intelligence',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            traffic != null
                ? '${traffic.roadName} • ${traffic.currentSpeedKmh} km/h now '
                      '(free flow ${traffic.freeFlowSpeedKmh} km/h)'
                : _isLoading
                ? 'Reading the live sensor matrix…'
                : 'Live traffic unavailable — check your connection or TomTom key',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () => HomeTabController.maybeOf(context)?.switchToTab(1),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Follow Live Map'),
          ),
        ],
      ),
    );
  }

  Widget _travelHubCard(BuildContext context) {
    final theme = Theme.of(context);
    Widget action(String label, IconData icon, String route) =>
        FilledButton.tonalIcon(
          onPressed: () => Navigator.of(context).pushNamed(route),
          icon: Icon(icon, size: 18),
          label: Text(label, overflow: TextOverflow.ellipsis),
        );

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Green & Inclusive Travel',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Smart sustainable hospitality & accessible mobility',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: action(
                  'Eco Stays',
                  Icons.hotel_outlined,
                  Routes.hospitality,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: action(
                  'Green Routes',
                  Icons.alt_route,
                  Routes.greenRoutePlanner,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: action(
                  'Hotel Optimizer',
                  Icons.insights_outlined,
                  Routes.hotelOptimizer,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: action(
                  'Carbon Wallet',
                  Icons.account_balance_wallet_outlined,
                  Routes.carbonWallet,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: action(
              'AI Eco Itinerary Generator',
              Icons.celebration_outlined,
              Routes.itinerary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _currentConditionsRow(BuildContext context) {
    final aqi = _telemetry?.usAqi;
    final temperature = _telemetry?.temperatureC;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SectionCard(
            child: StatTile(
              label: 'Air Quality',
              value: aqi?.toString() ?? (_isLoading ? '…' : '—'),
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
