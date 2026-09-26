import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/multi_objective_ranker.dart';
import '../models/evidence.dart';
import '../services/trip_intent_parser.dart';
import '../state/app_scope.dart';
import '../state/hospitality_view_model.dart';
import '../state/trip_plan_manager.dart';
import '../widgets/common.dart';

/// Port of `HospitalityActivity` / `activity_hospitality.xml` +
/// `item_hospitality_stay.xml`: Pareto-ranked eco stays with evidence-graph
/// audits, chip filters, search, and the natural-language intent box.
class HospitalityScreen extends StatefulWidget {
  const HospitalityScreen({super.key});

  @override
  State<HospitalityScreen> createState() => _HospitalityScreenState();
}

class _HospitalityScreenState extends State<HospitalityScreen> {
  HospitalityViewModel? _viewModel;
  final _searchController = TextEditingController();
  final _intentController = TextEditingController();
  String? _intentSummary;
  bool _isParsingIntent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel ??= HospitalityViewModel(AppScope.of(context).hospitality);
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    _searchController.dispose();
    _intentController.dispose();
    super.dispose();
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

    final filter = switch (intent) {
      _ when intent.requireWheelchairAccess => StayChipFilter.wheelchair,
      _ when intent.requireSolarEnergy => StayChipFilter.solar,
      _ when intent.requireZeroWaste => StayChipFilter.zeroWaste,
      _ => StayChipFilter.all,
    };
    _viewModel?.updateChipFilter(filter);

    if (intent.searchKeywords.isNotEmpty) {
      _searchController.text = intent.searchKeywords;
      _viewModel?.updateQuery(intent.searchKeywords);
    }

    final applied = <String>[
      if (intent.requireWheelchairAccess) 'wheelchair access required',
      if (intent.requireSolarEnergy) 'solar-powered preferred',
      if (intent.requireZeroWaste) 'zero-waste preferred',
      if (intent.maxPriceRupees != null)
        'budget under ₹${intent.maxPriceRupees}',
    ];

    if (!mounted) return;
    setState(() {
      _isParsingIntent = false;
      _intentSummary =
          'Parsed via ${intent.engineLabel}'
          '${applied.isNotEmpty ? " — ${applied.join(", ")}" : ""}';
    });
  }

  Future<void> _showStayAudit(RankedHospitalityStay ranked) async {
    final stay = ranked.stay;
    final services = AppScope.of(context);

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(stay.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ranked.badges.isNotEmpty) ...[
                Row(
                  children: [
                    Icon(Icons.workspace_premium_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        ranked.badges.map((b) => b.label).join(' • '),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Text('Classification: ${stay.category}'),
              Text('Location: ${stay.location}'),
              Text('Tariff: ${stay.pricePerNight}'),
              const SizedBox(height: 16),
              Text(
                'Evidence Graph — Why this?',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final claim in ranked.evidence) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(claim.confidence.icon, size: 16, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '[${claim.confidence.label}] ${claim.claim}',
                      ),
                    ),
                  ],
                ),
                Text(
                  'Sources: ${claim.sources.join(", ")}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (claim.contradiction != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          claim.contradiction!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('close'),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('add'),
            child: const Text('Add to My Trip'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('call'),
            child: const Text('Call Venue'),
          ),
        ],
      ),
    );

    if (!mounted || action == null || action == 'close') return;

    if (action == 'call') {
      final uri = Uri(scheme: 'tel', path: stay.contactPhone);
      if (!await launchUrl(uri) && mounted) {
        showToast(context, 'No dialer app available on this device.');
      }
      return;
    }

    await services.tripPlan.setSelectedStay(
      SelectedStay(
        id: stay.id,
        name: stay.name,
        carbonKgPerNight: parseCarbon(stay.carbonFootprintPerNight),
        priceRupees: parsePrice(stay.pricePerNight).toInt(),
      ),
    );
    if (!mounted) return;
    showToast(context, '${stay.name} added to your trip plan.');
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = _viewModel;
    return Scaffold(
      appBar: const ScreenHeader(
        title: 'Green & Inclusive Stays',
        subtitle: 'Verified Eco-Practices & Accessibility Audits',
      ),
      body: viewModel == null
          ? const SizedBox.shrink()
          : AnimatedBuilder(
              animation: viewModel,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  IntentPromptCard(
                    title: "Describe what you're looking for",
                    hint: 'e.g. cheap wheelchair-friendly eco stay',
                    buttonLabel: 'Apply Filters',
                    controller: _intentController,
                    onApply: _applyIntent,
                    summary: _intentSummary,
                    isParsing: _isParsingIntent,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: viewModel.updateQuery,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search eco-resorts, solar hotels, dining...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChoiceChips<StayChipFilter>(
                    values: StayChipFilter.values,
                    selected: viewModel.chipFilter,
                    labelOf: (f) => f.label,
                    onSelected: viewModel.updateChipFilter,
                  ),
                  const SizedBox(height: 16),
                  if (viewModel.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (viewModel.rankedStays.isEmpty)
                    const EmptyState(
                      message: 'No stays match these filters yet.',
                      icon: Icons.hotel_outlined,
                    )
                  else
                    for (final ranked in viewModel.rankedStays) ...[
                      _StayCard(
                        ranked: ranked,
                        onViewAudit: () => _showStayAudit(ranked),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
    );
  }
}

class _StayCard extends StatelessWidget {
  const _StayCard({required this.ranked, required this.onViewAudit});

  final RankedHospitalityStay ranked;
  final VoidCallback onViewAudit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stay = ranked.stay;
    return SectionCard(
      onTap: onViewAudit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  stay.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Eco Level ${stay.ecoScore}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${stay.category} • ${stay.location}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (ranked.badges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.workspace_premium_outlined, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    ranked.badges.map((b) => b.label).join('  •  '),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '${stay.energySource} • ${stay.wastePolicy}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            stay.carbonFootprintPerNight,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Accessibility: ${stay.accessibilityTags.join(" • ")}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stay.pricePerNight,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${stay.accessibilityRating}% Accessibility Match',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: onViewAudit,
                child: const Text('View Audit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
