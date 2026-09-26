import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../domain/carbon_estimator.dart';
import '../domain/multi_objective_ranker.dart';
import '../services/central_registry_client.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

/// Port of `CarbonWalletActivity` / `activity_carbon_wallet.xml` — the Green
/// Travel Passport: lifetime savings, the combined stay + transport + activity
/// footprint, its percentile against every other combination, and the
/// redeemable partner perks.
///
/// Perks come from the Central Registry (`GET /api/perks`) and redeeming one
/// issues a real server-side voucher tied to this traveler, so a redemption
/// survives a restart. When the backend is unreachable the screen says so rather
/// than offering perks it cannot actually issue.
class CarbonWalletScreen extends StatefulWidget {
  const CarbonWalletScreen({super.key});

  @override
  State<CarbonWalletScreen> createState() => _CarbonWalletScreenState();
}

class _CarbonWalletScreenState extends State<CarbonWalletScreen> {
  /// A mature urban tree absorbs roughly this much CO2 per year.
  static const _kgCo2PerTreeYear = 21.0;

  String? _percentileText;
  bool _isComparing = false;

  List<RegistryPerk>? _perks;
  bool _isLoadingPerks = true;
  String? _redeemingPerkId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _computePercentile();
      _loadPerks();
    });
  }

  Future<void> _loadPerks() async {
    final travelerName = await AppScope.of(context).auth
        .getOrCreateTravelerName();
    final perks = await CentralRegistryClient.fetchPerks(
      travelerName: travelerName,
    );
    if (!mounted) return;
    setState(() {
      _perks = perks;
      _isLoadingPerks = false;
    });
  }

  /// Scores the traveler's actual chosen stay + transport + activities together
  /// against every other stay×mode combination reachable at the same distance,
  /// instead of showing three disconnected numbers.
  Future<void> _computePercentile() async {
    final services = AppScope.of(context);
    final stay = services.tripPlan.selectedStay;
    final mobility = services.tripPlan.selectedMobility;
    final experiences = services.tripPlan.selectedExperiences;
    if (stay == null || mobility == null) return;

    setState(() {
      _isComparing = true;
      _percentileText = 'Comparing against every other stay+route combination…';
    });

    final allStays = await services.hospitality.getAllStays();
    final allModes = CarbonEstimator.estimateAllModes(
      mobility.distanceKm.coerceAtLeast(1.5),
    );
    final experienceCarbon = experiences?.totalCarbonKg ?? 0.0;

    final combinedCarbonKg =
        stay.carbonKgPerNight +
        mobility.carbonGrams / 1000.0 +
        (experiences?.totalCarbonKg ?? 0.0);

    final allCombined = <double>[
      for (final s in allStays)
        for (final m in allModes)
          parseCarbon(s.carbonFootprintPerNight) +
              m.carbonGrams / 1000.0 +
              experienceCarbon,
    ];
    final beatenCount = allCombined.where((c) => c >= combinedCarbonKg).length;
    final percentile = allCombined.isEmpty
        ? 0
        : ((beatenCount / allCombined.length) * 100).round();

    if (!mounted) return;
    final activityNote = experiences != null
        ? ' (with your chosen activities held fixed)'
        : '';
    setState(() {
      _isComparing = false;
      _percentileText =
          'Greener than $percentile% of the ${allCombined.length} possible '
          'stay+route combinations for this trip$activityNote';
    });
  }

  Future<void> _redeem(RegistryPerk perk) async {
    final services = AppScope.of(context);
    setState(() => _redeemingPerkId = perk.id);

    // Spend locally first so the balance check is authoritative on-device; the
    // credits are refunded if the backend cannot issue the voucher.
    final granted = await services.gamification.spendPulse(perk.pulseCost);
    if (!mounted) return;
    if (!granted) {
      setState(() => _redeemingPerkId = null);
      showToast(
        context,
        'Not enough PULSE credits yet — keep taking green trips!',
      );
      return;
    }

    final travelerName = await services.auth.getOrCreateTravelerName();
    final redeemed = await CentralRegistryClient.redeemPerk(
      perk.id,
      travelerName: travelerName,
    );

    if (redeemed == null) {
      await services.gamification.addPulse(perk.pulseCost);
      if (!mounted) return;
      setState(() => _redeemingPerkId = null);
      showToast(
        context,
        'Could not reach the rewards service — your credits were not spent.',
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _redeemingPerkId = null;
      _perks = [
        for (final p in _perks ?? const <RegistryPerk>[])
          if (p.id == redeemed.id) redeemed else p,
      ];
    });
    showToast(
      context,
      '${perk.title} unlocked — voucher ${redeemed.redeemedVoucherCode}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const ScreenHeader(
        title: 'Green Travel Passport',
        subtitle: 'Lifetime Carbon Savings & Eco-Perks',
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([services.gamification, services.tripPlan]),
        builder: (context, _) {
          final co2Kg = services.gamification.co2SavedGrams / 1000.0;
          final trees = (co2Kg / _kgCo2PerTreeYear).floor();

          return RefreshIndicator(
            onRefresh: _loadPerks,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatTile(
                        label: 'Total Lifetime CO₂ Saved',
                        value: '${fixed(co2Kg)} kg',
                        caption: trees > 0
                            ? 'Equivalent to a year of absorption by $trees mature '
                                  'urban tree(s)'
                            : 'Take a green journey to start saving',
                        valueColor: theme.colorScheme.primary,
                      ),
                      const Divider(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: StatTile(
                              label: 'PULSE Carbon Credits',
                              value:
                                  '${grouped(services.gamification.pulse)} pts',
                            ),
                          ),
                          Expanded(
                            child: StatTile(
                              label: 'Traveler Status',
                              value: 'Level ${services.gamification.level}',
                              caption:
                                  '${services.gamification.streak}-day streak',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _tripSummaryCard(context),
                const SizedBox(height: 16),
                Text(
                  'Redeemable Hospitality Partner Perks',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ..._perkSection(context),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _perkSection(BuildContext context) {
    if (_isLoadingPerks) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final perks = _perks;
    if (perks == null) {
      return const [
        EmptyState(
          message:
              'Partner perks live on the Central Registry, which is unreachable '
              'right now. Start the backend (server/) or check your connection, then '
              'pull to refresh.',
          icon: Icons.cloud_off_outlined,
        ),
      ];
    }
    if (perks.isEmpty) {
      return const [
        EmptyState(
          message: 'No partner perks are currently on offer.',
          icon: Icons.redeem_outlined,
        ),
      ];
    }

    return [
      for (final perk in perks) ...[
        _perkCard(context, perk),
        const SizedBox(height: 12),
      ],
    ];
  }

  Widget _tripSummaryCard(BuildContext context) {
    final services = AppScope.of(context);
    final theme = Theme.of(context);
    final stay = services.tripPlan.selectedStay;
    final mobility = services.tripPlan.selectedMobility;
    final experiences = services.tripPlan.selectedExperiences;

    if (stay == null && mobility == null && experiences == null) {
      return const SizedBox.shrink();
    }

    final combinedCarbonKg =
        (stay?.carbonKgPerNight ?? 0) +
        (mobility?.carbonGrams ?? 0) / 1000.0 +
        (experiences?.totalCarbonKg ?? 0);
    final combinedCost =
        (stay?.priceRupees ?? 0) +
        (mobility?.fareRupees ?? 0) +
        (experiences?.totalPriceRupees ?? 0);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Combined Trip',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.hotel_outlined, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stay != null
                      ? 'Stay: ${stay.name} — ${fixed(stay.carbonKgPerNight)} kg CO2e/night • '
                            '${rupees(stay.priceRupees)}/night'
                      : 'Stay: not yet chosen — pick one in Sustainable Stays',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.directions_bus_outlined, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mobility != null
                      ? 'Transport: ${mobility.modeLabel} — '
                            '${fixed(mobility.carbonGrams, 0)}g CO2e • ${rupees(mobility.fareRupees)}'
                      : 'Transport: not yet chosen — pick a route in Green Journey Planner',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.local_activity_outlined, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  experiences != null
                      ? 'Activities: ${experiences.names.join(", ")} — '
                            '${fixed(experiences.totalCarbonKg)} kg CO2e • '
                            '${rupees(experiences.totalPriceRupees)}'
                      : 'Activities: not yet chosen — build one in Eco & Inclusive Itinerary',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Text(
            'Combined footprint: ${fixed(combinedCarbonKg)} kg CO2e • '
            '${rupees(combinedCost)} total',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_percentileText != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (_isComparing) ...[
                  const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    _percentileText!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _perkCard(BuildContext context, RegistryPerk perk) {
    final theme = Theme.of(context);
    final isRedeeming = _redeemingPerkId == perk.id;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            perk.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (perk.partner.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              perk.partner,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            perk.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: perk.isRedeemed || isRedeeming
                  ? null
                  : () => _redeem(perk),
              child: isRedeeming
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      perk.isRedeemed
                          ? 'Voucher Code: ${perk.redeemedVoucherCode}'
                          : 'Redeem for ${perk.pulseCost} pts',
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
