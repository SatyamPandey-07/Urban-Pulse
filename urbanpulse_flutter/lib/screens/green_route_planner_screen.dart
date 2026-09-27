import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_colors.dart';
import '../core/formatting.dart';
import '../core/routes.dart';
import '../domain/carbon_estimator.dart';
import '../domain/mobility_optimizer.dart';
import '../models/mobility.dart';
import '../models/map_route.dart' show NavMode;
import '../services/place_geocoder.dart';
import '../services/routing_service.dart';
import '../services/trip_intent_parser.dart';
import '../state/activity_tracker.dart';
import '../state/app_scope.dart';
import '../state/trip_plan_manager.dart';
import '../widgets/common.dart';
import '../widgets/tool_location_sheet.dart';

/// Port of `GreenRoutePlannerActivity` / `activity_green_route_planner.xml`:
/// origin/destination entry with a real GPS lock, a real TomTom-routed distance,
/// and every travel mode scored and badged against the selected trade-off.
class GreenRoutePlannerScreen extends StatefulWidget {
  const GreenRoutePlannerScreen({super.key});

  @override
  State<GreenRoutePlannerScreen> createState() =>
      _GreenRoutePlannerScreenState();
}

class _GreenRoutePlannerScreenState extends State<GreenRoutePlannerScreen> {
  final _origin = TextEditingController();
  final _destination = TextEditingController();
  final _intentController = TextEditingController();

  /// Where the two ends are, found with the geocoder (or chosen from the
  /// sheet / GPS). Nothing is measured until both are known.
  final _geocoder = PlaceGeocoder();
  LatLng? _originPt;
  LatLng? _destPt;
  Timer? _resolveTimer;
  bool _resolving = false;
  bool _settingText = false;
  String? _placeMessage;

  TravelMode _selectedMode = TravelMode.metro;
  TradeoffPriority _priority = TradeoffPriority.eco;
  List<MobilityOption> _ranked = const [];
  List<MobilityOption> _allOptions = const [];

  /// Real TomTom-routed distance for the current origin/dest, set by
  /// "Calculate Live Routes". Cleared whenever the origin/dest text changes so
  /// stale network results are never reused.
  double? _realDistanceOverrideKm;

  String? _intentSummary;
  bool _isParsingIntent = false;
  bool _isRecalculating = false;

  @override
  void initState() {
    super.initState();
    _origin.addListener(() => _onEndpointChanged(origin: true));
    _destination.addListener(() => _onEndpointChanged(origin: false));
    // Start from where the traveller is, if the app knows.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startFromHere());
  }

  Future<void> _startFromHere() async {
    final location = AppScope.of(context).location;
    if (!location.hasFix) return;
    final lat = location.latitude, lon = location.longitude;
    if (lat == null || lon == null) return;
    _setPlace(origin: true, text: location.city ?? 'My location', point: LatLng(lat, lon));
  }

  void _setPlace({required bool origin, required String text, required LatLng point}) {
    _settingText = true;
    (origin ? _origin : _destination).text = text;
    _settingText = false;
    if (origin) {
      _originPt = point;
    } else {
      _destPt = point;
    }
    _realDistanceOverrideKm = null;
    _placeMessage = null;
    _recalculate();
  }

  Future<void> _choose({required bool origin}) async {
    final p = await chooseToolPlace(context, title: origin ? 'Where are you starting?' : 'Where are you going?');
    if (p != null && mounted) _setPlace(origin: origin, text: p.label.contains(' · ') && p.label.startsWith('Current') ? p.city : p.label, point: p.point);
  }

  @override
  void dispose() {
    _resolveTimer?.cancel();
    _origin.dispose();
    _destination.dispose();
    _intentController.dispose();
    super.dispose();
  }

  void _onEndpointChanged({required bool origin}) {
    if (_settingText) return;
    // Text changed: the place it named and any live route no longer apply.
    if (origin) {
      _originPt = null;
    } else {
      _destPt = null;
    }
    _realDistanceOverrideKm = null;
    _recalculate();
    _resolveTimer?.cancel();
    _resolveTimer = Timer(const Duration(milliseconds: 800), _resolveMissing);
  }

