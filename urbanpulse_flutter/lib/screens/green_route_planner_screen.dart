import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/formatting.dart';
import '../core/routes.dart';
import '../domain/carbon_estimator.dart';
import '../domain/mobility_optimizer.dart';
import '../models/mobility.dart';
import '../services/tomtom_service.dart';
import '../services/trip_intent_parser.dart';
import '../state/activity_tracker.dart';
import '../state/app_scope.dart';
import '../state/trip_plan_manager.dart';
import '../widgets/common.dart';

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
  final _origin = TextEditingController(
    text: 'Current GPS Location (Mulund / Thane)',
  );
  final _destination = TextEditingController(
    text: 'Chhatrapati Shivaji Maharaj Terminus (CSMT)',
  );
  final _intentController = TextEditingController();

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
    _origin.addListener(_onEndpointChanged);
    _destination.addListener(_onEndpointChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recalculate());
  }

  @override
  void dispose() {
    _origin.dispose();
    _destination.dispose();
    _intentController.dispose();
    super.dispose();
  }

  void _onEndpointChanged() {
    // Text changed — any previous live route no longer applies.
    _realDistanceOverrideKm = null;
    _recalculate();
  }

  double get _currentDistanceKm =>
      _realDistanceOverrideKm ??
      CarbonEstimator.estimateDistanceKm(_origin.text, _destination.text);

  /// Recomputes real distance/cost/carbon for every mode (including walk/cycle
  /// feasibility) and re-ranks them.
  void _recalculate() {
    if (!mounted) return;
    final requireStepFree =
        AppScope.of(context).accessibility.isWheelchairModeEnabled ||
        _priority == TradeoffPriority.stepFree;

    final allOptions = CarbonEstimator.estimateAllModes(_currentDistanceKm);
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
    // Prefer the resolved place name; fall back to the raw fix, which
    // CarbonEstimator can also parse.
    final place = location.city;
    _origin.text = place != null
        ? '$place (${fixed(location.latitude!, 4)}° N, '
              '${fixed(location.longitude!, 4)}° E)'
        : 'My GPS Location (${fixed(location.latitude!, 4)}° N, '
              '${fixed(location.longitude!, 4)}° E)';
    showToast(context, 'Origin set to real-time GPS coordinates.');
  }

  Future<void> _recalculateLiveRoute() async {
    setState(() => _isRecalculating = true);
    final realKm = await TomTomService.fetchRealRouteDistanceKm(
      _origin.text,
      _destination.text,
    );
    if (!mounted) return;

    _realDistanceOverrideKm = realKm;
    _recalculate();
    setState(() => _isRecalculating = false);

    showToast(
      context,
      realKm != null
          ? 'TomTom-routed distance: ${fixed(realKm)} km.'
          : 'Live route unavailable — using ${fixed(_currentDistanceKm)} km estimate.',
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
    final allOptions = CarbonEstimator.estimateAllModes(_currentDistanceKm);
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
    final distanceKm = _currentDistanceKm;
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
                  decoration: const InputDecoration(
                    labelText: 'Origin / Start Point',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _destination,
                  decoration: const InputDecoration(labelText: 'Destination'),
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
            'Ranked Options (${_priority.label}) • ${fixed(distanceKm)} km trip',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
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
