import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../domain/carbon_estimator.dart';
import '../domain/multi_objective_ranker.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

/// Port of `CarbonWalletActivity` / `activity_carbon_wallet.xml` — the Green
/// Travel Passport: lifetime savings, the combined stay + transport + activity
/// footprint, its percentile against every other combination, and the
/// redeemable partner perks.
class CarbonWalletScreen extends StatefulWidget {
  const CarbonWalletScreen({super.key});

  @override
  State<CarbonWalletScreen> createState() => _CarbonWalletScreenState();
}

class _CarbonWalletScreenState extends State<CarbonWalletScreen> {
  static const _orchidCost = 400;
  static const _evCost = 250;

  String? _orchidVoucher;
  String? _evVoucher;
  String? _percentileText;
  bool _isComparing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _computePercentile());
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

  Future<void> _redeem({
    required int cost,
    required String voucherCode,
    required String successMessage,
    required ValueChanged<String> onRedeemed,
  }) async {
    final services = AppScope.of(context);
    final granted = await services.gamification.spendPulse(cost);
    if (!mounted) return;
    if (!granted) {
      showToast(
        context,
        'Not enough PULSE credits yet — keep taking green trips!',
      );
      return;
    }
    setState(() => onRedeemed(voucherCode));
    showToast(context, successMessage);
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
          final trees = (co2Kg / 21)
              .floor(); // ~21 kg CO2 absorbed per urban tree/year

          return ListView(
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
                          ? 'Equivalent to planting $trees mature urban tree(s)'
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
              _perkCard(
                context,
                title: '15% Off at Orchid Eco-Resort',
                description: 'Valid on certified zero-waste dining and solar room suites.',
                cost: _orchidCost,
                voucher: _orchidVoucher,
                onRedeem: () => _redeem(
                  cost: _orchidCost,
                  voucherCode: 'ORCHID-ECO-15',
                  successMessage: 'Orchid Eco-Resort voucher unlocked! Saved to your profile.',
                  onRedeemed: (code) => _orchidVoucher = code,
                ),
              ),
              const SizedBox(height: 12),
              _perkCard(
                context,
                title: 'Complimentary 60kW EV Fast Charge Session',
                description:
                    'Applicable at Tata Power charging hubs across Mumbai.',
                cost: _evCost,
                voucher: _evVoucher,
                onRedeem: () => _redeem(
                  cost: _evCost,
                  voucherCode: 'TATA-EV-FREE',
                  successMessage: 'Free EV Charging voucher unlocked!',
                  onRedeemed: (code) => _evVoucher = code,
                ),
              ),
            ],
          );
        },
      ),
    );
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
          Text(
            stay != null
                ? '🏨 Stay: ${stay.name} — ${fixed(stay.carbonKgPerNight)} kg CO2e/night • '
                      '${rupees(stay.priceRupees)}/night'
                : '🏨 Stay: not yet chosen — pick one in Sustainable Stays',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            mobility != null
                ? '🚌 Transport: ${mobility.modeLabel} — '
                      '${fixed(mobility.carbonGrams, 0)}g CO2e • ${rupees(mobility.fareRupees)}'
                : '🚌 Transport: not yet chosen — pick a route in Green Journey Planner',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            experiences != null
                ? '🎟️ Activities: ${experiences.names.join(", ")} — '
                      '${fixed(experiences.totalCarbonKg)} kg CO2e • '
                      '${rupees(experiences.totalPriceRupees)}'
                : '🎟️ Activities: not yet chosen — build one in Eco & Inclusive Itinerary',
            style: theme.textTheme.bodySmall,
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

  Widget _perkCard(
    BuildContext context, {
    required String title,
    required String description,
    required int cost,
    required String? voucher,
    required VoidCallback onRedeem,
  }) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: voucher == null ? onRedeem : null,
              child: Text(
                voucher == null
                    ? 'Redeem for $cost pts'
                    : 'Voucher Code: $voucher',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