  /// Finds the places named in the boxes that are not yet located.
  Future<void> _resolveMissing() async {
    final pending = <bool, String>{
      if (_originPt == null && _origin.text.trim().length >= 2) true: _origin.text.trim(),
      if (_destPt == null && _destination.text.trim().length >= 2) false: _destination.text.trim(),
    };
    if (pending.isEmpty) return;
    setState(() {
      _resolving = true;
      _placeMessage = null;
    });
    String? missing;
    for (final e in pending.entries) {
      final area = await _geocoder.lookupArea(e.value);
      if (!mounted) return;
      if (area == null) {
        missing = e.value;
        continue;
      }
      // Ignore an answer for text that has been changed since.
      if (e.key && _origin.text.trim() == e.value) _originPt = area.center;
      if (!e.key && _destination.text.trim() == e.value) _destPt = area.center;
    }
    setState(() {
      _resolving = false;
      _placeMessage = missing == null ? null : 'I could not find "$missing". Try the city name, or pick it from the list.';
    });
    _recalculate();
  }

  /// The trip's distance: a live measurement if there is one, otherwise an
  /// estimate from the two located places. Null until both are known.
  double? get _distanceKm {
    if (_realDistanceOverrideKm != null) return _realDistanceOverrideKm;
    final o = _originPt, d = _destPt;
    if (o == null || d == null) return null;
    return CarbonEstimator.estimateDistanceBetween(o.latitude, o.longitude, d.latitude, d.longitude);
  }

  /// Recomputes real distance/cost/carbon for every mode (including walk/cycle
  /// feasibility) and re-ranks them.
  void _recalculate() {
    if (!mounted) return;
    final km = _distanceKm;
    if (km == null) {
      setState(() {
        _allOptions = const [];
        _ranked = const [];
      });
      return;
    }
    final requireStepFree =
        AppScope.of(context).accessibility.isWheelchairModeEnabled ||
        _priority == TradeoffPriority.stepFree;

    final allOptions = CarbonEstimator.estimateAllModes(km);
    final ranked = MobilityOptimizer.rank(
      allOptions,
      _priority,
      requireStepFree: requireStepFree,
    );

    // If the current selection became unusable (impractical at this distance, or
    // filtered out by a step-free requirement), fall back to the top match.
    final selected = allOptions.firstWhere((o) => o.mode == _selectedMode);
    final selectedIsUsable =
        selected.practical && (!requireStepFree || selected.stepFreeAccessible);

    setState(() {
      _allOptions = allOptions;
      _ranked = ranked;
      if (!selectedIsUsable && ranked.isNotEmpty) {
        _selectedMode = ranked.first.mode;
      }
    });
  }

  Future<void> _useGps() async {
    final location = AppScope.of(context).location;
    await location.resolve(force: true);
    if (!mounted) return;
    if (!location.hasFix) {
      showToast(
        context,
        'GPS location unavailable — enable location services and try again.',
      );
      return;
    }
    _setPlace(origin: true, text: location.city ?? 'My location', point: LatLng(location.latitude!, location.longitude!));
    showToast(context, 'Starting from your current location.');
  }

  Future<void> _recalculateLiveRoute() async {
    setState(() => _isRecalculating = true);
    _resolveTimer?.cancel();
    await _resolveMissing();
    final o = _originPt, d = _destPt;
    if (!mounted) return;
    if (o == null || d == null) {
      setState(() => _isRecalculating = false);
      showToast(context, 'Enter where you are starting and where you are going first.');
      return;
    }
    final routes = await RoutingService().routes(o, d, NavMode.drive);
    if (!mounted) return;

    _realDistanceOverrideKm = routes.isEmpty ? null : routes.first.distanceKm;
    _recalculate();
    setState(() => _isRecalculating = false);

    showToast(
      context,
      routes.isNotEmpty
          ? 'Road distance measured by ${routes.first.source}: ${fixed(routes.first.distanceKm)} km.'
          : 'A live route is unavailable, so the distance is an estimate: ${fixed(_distanceKm ?? 0)} km.',
    );
  }

  Future<void> _applyIntent() async {
    final text = _intentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isParsingIntent = true);

    final intent = await TripIntentParser.parse(text);
    if (!mounted) return;

    final services = AppScope.of(context);
    if (intent.requireWheelchairAccess) {
      await services.accessibility.setWheelchairMode(true);
    }

