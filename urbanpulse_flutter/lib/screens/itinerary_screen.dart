import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../core/routes.dart';
import '../domain/experience_optimizer.dart';
import '../domain/multi_objective_ranker.dart';
import '../models/evidence.dart';
import '../services/trip_intent_parser.dart';
import '../state/activity_tracker.dart';
import '../state/app_scope.dart';
import '../state/trip_plan_manager.dart';
import '../widgets/common.dart';

enum _Duration {
  halfDay('Half-Day Eco Tour (4h)', 1),
  fullDay('Full-Day Inclusive (8h)', 2),
  weekend('Weekend 2-Day Eco Retreat', 3);

  const _Duration(this.label, this.slotCount);

  final String label;
  final int slotCount;
}

enum _Persona {
  wheelchair('Wheelchair / Step-Free'),
  farmToFork('Organic & Farm-to-Fork'),
  heritage('Sensory Heritage & Art');

  const _Persona(this.label);

  final String label;
}

/// Port of `ItineraryActivity` / `activity_itinerary.xml` — builds a ranked,
/// chronological day plan out of the real experience catalog.
class ItineraryScreen extends StatefulWidget {
  const ItineraryScreen({super.key});

  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen> {
  /// Matches `ExperienceRepository`'s category-average reference point.
  static const _categoryAverageCarbonKg = 1.4;

  final _intentController = TextEditingController();

  List<RankedExperience> _allRanked = const [];
  List<RankedExperience> _lastGenerated = const [];
  String _keywordFilter = '';
  _Duration _duration = _Duration.fullDay;
  _Persona _persona = _Persona.heritage;
  String? _intentSummary;
  bool _isParsingIntent = false;
  bool _isLoadingCatalog = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCatalog());
  }

  @override
  void dispose() {
    _intentController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    final experiences = await AppScope.of(context).experiences
        .getAllExperiences();
    if (!mounted) return;
    setState(() {
      _allRanked = ExperienceOptimizer.rank(experiences);
      _isLoadingCatalog = false;
    });
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

    final persona = switch (intent) {
      _ when intent.requireWheelchairAccess || intent.prioritizeAccessibility =>
        _Persona.wheelchair,
      _ when intent.requireZeroWaste => _Persona.farmToFork,
      _ => _Persona.heritage,
    };

    final applied = <String>[
      if (intent.requireWheelchairAccess) 'wheelchair access required',
      if (intent.requireZeroWaste) 'zero-waste / organic preferred',
      if (intent.maxPriceRupees != null)
        'budget under ₹${intent.maxPriceRupees}',
    ];

    if (!mounted) return;
    setState(() {
      _persona = persona;
      _keywordFilter = intent.searchKeywords;
      _isParsingIntent = false;
      _intentSummary =
          'Parsed via ${intent.engineLabel}'
          '${applied.isNotEmpty ? " — ${applied.join(", ")}" : ""}';
    });
  }

  void _generate() {
    if (_allRanked.isEmpty) {
      showToast(context, 'Still loading the experience catalog…');
      return;
    }

    final wheelchairMode = AppScope.of(context)
        .accessibility
        .isWheelchairModeEnabled;
    var pool = _allRanked;

    if (_keywordFilter.isNotEmpty) {
      final kw = _keywordFilter.toLowerCase();
      final matches = pool
          .where(
            (r) =>
                r.experience.name.toLowerCase().contains(kw) ||
                r.experience.category.toLowerCase().contains(kw),
          )
          .toList();
      if (matches.isNotEmpty) pool = matches;
    }

    pool = switch (_persona) {
      _Persona.farmToFork => _orAll(
        pool,
        pool.where((r) {
          final e = r.experience;
          return e.category.toLowerCase().contains('culinary') ||
              e.sustainabilityPractice.toLowerCase().contains('farm') ||
              e.sustainabilityPractice.toLowerCase().contains('organic');
        }).toList(),
      ),
      _Persona.heritage => _orAll(
        pool,
        pool.where((r) {
          final c = r.experience.category.toLowerCase();
          return c.contains('heritage') || c.contains('cultural');
        }).toList(),
      ),
      // The wheelchair persona keeps the full pool, filtered by accessibility below.
      _Persona.wheelchair => pool,
    };

    if (_persona == _Persona.wheelchair || wheelchairMode) {
      pool = _orAll(
        pool,
        pool.where((r) => r.experience.accessibilityRating >= 90).toList(),
      );
    }

    setState(() => _lastGenerated = pool.take(_duration.slotCount).toList());
    showToast(
      context,
      'Optimized green & inclusive itinerary generated from ${_allRanked.length} '
      'real listings!',
    );
  }

  /// Keeps the unfiltered pool when a filter would empty it, matching the
  /// Kotlin `.ifEmpty { candidatePool }` chain.
  static List<RankedExperience> _orAll(
    List<RankedExperience> fallback,
    List<RankedExperience> filtered,
  ) => filtered.isEmpty ? fallback : filtered;

  Future<void> _save() async {
    if (_lastGenerated.isEmpty) {
      showToast(context, 'Generate an itinerary first.');
      return;
    }

    final services = AppScope.of(context);
    final navigator = Navigator.of(context);
    final totalCarbonKg = _lastGenerated.fold<double>(
      0,
      (sum, r) => sum + parseCarbon(r.experience.carbonFootprintPerVisit),
    );
    final totalPrice = _lastGenerated.fold<int>(
      0,
      (sum, r) => sum + parsePrice(r.experience.pricePerPerson).toInt(),
    );
    final avoidedKg =
        (_categoryAverageCarbonKg * _lastGenerated.length - totalCarbonKg)
            .coerceAtLeast(0);
    final credits = (avoidedKg * 20).round().coerceAtLeast(0);

    await services.tripPlan.setSelectedExperiences(
      SelectedExperiences(
        names: _lastGenerated.map((r) => r.experience.name).toList(),
        totalCarbonKg: totalCarbonKg,
        totalPriceRupees: totalPrice,
      ),
    );
    await services.gamification.addPulse(credits);
    await services.gamification.addCo2Saved(avoidedKg * 1000.0);
    await services.gamification.addXp(credits * 2);
    await services.activity.increment(TrackedAction.itinerariesSaved);

    if (!mounted) return;
    showToast(
      context,
      'Itinerary saved to your Green Travel Passport! +$credits Pts credited.',
    );
    navigator.pushNamed(Routes.carbonWallet);
  }

  ({String carbon, int credits}) get _impact {
    if (_lastGenerated.isEmpty) {
      return (carbon: 'No experiences match these filters yet.', credits: 0);
    }
    final totalCarbonKg = _lastGenerated.fold<double>(
      0,
      (sum, r) => sum + parseCarbon(r.experience.carbonFootprintPerVisit),
    );
    final baselineCarbonKg = _categoryAverageCarbonKg * _lastGenerated.length;
    final avoidedKg = (baselineCarbonKg - totalCarbonKg).coerceAtLeast(0);
    final cleanerPct = baselineCarbonKg > 0
        ? ((avoidedKg / baselineCarbonKg) * 100).round()
        : 0;
    return (
      carbon:
          '${fixed(avoidedKg)} kg CO2e Avoided ($cleanerPct% cleaner than the '
          'category average for ${_lastGenerated.length} stop(s))',
      credits: (avoidedKg * 20).round().coerceAtLeast(0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final impact = _impact;

    return Scaffold(
      appBar: const ScreenHeader(
        title: 'Eco & Inclusive Itinerary',
        subtitle: 'AI-Generated Low-Carbon, Step-Free Day Plans',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          IntentPromptCard(
            title: 'Describe your ideal day',
            hint: 'e.g. wheelchair-friendly nature experiences',
            buttonLabel: 'Apply to Itinerary',
            controller: _intentController,
            onApply: _applyIntent,
            summary: _intentSummary,
            isParsing: _isParsingIntent,
          ),
          const SizedBox(height: 16),
          Text(
            'Select Trip Duration',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SingleChoiceChips<_Duration>(
            values: _Duration.values,
            selected: _duration,
            labelOf: (d) => d.label,
            onSelected: (d) => setState(() => _duration = d),
          ),
          const SizedBox(height: 16),
          Text(
            'Traveler Persona & Needs',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          SingleChoiceChips<_Persona>(
            values: _Persona.values,
            selected: _persona,
            labelOf: (p) => p.label,
            onSelected: (p) => setState(() => _persona = p),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _isLoadingCatalog ? null : _generate,
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                _isLoadingCatalog
                    ? 'Loading experience catalog…'
                    : 'Generate Optimized Itinerary',
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Itinerary Impact',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(impact.carbon, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '+${impact.credits} PTS',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Curated Chronological Timeline',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (_lastGenerated.isEmpty)
            const EmptyState(
              message:
                  'Tap "Generate Optimized Itinerary" to build a real, ranked plan '
                  'from the experience catalog.',
              icon: Icons.timeline_outlined,
            )
          else
            for (final entry in _timelineEntries()) ...[
              _TimelineCard(time: entry.$1, ranked: entry.$2),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.tonal(
              onPressed: _lastGenerated.isEmpty ? null : _save,
              child: Text(
                'Save Itinerary to Green Passport (+${impact.credits} Pts)',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Spreads the selected stops across the day starting at 09:00, the same slot
  /// arithmetic the Kotlin timeline builder used.
  List<(String, RankedExperience)> _timelineEntries() {
    const startHour = 9;
    final divisor = (_lastGenerated.length * 2).clamp(1, 8);
    final hoursPerSlot = (24 ~/ divisor).clamp(2, 24);

    return [
      for (var i = 0; i < _lastGenerated.length; i++)
        (_formatSlot((startHour + i * hoursPerSlot) % 24), _lastGenerated[i]),
    ];
  }

  static String _formatSlot(int hour) {
    final amPm = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '${displayHour.toString().padLeft(2, '0')}:00 $amPm';
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.time, required this.ranked});

  final String time;
  final RankedExperience ranked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exp = ranked.experience;
    final badgeLine = ranked.badges.isNotEmpty
        ? ' • ${ranked.badges.map((b) => b.label).join(" • ")}'
        : '';

    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$time • ${exp.name}',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${exp.location} — ${exp.sustainabilityPractice}.$badgeLine\n'
            '${exp.carbonFootprintPerVisit} • ${fixed(exp.durationHours)}h • '
            '${exp.pricePerPerson}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
