import '../models/evidence.dart';

/// Shared machinery behind the two multi-objective rankers (`ParetoOptimizer`
/// for stays, `ExperienceOptimizer` for activities). The Kotlin source carried
/// two near-identical copies of the parsing, normalisation, weighting and
/// Pareto-dominance code; this is that one implementation, parameterised by the
/// wording each caller uses for its badges.

final _carbonPattern = RegExp(r'(\d+(\.\d+)?)\s*kg');
final _pricePattern = RegExp(r'[\d,]+');

/// Pulls the numeric kilogram figure out of copy like
/// `"4.2 kg CO2e / night (68% below city avg)"`.
double parseCarbon(String value) =>
    double.tryParse(_carbonPattern.firstMatch(value)?.group(1) ?? '') ??
    double.maxFinite;

/// Pulls the numeric amount out of copy like `"₹4,200 / night"`.
double parsePrice(String value) =>
    double.tryParse(
      _pricePattern.firstMatch(value)?.group(0)?.replaceAll(',', '') ?? '',
    ) ??
    double.maxFinite;

double _normalize(
  double value,
  double min,
  double max, {
  required bool higherIsBetter,
}) {
  if (max == min) return 1.0;
  final n = (value - min) / (max - min);
  return higherIsBetter ? n : 1 - n;
}

/// The badge captions a caller wants for each role.
class BadgeReasons {
  const BadgeReasons({
    required this.greenest,
    required this.mostAccessible,
    required this.bestValue,
    required this.bestBalance,
    required this.paretoOptimal,
  });

  final String greenest;
  final String mostAccessible;
  final String bestValue;
  final String bestBalance;
  final String paretoOptimal;
}

/// One ranked entry: the source index, its badges and its weighted score.
class RankedEntry {
  const RankedEntry(this.index, this.badges, this.balanceScore);

  final int index;
  final List<TripOptionBadge> badges;
  final double balanceScore;
}

/// Compares every option across carbon footprint, accessibility and price and
/// labels each by role rather than collapsing them into a single "best" answer.
/// An option is only left unlabelled if another option beats it on every axis at
/// once. Returns entries sorted by descending balance score.
List<RankedEntry> rankMultiObjective({
  required List<double> carbons,
  required List<double> prices,
  required List<double> accessibility,
  required BadgeReasons reasons,
}) {
  final count = carbons.length;
  if (count == 0) return const [];

  final carbonMin = carbons.reduce((a, b) => a < b ? a : b);
  final carbonMax = carbons.reduce((a, b) => a > b ? a : b);
  final priceMin = prices.reduce((a, b) => a < b ? a : b);
  final priceMax = prices.reduce((a, b) => a > b ? a : b);
  final accessMin = accessibility.reduce((a, b) => a < b ? a : b);
  final accessMax = accessibility.reduce((a, b) => a > b ? a : b);

  final balanceScores = List<double>.generate(count, (i) {
    final carbonScore = _normalize(
      carbons[i],
      carbonMin,
      carbonMax,
      higherIsBetter: false,
    );
    final priceScore = _normalize(
      prices[i],
      priceMin,
      priceMax,
      higherIsBetter: false,
    );
    final accessScore = _normalize(
      accessibility[i],
      accessMin,
      accessMax,
      higherIsBetter: true,
    );
    return (carbonScore * 0.4) + (accessScore * 0.4) + (priceScore * 0.2);
  });

  int minIndex(List<double> values) {
    var best = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] < values[best]) best = i;
    }
    return best;
  }

  int maxIndex(List<double> values) {
    var best = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] > values[best]) best = i;
    }
    return best;
  }

  final greenestIdx = minIndex(carbons);
  final mostAccessibleIdx = maxIndex(accessibility);
  final bestValueIdx = minIndex(prices);
  final bestBalanceIdx = maxIndex(balanceScores);

  final ranked = List<RankedEntry>.generate(count, (i) {
    final badges = <TripOptionBadge>[];
    if (i == greenestIdx) {
      badges.add(TripOptionBadge('Greenest', reasons.greenest));
    }
    if (i == mostAccessibleIdx) {
      badges.add(TripOptionBadge('Most Accessible', reasons.mostAccessible));
    }
    if (i == bestValueIdx) {
      badges.add(TripOptionBadge('Best Value', reasons.bestValue));
    }
    if (i == bestBalanceIdx) {
      badges.add(TripOptionBadge('Best Balance', reasons.bestBalance));
    }

    final isDominated = List.generate(count, (j) => j).any(
      (j) =>
          j != i &&
          carbons[j] <= carbons[i] &&
          prices[j] <= prices[i] &&
          accessibility[j] >= accessibility[i] &&
          (carbons[j] < carbons[i] ||
              prices[j] < prices[i] ||
              accessibility[j] > accessibility[i]),
    );
    if (!isDominated && badges.isEmpty) {
      badges.add(TripOptionBadge('Pareto-Optimal', reasons.paretoOptimal));
    }

    return RankedEntry(i, badges, balanceScores[i]);
  });

  ranked.sort((a, b) => b.balanceScore.compareTo(a.balanceScore));
  return ranked;
}
