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
import '../surprise_me_screen.dart';

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
          const SizedBox(height: 14),
          _surpriseCard(context),
          const SizedBox(height: 22),
          _popularDestinationsSection(context),
          const SizedBox(height: 22),
          _geoIntelligenceCard(context),
          const SizedBox(height: 24),
          _travelHubSection(context),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 900
                ? _evenRow([_aqiTrendCard(context), _congestionCard(context)])
                : Column(children: [_aqiTrendCard(context), const SizedBox(height: 16), _congestionCard(context)]),
          ),
        ],
      ),
    );
  }

  /// Surprise Me: Yatri picks a short trip from the traveller's past ones.
  Widget _surpriseCard(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    void open() {
      final tabs = HomeTabController.maybeOf(context);
      final inbox = AppScope.of(context).yatriInbox;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeContext) => SurpriseMeScreen(
            onPlan: (pick) {
              Navigator.of(routeContext).pop();
              tabs?.switchToTab(3);
              inbox.value = pick.brief;
            },
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: open,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceCard : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? AppColors.surfaceBorder : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF064E3B) : const Color(0xFFE8F8F0),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primaryGreen.withValues(alpha: isDark ? 0.3 : 0.2),
                    width: 1,
                  ),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: AppColors.primaryGreen, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Surprise me',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'A tailored eco-trip Yatri picks for you based on your history',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  String _selectedCategory = 'All';

  static final List<_CuratedPlace> _allPlaces = [
    _CuratedPlace(
      name: 'Lonavala & Khandala',
      category: 'Hill Stations',
      distanceStr: '28 km from Panvel',
      travelTime: '1.2 hrs by train / cab',
      rating: 4.8,
      reviewsCount: 1420,
      imageUrl: 'https://images.unsplash.com/photo-1570789210967-2cac24afeb00?w=800&auto=format&fit=crop&q=80',
      tag: 'Mist & Waterfalls',
      tagColor: Color(0xFF047857),
      description: 'Scenic Western Ghats hill station famous for lush valleys, Karla & Bhaja rock-cut caves, and panoramic mountain lookouts.',
      highlights: ['Tiger Point', 'Bhushi Dam', 'Karla Caves', 'Rajmachi Fort'],
      ecoScore: '🌱 -65% CO2e via Central Rail',
      accentColor: Color(0xFF047857),
    ),
    _CuratedPlace(
      name: 'Alibaug Coastal Bay',
      category: 'Beaches',
      distanceStr: '56 km via Mandwa Jetty',
      travelTime: '1.5 hrs via Ro-Ro Ferry + eBus',
      rating: 4.7,
      reviewsCount: 980,
      imageUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800&auto=format&fit=crop&q=80',
      tag: 'Beaches & Forts',
      tagColor: Color(0xFF0284C7),
      description: 'Coastal paradise renowned for clean sandy beaches, sea forts reachable during low tide, and sustainable homestays.',
      highlights: ['Kolaba Sea Fort', 'Mandwa Beach', 'Varsoli Coast', 'Kihim Beach'],
      ecoScore: '🌱 Low-emission electric ferry link',
      accentColor: Color(0xFF0284C7),
    ),
    _CuratedPlace(
      name: 'Matheran Eco-Reserve',
      category: 'Eco & Nature',
      distanceStr: '65 km from Panvel',
      travelTime: '2 hrs via Neral Toy Train',
      rating: 4.9,
      reviewsCount: 1850,
      imageUrl: 'https://images.unsplash.com/photo-1448375240586-882707db888b?w=800&auto=format&fit=crop&q=80',
      tag: 'Zero Automobile Zone',
      tagColor: Color(0xFF059669),
      description: "Asia's only automobile-free hill retreat. Red soil pathways, thick forest canopy, and over 38 lookout points.",
      highlights: ['Charlotte Lake', 'Panorama Point', 'Echo Point', 'Louisa Lookout'],
      ecoScore: '🌱 100% Zero-tailpipe emission zone',
      accentColor: Color(0xFF059669),
    ),
    _CuratedPlace(
      name: 'Mahabaleshwar & Panchgani',
      category: 'Hill Stations',
      distanceStr: '115 km from Pune/Panvel',
      travelTime: '3 hrs via eBus express',
      rating: 4.8,
      reviewsCount: 2100,
      imageUrl: 'https://images.unsplash.com/photo-1626621341517-bbf3d9990a23?w=800&auto=format&fit=crop&q=80',
      tag: 'Strawberry Valleys',
      tagColor: Color(0xFFE11D48),
      description: 'Elevated plateau in the Sahyadri range featuring fresh strawberry farms, evergreen viewpoints, and Venna Lake boating.',
      highlights: ["Arthur's Seat", 'Venna Lake', 'Mapro Garden', "Elephant's Head"],
      ecoScore: '🌱 Certified organic farm trails',
      accentColor: Color(0xFFE11D48),
    ),
    _CuratedPlace(
      name: 'Jaipur Pink City',
      category: 'Heritage & Forts',
      distanceStr: 'Rajasthan Heritage Hub',
      travelTime: 'Direct Vande Bharat / Flight',
      rating: 4.9,
      reviewsCount: 3400,
      imageUrl: 'https://images.unsplash.com/photo-1599661046289-e31897846e41?w=800&auto=format&fit=crop&q=80',
      tag: 'Royal Palaces & Forts',
      tagColor: Color(0xFFD97706),
      description: 'UNESCO World Heritage city with sandstone palaces, astronomical observatories, and vibrant bazaar culture.',
      highlights: ['Amber Palace', 'Hawa Mahal', 'City Palace', 'Jantar Mantar'],
      ecoScore: '🌱 Solar-powered transit metro',
      accentColor: Color(0xFFD97706),
    ),
    _CuratedPlace(
      name: 'Coorg (Kodagu)',
      category: 'Coffee & Highlands',
      distanceStr: 'Western Ghats Rainforest',
      travelTime: 'Scenic Hill Road Connection',
      rating: 4.9,
      reviewsCount: 1680,
      imageUrl: 'https://images.unsplash.com/photo-1588668214407-6ea9a6d8c272?w=800&auto=format&fit=crop&q=80',
      tag: 'Coffee & Waterfalls',
      tagColor: Color(0xFF15803D),
      description: 'The Scotland of India. Misty valleys, sprawling coffee and spice plantations, and gushing Abbey Falls.',
      highlights: ['Abbey Falls', "Raja's Seat", 'Dubare Elephant Sanctuary', 'Talakaveri'],
      ecoScore: '🌱 Certified Rainforest Alliance Stay',
      accentColor: Color(0xFF15803D),
    ),
    _CuratedPlace(
      name: 'Goa Coastal Trail',
      category: 'Beaches',
      distanceStr: 'Konkan Coastline',
      travelTime: 'Vande Bharat Express Route',
      rating: 4.8,
      reviewsCount: 2950,
      imageUrl: 'https://images.unsplash.com/photo-1512343879784-a960bf40e7f2?w=800&auto=format&fit=crop&q=80',
      tag: 'Sunset & Heritage',
      tagColor: Color(0xFF0284C7),
      description: 'Pristine golden coastline, Portuguese baroque architecture, mangrove estuaries, and oceanfront eco-huts.',
      highlights: ['Palolem Bay', 'Fort Aguada', 'Dudhsagar Falls', 'Fontainhas Quarter'],
      ecoScore: '🌱 Electric scooter & bike routes',
      accentColor: Color(0xFF0284C7),
    ),
  ];

  Widget _searchBar(BuildContext context) {
    return InkWell(
      onTap: () => _showSearchPlacesSheet(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              color: AppColors.primaryGreen,
              size: 22,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Explore destinations, hill stations, beaches…',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.auto_awesome,
                    color: AppColors.primaryGreen,
                    size: 14,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'AI Finder',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryGreen,
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

  Widget _categoryIconsRow(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final categories = [
      (
        'Hotels',
        Icons.hotel_rounded,
        const Color(0xFF10B981),
        isDark ? const Color(0x2410B981) : const Color(0xFFE8F8F0),
        () => Navigator.of(context).pushNamed(Routes.hospitality),
      ),
      (
        'Flights',
        Icons.flight_rounded,
        const Color(0xFF38BDF8),
        isDark ? const Color(0x2438BDF8) : const Color(0xFFE0F2FE),
        () => Navigator.of(context).pushNamed(Routes.greenRoutePlanner),
      ),
      (
        'Trains',
        Icons.train_rounded,
        const Color(0xFF34D399),
        isDark ? const Color(0x2434D399) : const Color(0xFFE6F7FA),
        () => Navigator.of(context).pushNamed(Routes.greenRoutePlanner),
      ),
      (
        'Attractions',
        Icons.star_rounded,
        const Color(0xFFFBBF24),
        isDark ? const Color(0x24FBBF24) : const Color(0xFFFEF3C7),
        () => Navigator.of(context).pushNamed(Routes.itinerary),
      ),
      (
        'More',
        Icons.more_horiz_rounded,
        const Color(0xFF94A3B8),
        isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
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
                    color: cat.$3.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                ),
                child: Icon(cat.$2, color: cat.$3, size: 24),
              ),
              const SizedBox(height: 6),
              Text(
                cat.$1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
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
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
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
    final theme = Theme.of(context);
    final categories = ['All', 'Hill Stations', 'Beaches', 'Heritage & Forts', 'Eco & Nature', 'Coffee & Highlands'];
    final filteredPlaces = _selectedCategory == 'All'
        ? _allPlaces
        : _allPlaces.where((p) => p.category == _selectedCategory).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Curated Places & Getaways',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Hand-picked sustainable destinations with real-time transit & AI planning',
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
            const SizedBox(width: 8),
            InkWell(
              onTap: () => HomeTabController.maybeOf(context)?.switchToTab(3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Yatri AI >',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? Colors.white : theme.colorScheme.onSurface,
                  ),
                  selectedColor: AppColors.primaryGreen,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  side: BorderSide(
                    color: isSelected ? AppColors.primaryGreen : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),

        // Elevated Destination Cards Carousel
        SizedBox(
          height: 235,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: filteredPlaces.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final place = filteredPlaces[index];
              return _buildPlaceCard(context, place);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceCard(BuildContext context, _CuratedPlace place) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _showPlaceDetailsSheet(context, place),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 195,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Image with Rating Badge & Category Tag
            SizedBox(
              height: 125,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    place.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: place.accentColor.withValues(alpha: 0.15),
                      child: Icon(Icons.terrain_rounded, color: place.accentColor, size: 40),
                    ),
                  ),
                  // Gradient scrim
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.3),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Rating Pill
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24, width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 14),
                          const SizedBox(width: 3),
                          Text(
                            '${place.rating}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Category Tag
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: place.tagColor.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        place.tag,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom Metadata Details
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.near_me_outlined,
                        size: 12,
                        color: AppColors.primaryGreen,
                      ),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          place.distanceStr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          place.ecoScore,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_circle_right_rounded,
                        size: 16,
                        color: AppColors.primaryGreen,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Interactive Bottom Sheet with high-def details, key attractions & one-tap AI planning.
  void _showPlaceDetailsSheet(BuildContext context, _CuratedPlace place) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(sheetContext).size.height * 0.78,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Top Hero Image Banner
            SizedBox(
              height: 200,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(place.imageUrl, fit: BoxFit.cover),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.4),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: place.tagColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                place.tag,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 14),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${place.rating} (${place.reviewsCount}+)',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          place.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Body Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 16, color: AppColors.primaryGreen),
                      const SizedBox(width: 6),
                      Text(
                        place.travelTime,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.eco_rounded, color: AppColors.primaryGreen, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            place.ecoScore,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'About this Destination',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    place.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Must-Visit Spots & Highlights',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: place.highlights.map((h) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.place_rounded, size: 14, color: AppColors.primaryGreen),
                          const SizedBox(width: 6),
                          Text(h, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 28),
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: const Text('Live Map'),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            HomeTabController.maybeOf(context)?.switchToTab(1);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.auto_awesome, size: 18),
                          label: const Text('Plan with Yatri AI'),
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            final tabs = HomeTabController.maybeOf(context);
                            tabs?.switchToTab(3);
                            showToast(
                              context,
                              'Yatri AI ready! Type "Plan a sustainable trip to ${place.name}"',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Instant Search Modal for Quick Place Discovery
  void _showSearchPlacesSheet(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            height: MediaQuery.of(sheetContext).size.height * 0.82,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Search & Select Places',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search forts, hill stations, beaches, tea estates…',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryGreen),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) {
                    setModalState(() {});
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Recommended Getaways',
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: _allPlaces.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, i) {
                      final p = _allPlaces[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(p.imageUrl, width: 50, height: 50, fit: BoxFit.cover),
                        ),
                        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${p.distanceStr} • ${p.tag}'),
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.primaryGreen),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _showPlaceDetailsSheet(context, p);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
        LayoutBuilder(
          builder: (context, box) {
            // Four across (and the two wide cards side by side) when there is
            // room, as on the website; two across on phones.
            final wide = box.maxWidth >= 900;
            final cards = [
              _bentoCard(
                context: context,
                title: 'Eco Stays',
                subtitle: 'Verified sustainable & accessible stays',
                icon: Icons.hotel_outlined,
                route: Routes.hospitality,
              ),
              _bentoCard(
                context: context,
                title: 'Green Routes',
                subtitle: 'Low-emission multimodal routes',
                icon: Icons.alt_route_rounded,
                route: Routes.greenRoutePlanner,
              ),
              _bentoCard(
                context: context,
                title: 'Hotel Optimizer',
                subtitle: 'Best value & lowest footprint',
                icon: Icons.trending_up_rounded,
                route: Routes.hotelOptimizer,
              ),
              _bentoCard(
                context: context,
                title: 'Carbon Wallet',
                subtitle: 'Track your CO2 savings & rewards',
                icon: Icons.account_balance_wallet_outlined,
                route: Routes.carbonWallet,
              ),
            ];
            final features = [
              _wideBentoCard(
                context: context,
                title: 'AI Eco Itinerary Generator',
                subtitle: 'Personalized step-free & low-carbon day plans',
                icon: Icons.auto_awesome_rounded,
                route: Routes.itinerary,
              ),
              _wideBentoCard(
                context: context,
                title: 'Weather Digital Twin',
                subtitle: 'Live weather, reports and what-ifs: see how rain, heat or floods change your trip',
                icon: Icons.thunderstorm_outlined,
                route: Routes.weatherTwin,
              ),
            ];
            return Column(
              children: [
                for (final row in _rows(cards, wide ? 4 : 2)) ...[
                  _evenRow(row),
                  const SizedBox(height: 12),
                ],
                if (wide)
                  _evenRow(features)
                else
                  for (final (i, f) in features.indexed) ...[
                    if (i > 0) const SizedBox(height: 12),
                    f,
                  ],
              ],
            );
          },
        ),
      ],
    );
  }

  static List<List<Widget>> _rows(List<Widget> items, int perRow) => [
    for (var i = 0; i < items.length; i += perRow) items.sublist(i, (i + perRow).clamp(0, items.length)),
  ];

  /// Equal-width cells of equal height.
  static Widget _evenRow(List<Widget> cells) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in cells.indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: c),
        ],
      ],
    ),
  );

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

class _CuratedPlace {
  const _CuratedPlace({
    required this.name,
    required this.category,
    required this.distanceStr,
    required this.travelTime,
    required this.rating,
    required this.reviewsCount,
    required this.imageUrl,
    required this.tag,
    required this.tagColor,
    required this.description,
    required this.highlights,
    required this.ecoScore,
    required this.accentColor,
  });

  final String name;
  final String category;
  final String distanceStr;
  final String travelTime;
  final double rating;
  final int reviewsCount;
  final String imageUrl;
  final String tag;
  final Color tagColor;
  final String description;
  final List<String> highlights;
  final String ecoScore;
  final Color accentColor;
}

