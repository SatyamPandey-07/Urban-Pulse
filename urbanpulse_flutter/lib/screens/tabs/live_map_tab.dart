import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../models/live_city_data.dart';
import '../../services/location_service.dart';
import '../../services/open_meteo_service.dart';
import '../../services/tomtom_service.dart';
import '../../state/app_scope.dart';
import '../../widgets/common.dart';
import 'live_map_html.dart';

/// Port of `LiveMapFragment` / `fragment_live_map.xml`.
///
/// Keeps the original architecture: a Leaflet map in a WebView, driven by
/// injected JavaScript, with two *real* TomTom routes (an `eco` green corridor
/// and a traffic-aware `fastest` car route) and a live Open-Meteo AQI reading
/// feeding the comparison HUD.
class LiveMapTab extends StatefulWidget {
  const LiveMapTab({super.key});

  @override
  State<LiveMapTab> createState() => _LiveMapTabState();
}

class _LiveMapTabState extends State<LiveMapTab> {
  late final WebViewController _webView;
  final _searchController = TextEditingController();

  // Initial viewport, replaced by the real fix as soon as one resolves.
  double _currentLat = LocationService.defaultLat;
  double _currentLon = LocationService.defaultLon;
  bool _isTrafficEnabled = true;
  bool _isRouting = false;

  _RouteComparison? _comparison;
  String _statusTitle = 'Dual Route Comparison';
  String _statusSubtitle =
      'Comparing Green Electric Corridor vs Standard Petrol Cab';

  List<LivePoiResult> _searchResults = const [];
  LivePoiResult? _nearestHospital;