    final priority = switch (intent) {
      _ when intent.prioritizeAccessibility || intent.requireWheelchairAccess =>
        TradeoffPriority.stepFree,
      _ when intent.prioritizeSpeed => TradeoffPriority.fastest,
      _ when intent.prioritizeBudget => TradeoffPriority.budget,
      // Carbon priority is the default when nothing else stands out.
      _ => TradeoffPriority.eco,
    };

    final applied = <String>[
      if (intent.requireWheelchairAccess) 'wheelchair access required',
      if (intent.requireSolarEnergy) 'solar-powered preferred',
      if (intent.requireZeroWaste) 'zero-waste preferred',
      if (intent.maxPriceRupees != null)
        'budget under ₹${intent.maxPriceRupees}',
    ];

    if (!mounted) return;
    setState(() {
      _priority = priority;
      _isParsingIntent = false;
      _intentSummary =
          'Parsed via ${intent.engineLabel}'
          '${applied.isNotEmpty ? " — ${applied.join(", ")}" : ""}';
    });
    _recalculate();
  }

  void _selectMode(TravelMode mode) {
    final option =
        _ranked.where((o) => o.mode == mode).firstOrNull ??
        _allOptions.where((o) => o.mode == mode).firstOrNull;
    if (option == null) return;
    if (!option.practical) {
      showToast(
        context,
        option.impracticalReason ?? 'Not practical for this distance',
      );
      return;
    }
    setState(() => _selectedMode = mode);
  }

  Future<void> _confirmJourney() async {
    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    final km = _distanceKm;
    if (km == null) return;
    final allOptions = CarbonEstimator.estimateAllModes(km);
    final option = allOptions.where((o) => o.mode == _selectedMode).firstOrNull;
    if (option == null) return;

    final baseline = allOptions
        .firstWhere((o) => o.mode == TravelMode.taxi)
        .carbonGrams;
    final avoidedGrams = option.carbonAvoidedVsBaseline(baseline);
    final credits = (avoidedGrams / 10.0).round().coerceAtLeast(0);

    await services.gamification.addPulse(credits);
    await services.gamification.addCo2Saved(avoidedGrams);
    await services.gamification.addXp(credits * 2);
    await services.activity.increment(TrackedAction.greenJourneysConfirmed);
    await services.tripPlan.setSelectedMobility(
      SelectedMobility(
        modeLabel: option.mode.label,
        carbonGrams: option.carbonGrams,
        fareRupees: option.fareRupees,
        distanceKm: option.distanceKm,
      ),
    );

    if (!mounted) return;
    showToast(
      context,
      'Journey started via ${option.mode.label}! ${fixed(avoidedGrams, 0)}g CO2 avoided, '
      '+$credits Carbon Credits earned.',
    );
    navigator.pushNamed(Routes.carbonWallet);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distanceKm = _distanceKm;
    final selectedOption = _ranked
        .where((o) => o.mode == _selectedMode)
        .firstOrNull;
    final baselineCarbon = _allOptions.isEmpty
        ? 0.0
        : _allOptions.firstWhere((o) => o.mode == TravelMode.taxi).carbonGrams;
    final credits = selectedOption == null
        ? 0
        : (selectedOption.carbonAvoidedVsBaseline(baselineCarbon) / 10.0)
              .round()
              .coerceAtLeast(0);

    return Scaffold(
      appBar: const ScreenHeader(
        title: 'Green Journey Planner',
        subtitle: 'Tradeoff Optimizer • Live Multimodal Carbon Matrix',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          IntentPromptCard(
            title: 'Describe your trip priorities',
            hint: 'e.g. cheapest wheelchair-friendly option',
            buttonLabel: 'Apply to Route Options',
            controller: _intentController,
            onApply: _applyIntent,
            summary: _intentSummary,
            isParsing: _isParsingIntent,
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: _origin,
                  decoration: InputDecoration(
                    labelText: 'Origin / Start Point',
                    hintText: 'City, area or landmark',
                    suffixIcon: IconButton(tooltip: 'Choose a place', icon: const Icon(Icons.place_outlined), onPressed: () => _choose(origin: true)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _destination,
                  decoration: InputDecoration(
                    labelText: 'Destination',
                    hintText: 'City, area or landmark',
                    suffixIcon: IconButton(tooltip: 'Choose a place', icon: const Icon(Icons.place_outlined), onPressed: () => _choose(origin: false)),
                  ),
                ),
                if (_resolving || _placeMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_resolving ? 'Finding the places…' : _placeMessage!, style: theme.textTheme.bodySmall),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isRecalculating
                            ? null
                            : _recalculateLiveRoute,
                        icon: _isRecalculating
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.route, size: 18),
                        label: const Text('Calculate Live Routes'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _useGps,
                      icon: const Icon(Icons.my_location, size: 18),
                      label: const Text('GPS Lock'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Tradeoff Optimization Priority',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SingleChoiceChips<TradeoffPriority>(
            values: const [
              TradeoffPriority.eco,
              TradeoffPriority.stepFree,
              TradeoffPriority.fastest,
              TradeoffPriority.budget,
            ],
            selected: _priority,
            labelOf: (p) => p.label,
            onSelected: (p) {
              setState(() => _priority = p);
              _recalculate();
            },
          ),
          const SizedBox(height: 20),
          Text(
            distanceKm == null ? 'Ranked Options (${_priority.label})' : 'Ranked Options (${_priority.label}) • ${fixed(distanceKm)} km trip',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (distanceKm == null)
            const EmptyState(
              message: 'Enter where you are starting and where you are going to compare the ways to travel.',
              icon: Icons.alt_route_rounded,
            ),
          // Every mode is always listed, in ranked order, so nothing is hidden.
          for (final option in _ranked) ...[
            _ModeCard(
              option: option,
              badge: MobilityOptimizer.badgeFor(option, _ranked),
              isSelected: option.mode == _selectedMode,
              baselineCarbon: baselineCarbon,
              onTap: () => _selectMode(option.mode),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: selectedOption == null ? null : _confirmJourney,
              child: Text(
                'Confirm ${selectedOption?.mode.label ?? "Route"} '
                '(+$credits Carbon Credits)',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.option,
    required this.badge,
    required this.isSelected,
    required this.baselineCarbon,
    required this.onTap,
  });

  final MobilityOption option;
  final String badge;
  final bool isSelected;
  final double baselineCarbon;
  final VoidCallback onTap;

  static Color _badgeColor(String badge) => switch (badge) {
    _ when badge.contains('BEST MATCH') => AppColors.primaryGreen,
    _ when badge.contains('GREENEST') => AppColors.primaryGreen,
    _ when badge.contains('STEP-FREE') => AppColors.primaryBlue,
    _ when badge.contains('FASTEST') => AppColors.solidWarning,
    _ when badge.contains('LOWEST FARE') => AppColors.primaryGreen,
    _ when badge.contains('NOT PRACTICAL') => AppColors.textSecondary,
    _ => AppColors.textTertiary,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final String metrics;
    final String savings;
    if (!option.practical) {
      metrics =
          '${fixed(option.distanceKm)} km • '
          '${option.impracticalReason ?? "Not practical for this distance"}';
      savings = 'Choose a motorized option for this distance';
    } else {
      metrics = option.carbonGrams > 0
          ? '${option.durationMin} mins • ${rupees(option.fareRupees)} • '
                '${fixed(option.carbonGrams, 0)}g CO2e per passenger'
          : '${option.durationMin} mins • ${rupees(option.fareRupees)} • '
                '0g CO2e (zero-emission)';
      if (option.mode == TravelMode.taxi) {
        savings = 'Baseline high-emission reference';
      } else {
        final baseline = baselineCarbon > 0
            ? baselineCarbon
            : CarbonEstimator.estimateOption(
                TravelMode.taxi,
                option.distanceKm,
              ).carbonGrams;
        final avoided = option.carbonAvoidedVsBaseline(baseline);
        final cleanerPct = baseline > 0
            ? ((avoided / baseline) * 100).round()
            : 0;
        savings =
            'CO2 Avoided vs Petrol Cab: -${fixed(avoided, 0)}g '
            '($cleanerPct% cleaner)';
      }
    }

    return SectionCard(
      onTap: onTap,
      borderWidth: isSelected ? 4 : 0,
      borderColor: AppColors.primaryGreen,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  option.mode.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (badge.isNotEmpty)
                Text(
                  badge,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _badgeColor(badge),
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(metrics, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            'Accessibility: ${option.accessibilityNote}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            savings,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
