import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../core/routes.dart';
import '../../services/location_service.dart';
import '../../services/open_meteo_service.dart';
import '../../state/app_scope.dart';
import '../../widgets/common.dart';
import '../../widgets/mini_charts.dart';
import '../home_screen.dart';

/// Port of `DashboardFragment` / `fragment_dashboard.xml`.
///
/// The Kotlin charts plotted a fixed array of seven values. Here the same two
/// cards are backed by the live Open-Meteo telemetry the app already fetches, so
/// the AQI figure, the weather figure and the 7-day AQI trend are real readings;
/// the screen says plainly when they can't be loaded rather than showing
/// invented numbers.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  static const _weekdayLabels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const _trafficHours = [
    '6 AM',
    '8 AM',
    '10 AM',
    '12 PM',
    '3 PM',
    '6 PM',
    '9 PM',
  ];

  DashboardTelemetry? _telemetry;
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
    final position = await AppScope.of(context).location.currentPosition();
    final telemetry = await OpenMeteoService.fetchDashboardTelemetry(
      position?.latitude ?? LocationService.defaultLat,
      position?.longitude ?? LocationService.defaultLon,
    );
    if (!mounted) return;
    setState(() {
      _telemetry = telemetry;
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
          _trafficForecastCard(context),
        ],
      ),
    );
  }

  Widget _geoIntelligenceCard(BuildContext context) {
    final theme = Theme.of(context);
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
            'Live Traffic • Sensor Matrix Active',
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
    final series = _telemetry?.dailyAqiAverages ?? const <double>[];
    // The API returns the past seven days plus today; keep the last seven.
    final trimmed = series.length > 7
        ? series.sublist(series.length - 7)
        : series;

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
            'Daily sensor averages',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (trimmed.isEmpty)
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
              values: trimmed,
              labels: _weekdayLabels.sublist(0, trimmed.length),
            ),
        ],
      ),
    );
  }

  Widget _trafficForecastCard(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '12h Traffic Forecast',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Typical arterial congestion by hour',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const ForecastBarChart(
            // The same seven-point congestion profile the Kotlin BarChart plotted.
            values: [25, 40, 75, 88, 60, 92, 50],
            labels: _trafficHours,
            barColor: AppColors.primaryGreen,
          ),
        ],
      ),
    );
  }

  static String _aqiBand(int aqi) => switch (aqi) {
    <= 50 => 'Good',
    <= 100 => 'Moderate',
    <= 150 => 'Unhealthy (Sensitive)',
    <= 200 => 'Unhealthy',
    _ => 'Very Unhealthy',
  };
}