  @override
  void initState() {
    super.initState();
    _webView = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.bgDark)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _centerMap(_currentLat, _currentLon, 13);
            // Draw the real nearby POIs and the live flow segment for wherever
            // the traveler actually is. Routes are drawn once they pick a
            // destination, rather than to a fixed demo coordinate.
            _loadNearbyPois();
          },
        ),
      )
      ..loadHtmlString(liveMapHtml, baseUrl: 'https://unpkg.com');
    // Deferred: _locateUser() reads AppScope, and an inherited-widget lookup is
    // not legal until the first frame has been scheduled.
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateUser());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _locateUser({int zoom = 14, bool force = false}) async {
    final location = AppScope.of(context).location;
    await location.resolve(force: force);
    if (!location.hasFix || !mounted) return;
    setState(() {
      _currentLat = location.latitude!;
      _currentLon = location.longitude!;
    });
    await _centerMap(_currentLat, _currentLon, zoom);
    await _loadNearbyPois();
  }

  /// Pulls real nearby hospitals and EV charging points from the TomTom POI
  /// search and draws them, plus the live flow segment for the corridor the user
  /// is on. The Kotlin page had four pins and two polylines written into the
  /// HTML at fixed coordinates.
  Future<void> _loadNearbyPois() async {
    final hospitals = await TomTomService.searchNearbyPoi(
      'hospital',
      _currentLat,
      _currentLon,
      limit: 4,
    );
    final chargers = await TomTomService.searchNearbyPoi(
      'electric vehicle station',
      _currentLat,
      _currentLon,
      limit: 4,
    );

    final pins = [
      for (final poi in hospitals)
        {
          'lat': poi.lat,
          'lon': poi.lon,
          'code': 'MED',
          'title': poi.name,
          'desc': poi.address,
          'bg': '#EF4444',
        },
      for (final poi in chargers)
        {
          'lat': poi.lat,
          'lon': poi.lon,
          'code': 'EV',
          'title': poi.name,
          'desc': poi.address,
          'bg': '#38BDF8',
        },
    ];

    if (!mounted) return;
    setState(() => _nearestHospital = hospitals.firstOrNull);
    await _webView.runJavaScript('window.setPois(${jsonEncode(pins)});');
    await _drawLiveTrafficSegment();
  }

  /// Draws the real TomTom flow segment for the user's current corridor.
  Future<void> _drawLiveTrafficSegment() async {
    final traffic = await TomTomService.getLiveTrafficSegment(
      _currentLat,
      _currentLon,
    );
    if (traffic == null || traffic.geometry.length < 2) return;
    final flow = traffic.data;
    final congestion = flow.freeFlowSpeedKmh <= 0
        ? 0.0
        : (((flow.freeFlowSpeedKmh - flow.currentSpeedKmh) /
                      flow.freeFlowSpeedKmh) *
                  100)
              .clamp(0.0, 100.0);
    final label =
        '${flow.roadName}: ${flow.currentSpeedKmh} km/h '
        '(free flow ${flow.freeFlowSpeedKmh} km/h)';
    await _webView.runJavaScript(
      'window.setTrafficSegment('
      '${jsonEncode(traffic.geometry)}, '
      '${jsonEncode(label)}, '
      '${congestion.toStringAsFixed(1)});',
    );
  }

  /// Routes to the nearest real result for a category, instead of a coordinate
  /// pair written into the chip handler.
  Future<void> _routeToNearest(String query, String emptyMessage) async {
    final results = await TomTomService.searchNearbyPoi(
      query,
      _currentLat,
      _currentLon,
      limit: 1,
    );
    if (!mounted) return;
    final nearest = results.firstOrNull;
    if (nearest == null) {
      showToast(context, emptyMessage);
      return;
    }
    await _calculateAndDrawDualRoutes(nearest.lat, nearest.lon, nearest.name);
  }

  Future<void> _centerMap(double lat, double lon, int zoom) =>
      _webView.runJavaScript('window.setCenter($lat, $lon, $zoom);');

  Future<void> _toggleTraffic() async {
    setState(() => _isTrafficEnabled = !_isTrafficEnabled);
    await _webView.runJavaScript(
      'window.toggleTrafficOverlay($_isTrafficEnabled);',
    );
    if (!mounted) return;
    showToast(context, 'Traffic Overlay: ${_isTrafficEnabled ? "ON" : "OFF"}');
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    final results = await TomTomService.searchNearbyPoi(
      query,
      _currentLat,
      _currentLon,
      limit: 5,
    );
    if (!mounted) return;
    if (results.isEmpty) {
      setState(() => _searchResults = const []);
      showToast(
        context,
        'No places matched "$query" — check your connection or TomTom key.',
      );
      return;
    }
    setState(() => _searchResults = results);
  }

  void _selectSearchResult(LivePoiResult result) {
    setState(() {
      _searchResults = const [];
      _searchController.text = result.name;
    });
    FocusScope.of(context).unfocus();
    _calculateAndDrawDualRoutes(result.lat, result.lon, result.name);
  }

  /// Fetches the two real routes plus live AQI, computes the authentic
  /// Maharashtra taxi fare and per-km carbon figures, then hands the geometry to
  /// Leaflet.
  Future<void> _calculateAndDrawDualRoutes(
    double destLat,
    double destLon,
    String destName,
  ) async {
    setState(() {
      _isRouting = true;
      _statusTitle = 'Routing to $destName';
      _statusSubtitle =
          'Fetching real TomTom multi-routing & Open-Meteo AQI telemetry...';
    });

    final currentAqi = await OpenMeteoService.fetchCurrentUsAqi(
      _currentLat,
      _currentLon,
    );

    final normal = await TomTomService.calculateRoute(
      fromLat: _currentLat,
      fromLon: _currentLon,
      toLat: destLat,
      toLon: destLon,
      routeType: 'fastest',
      traffic: true,
      travelMode: 'car',
    );
    final green = await TomTomService.calculateRoute(
      fromLat: _currentLat,
      fromLon: _currentLon,
      toLat: destLat,
      toLon: destLon,
      routeType: 'eco',
      traffic: false,
    );

    // With no live geometry, fall back to a straight-line corridor between the
    // two points so the comparison still renders — and say so in the HUD.
    final isEstimated = normal == null || green == null;
    final normalPoints = normal?.points.isNotEmpty == true
        ? normal!.points
        : _fallbackGeometry(
            destLat,
            destLon,
            latNudge: -0.005,
            lonNudge: 0.006,
          );
    final greenPoints = green?.points.isNotEmpty == true
        ? green!.points
        : _fallbackGeometry(
            destLat,
            destLon,
            latNudge: 0.004,
            lonNudge: -0.003,
          );

    final distanceKm = normal?.distanceKm ?? green?.distanceKm ?? 12.6;
    final normalTimeMin = (normal?.durationMin ?? 34).coerceAtLeast(10);
    final greenTimeMin = (green?.durationMin ?? 22).coerceAtLeast(8);

    // Standard petrol cab, MH official taxi formula: base ₹28 + ₹18.5/km.
    final normalFare = (28.0 + distanceKm * 18.5).round();
    final normalCo2 = (distanceKm * 160.0).round(); // 160g CO2/km

    // Green transit (Metro Line 3 / suburban rail / electric bus) slab fares.
    final greenFare = switch (distanceKm) {
      <= 5.0 => 10,
      <= 12.0 => 20,
      <= 25.0 => 30,
      _ => 45,
    };
    final greenCo2 = (distanceKm * 14.0).round(); // 14g CO2/km

    final comparison = _RouteComparison(
      greenSummary:
          '$greenTimeMin mins • ${rupees(greenFare)} • ${greenCo2}g CO2e',
      normalSummary:
          '$normalTimeMin mins • ${rupees(normalFare)} • ${normalCo2}g CO2e',
      greenMetrics: '$greenTimeMin mins • ${rupees(greenFare)} (Metro)',
      greenCarbon: '${greenCo2}g CO2e • Step-Free',
      normalMetrics: '$normalTimeMin mins • ${rupees(normalFare)} (Cab)',
      normalCarbon: '${normalCo2}g CO2e • Congested',
      savedCo2: (normalCo2 - greenCo2).coerceAtLeast(0),
      savedFare: (normalFare - greenFare).coerceAtLeast(0),
    );

    if (!mounted) return;
    setState(() {
      _comparison = comparison;
      _isRouting = false;
      _statusTitle = 'Real Dual Routes: $destName (${fixed(distanceKm)} km)';
      _statusSubtitle = isEstimated
          ? 'Live TomTom routing unavailable — showing a straight-line estimate'
          : '🟢 Metro/E-Bus${currentAqi != null ? " (AQI $currentAqi)" : ""} vs 🔴 Petrol Cab';
    });

    await _webView.runJavaScript(
      'window.drawDualRoutes('
      '${jsonEncode(greenPoints)}, '
      '${jsonEncode(normalPoints)}, '
      '${jsonEncode(destName)}, '
      '${jsonEncode(comparison.greenSummary)}, '
      '${jsonEncode(comparison.normalSummary)});',
    );
  }

  List<List<double>> _fallbackGeometry(
    double destLat,
    double destLon, {
    required double latNudge,
    required double lonNudge,
  }) => [
    [_currentLat, _currentLon],
    [
      (_currentLat + destLat) / 2 + latNudge,
      (_currentLon + destLon) / 2 + lonNudge,
    ],
    [destLat, destLon],
  ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _webView)),
        _topOverlay(context),
        _floatingControls(context),
        _comparisonHud(context),
      ],
    );
  }

  Widget _topOverlay(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: 12,
      left: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _performSearch,
                      decoration: const InputDecoration(
                        hintText: 'Search places, facilities, destinations...',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: 'Clear search',
                      onPressed: () => setState(() {
                        _searchController.clear();
                        _searchResults = const [];
                      }),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _filterChips(context),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: Card(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final result = _searchResults[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(
                        result.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${result.address} • ${fixed(result.distanceMeters / 1000)} km',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _selectSearchResult(result),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterChips(BuildContext context) {
    // Each chip routes to the same landmark the Kotlin chip listeners used.
    // Each chip acts on real data: a live route between the user's position and
    // a real searched destination, or the live traffic overlay.
    final chips = <(String, IconData, VoidCallback)>[
      (
        'Compare Dual Routes',
        Icons.alt_route,
        () {
          final destination = _searchResults.firstOrNull ?? _nearestHospital;
          if (destination == null) {
            showToast(
              context,
              'Search for a destination first, then compare the two routes to it.',
            );
            return;
          }
          _calculateAndDrawDualRoutes(
            destination.lat,
            destination.lon,
            destination.name,
          );
        },
      ),
      (
        'Hospitals',
        Icons.local_hospital_outlined,
        () => _routeToNearest(
          'hospital',
          'No hospitals found near your location.',
        ),
      ),
      ('Traffic Flow', Icons.traffic_outlined, _toggleTraffic),
      (
        'Pharmacies',
        Icons.medication_outlined,
        () => _routeToNearest(
          'pharmacy',
          'No pharmacies found near your location.',
        ),
      ),
      (
        'Parks & Trails',
        Icons.park_outlined,
        () => _routeToNearest(
          'park',
          'No parks or trails found near your location.',
        ),
      ),
      (
        'EV Stations',
        Icons.ev_station_outlined,
        () => _routeToNearest(
          'electric vehicle station',
          'No EV charging points found near your location.',
        ),
      ),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (label, icon, onTap) = chips[index];
          return ActionChip(
            avatar: Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            label: Text(label),
            onPressed: onTap,
          );
        },
      ),
    );
  }

  /// Re-reads the live flow segment so the overlay reflects current conditions.
  Future<void> _refreshTraffic() async {
    await _drawLiveTrafficSegment();
    if (!mounted) return;
    showToast(context, 'Live traffic overlay refreshed.');
  }

  Future<void> _centreOnUser() async {
    await _locateUser(zoom: 15, force: true);
    if (!mounted) return;
    showToast(context, 'Centered at GPS location');
  }

  Widget _floatingControls(BuildContext context) => Positioned(
    right: 16,
    bottom: 240,
    child: Column(
      children: [
        FloatingActionButton.small(
          heroTag: 'map-traffic',
          tooltip: 'Toggle Traffic',
          onPressed: _toggleTraffic,
          child: const Icon(Icons.traffic_outlined),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.small(
          heroTag: 'map-refresh-traffic',
          tooltip: 'Refresh live traffic',
          onPressed: _refreshTraffic,
          child: const Icon(Icons.refresh),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'map-location',
          tooltip: 'My Location',
          onPressed: _centreOnUser,
          child: const Icon(Icons.my_location),
        ),
      ],
    ),
  );

  Widget _comparisonHud(BuildContext context) {
    final theme = Theme.of(context);
    final comparison = _comparison;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: SectionCard(
        padding: const EdgeInsets.all(16),
        borderWidth: 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _statusTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_isRouting)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (comparison != null)
                  Text(
                    'Save ${comparison.savedCo2}g CO2 • Save ${rupees(comparison.savedFare)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _statusSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _routeColumn(
                    context,
                    title: '🌿 GREEN PATH',
                    accent: AppColors.primaryGreen,
                    metrics: comparison?.greenMetrics ?? '—',
                    carbon: comparison?.greenCarbon ?? 'Awaiting live route',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _routeColumn(
                    context,
                    title: '🚗 STANDARD PATH',
                    accent: AppColors.solidError,
                    metrics: comparison?.normalMetrics ?? '—',
                    carbon: comparison?.normalCarbon ?? 'Awaiting live route',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _routeColumn(
    BuildContext context, {
    required String title,
    required Color accent,
    required String metrics,
    required String carbon,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            metrics,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            carbon,
            style: theme.textTheme.labelSmall?.copyWith(color: accent),
          ),
        ],
      ),
    );
  }
}

/// The rendered HUD figures for one routing result. The summaries are also the
/// strings handed to Leaflet for the two route popups.
class _RouteComparison {
  const _RouteComparison({
    required this.greenSummary,
    required this.normalSummary,
    required this.greenMetrics,
    required this.greenCarbon,
    required this.normalMetrics,
    required this.normalCarbon,
    required this.savedCo2,
    required this.savedFare,
  });

  final String greenSummary;
  final String normalSummary;
  final String greenMetrics;
  final String greenCarbon;
  final String normalMetrics;
  final String normalCarbon;
  final int savedCo2;
  final int savedFare;
}
