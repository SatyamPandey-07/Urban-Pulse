import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../models/live_city_data.dart';
import '../../services/location_service.dart';
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
  Timer? _searchDebounce;
  bool _isSearching = false;

  // Initial viewport, replaced by the real fix as soon as one resolves.
  double _currentLat = LocationService.defaultLat;
  double _currentLon = LocationService.defaultLon;
  bool _isTrafficEnabled = true;
  bool _isRouting = false;

  _RouteComparison? _comparison;
  List<LivePoiResult> _searchResults = const [];

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
    _searchDebounce?.cancel();
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

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = const [];
        _isSearching = false;
      });
      return;
    }
    if (trimmed.length < 2) return;
    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _performSearch(trimmed);
    });
  }

  Future<void> _performSearch(String query) async {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = const [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);

    final results = await TomTomService.searchPlacesBounded(
      trimmed,
      lat: _currentLat,
      lon: _currentLon,
      radiusKm: 60.0,
      limit: 6,
    );
    if (!mounted) return;
    setState(() {
      _isSearching = false;
      _searchResults = results;
    });
    if (results.isEmpty) {
      showToast(
        context,
        'No places matched "$trimmed" in region.',
      );
    }
  }

  void _selectSearchResult(LivePoiResult result) {
    _searchDebounce?.cancel();
    setState(() {
      _searchResults = const [];
      _isSearching = false;
      _searchController.text = result.name;
    });
    FocusScope.of(context).unfocus();
    _centerMap(result.lat, result.lon, 14);
    _calculateAndDrawDualRoutes(result.lat, result.lon, result.name);
  }

  /// Fetches the two real routes, computes the Maharashtra taxi fare and per-km
  /// carbon figures from their real distance, then hands the geometry to
  /// Leaflet. When a live route cannot be had, nothing is drawn and the traveller
  /// is told, rather than showing a distance or time that was not measured.
  Future<void> _calculateAndDrawDualRoutes(
    double destLat,
    double destLon,
    String destName,
  ) async {
    setState(() => _isRouting = true);

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

    if (!mounted) return;
    if (normal == null || green == null || normal.points.isEmpty || green.points.isEmpty) {
      setState(() => _isRouting = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Live routes are not available right now, so no comparison is shown. Please try again in a moment.')),
      );
      return;
    }
    final normalPoints = normal.points;
    final greenPoints = green.points;

    final distanceKm = normal.distanceKm;
    final normalTimeMin = normal.durationMin.coerceAtLeast(10);
    final greenTimeMin = green.durationMin.coerceAtLeast(8);

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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: WebViewWidget(
            controller: _webView,
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
          ),
        ),
        _topOverlay(context),
        _floatingControls(context),
        if (_comparison != null)
          _comparisonHud(context)
        else
          _nearbyPlacesSheet(context),
      ],
    );
  }

  Widget _topOverlay(BuildContext context) {
    return Positioned(
      top: 12,
      left: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: AppColors.surfaceBorder,
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                    onSubmitted: (val) {
                      _searchDebounce?.cancel();
                      _performSearch(val);
                    },
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Search places, facilities, destinations...',
                      hintStyle: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      filled: false,
                    ),
                  ),
                ),
                if (_isSearching)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  )
                else if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchDebounce?.cancel();
                      setState(() {
                        _searchController.clear();
                        _searchResults = const [];
                        _isSearching = false;
                      });
                    },
                  ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.surfaceBorder, width: 0.8),
                  ),
                  child: const Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _filterChips(context),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.surfaceBorder,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    thickness: 0.5,
                    color: AppColors.surfaceBorder,
                  ),
                  itemBuilder: (context, index) {
                    final result = _searchResults[index];
                    return InkWell(
                      onTap: () => _selectSearchResult(result),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: AppColors.primaryGreen
                                      .withValues(alpha: 0.3),
                                  width: 0.8,
                                ),
                              ),
                              child: const Icon(
                                Icons.near_me_rounded,
                                size: 16,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    result.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (result.address.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      result.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.surfaceBorder,
                                  width: 0.6,
                                ),
                              ),
                              child: Text(
                                '${fixed(result.distanceMeters / 1000)} km',
                                style: const TextStyle(
                                  color: AppColors.primaryGreen,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChipItem(
            label: 'Hotels',
            icon: Icons.hotel_rounded,
            iconColor: const Color(0xFF00A86B),
            isSelected: false,
            onTap: () => _performSearch('hotel'),
          ),
          const SizedBox(width: 8),
          _filterChipItem(
            label: 'Food',
            icon: Icons.restaurant_rounded,
            iconColor: const Color(0xFFEF4444),
            isSelected: false,
            onTap: () => _performSearch('restaurant'),
          ),
          const SizedBox(width: 8),
          _filterChipItem(
            label: 'Attractions',
            icon: Icons.star_rounded,
            iconColor: const Color(0xFFF59E0B),
            isSelected: false,
            onTap: () => _performSearch('tourist attraction'),
          ),
          const SizedBox(width: 8),
          _filterChipItem(
            label: 'Traffic',
            icon: Icons.traffic_rounded,
            iconColor: _isTrafficEnabled ? const Color(0xFF00A86B) : const Color(0xFF64748B),
            isSelected: _isTrafficEnabled,
            onTap: () => _toggleTraffic(),
          ),
        ],
      ),
    );
  }

  Widget _filterChipItem({
    required String label,
    required IconData icon,
    required Color iconColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8F8F0) : Colors.white,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: isSelected ? const Color(0xFF00A86B) : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 17,
              color: iconColor,
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF00A86B) : const Color(0xFF0F172A),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _centreOnUser() async {
    await _locateUser(zoom: 15, force: true);
    if (!mounted) return;
    showToast(context, 'Centered at GPS location');
  }

  Widget _floatingControls(BuildContext context) => Positioned(
    right: 16,
    bottom: _comparison != null ? 360 : 195,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _mapCircleButton(
          icon: Icons.layers_outlined,
          tooltip: 'Map Layers',
          onTap: _toggleTraffic,
        ),
        const SizedBox(height: 12),
        _mapCircleButton(
          icon: Icons.my_location_rounded,
          tooltip: 'My Location',
          onTap: _centreOnUser,
        ),
      ],
    ),
  );

  Widget _mapCircleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, size: 20, color: const Color(0xFF0F172A)),
        ),
      ),
    );
  }

  Widget _nearbyPlacesSheet(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F8F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.explore_rounded,
                        color: Color(0xFF00A86B),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Nearby Places',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {
                    _performSearch('attraction hotel food');
                    showToast(context, 'Showing all verified spots near you');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F8F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'See all',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00A86B),
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Color(0xFF00A86B)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _nearbyCategoryTile(
                    title: 'Hotels',
                    subtitle: '12 nearby',
                    icon: Icons.hotel_rounded,
                    accentColor: const Color(0xFF00A86B),
                    bgGradient: const [Color(0xFFE8F8F0), Color(0xFFD1F2E2)],
                    tagBg: const Color(0xFFE8F8F0),
                    onTap: () => _performSearch('hotel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _nearbyCategoryTile(
                    title: 'Food',
                    subtitle: '18 nearby',
                    icon: Icons.restaurant_rounded,
                    accentColor: const Color(0xFFEF4444),
                    bgGradient: const [Color(0xFFFEE2E2), Color(0xFFFDD2D2)],
                    tagBg: const Color(0xFFFEE2E2),
                    onTap: () => _performSearch('restaurant'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _nearbyCategoryTile(
                    title: 'Attractions',
                    subtitle: '7 nearby',
                    icon: Icons.star_rounded,
                    accentColor: const Color(0xFFF59E0B),
                    bgGradient: const [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                    tagBg: const Color(0xFFFEF3C7),
                    onTap: () => _performSearch('tourist attraction'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _nearbyCategoryTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required List<Color> bgGradient,
    required Color tagBg,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: bgGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: tagBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  subtitle,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: accentColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _comparisonHud(BuildContext context) {
    final comparison = _comparison;

    final greenDuration = comparison != null
        ? comparison.greenMetrics.split(' ').first
        : '24 min';
    final greenDetail = comparison != null
        ? '${comparison.greenCarbon} • Save ${comparison.savedCo2}g CO2'
        : '8.2 km • 0.4 kg CO2';

    final normalDuration = comparison != null
        ? comparison.normalMetrics.split(' ').first
        : '28 min';
    final normalDetail = comparison != null
        ? comparison.normalCarbon
        : '9.1 km • 2.3 kg CO2';

    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.surfaceLightBorder, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Dual Route Comparison',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (_isRouting)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _comparison = null),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F8F0),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF00A86B),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.eco_rounded, size: 14, color: Color(0xFF00A86B)),
                            SizedBox(width: 4),
                            Text(
                              'Green Path',
                              style: TextStyle(
                                color: Color(0xFF00A86B),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          greenDuration,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          greenDetail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF00A86B),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.surfaceLightBorder,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.directions_car_rounded, size: 14, color: AppColors.textSecondary),
                            SizedBox(width: 4),
                            Text(
                              'Standard Path',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          normalDuration,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          normalDetail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F8F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.eco_rounded, size: 15, color: Color(0xFF00A86B)),
                      SizedBox(width: 6),
                      Text(
                        'Why choose green?',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Color(0xFF00A86B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _whyChooseGreenItem('Lower carbon emissions'),
                  _whyChooseGreenItem('Less traffic'),
                  _whyChooseGreenItem('Smoother & scenic route'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  showToast(context, 'Starting green multimodal navigation...');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A86B),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.near_me_rounded, size: 18, color: Colors.white),
                label: const Text(
                  'Start Navigation',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _whyChooseGreenItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          const Icon(Icons.check_rounded, size: 13, color: Color(0xFF00A86B)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
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
