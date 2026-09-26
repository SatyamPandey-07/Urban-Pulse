import '../models/mobility.dart';

enum TradeoffPriority {
  eco('Lowest Carbon Impact'),
  stepFree('100% Step-Free Accessibility'),
  fastest('Fastest Travel Time'),
  budget('Lowest Cost'),
  balanced('Best Overall Balance');

  const TradeoffPriority(this.label);

  final String label;
}

/// Multi-objective comparison across carbon, accessibility, time and cost — the
/// same Pareto-badge approach used for hospitality, applied to mobility.
///
/// Port of `mobility/MobilityOptimizer.kt`.
abstract final class MobilityOptimizer {
  static double _normalize(
    double value,
    double min,
    double max, {
    required bool higherIsBetter,
  }) {
    if (max == min) return 1.0;
    final n = (value - min) / (max - min);
    return higherIsBetter ? n : 1 - n;
  }

  /// Scores and sorts options for a given priority. Impractical options (e.g. a
  /// 20km walk) sink to the bottom and never win a badge, but are never hidden.
  static List<MobilityOption> rank(
    List<MobilityOption> options,
    TradeoffPriority priority, {
    required bool requireStepFree,
  }) {
    if (options.isEmpty) return const [];

    final carbons = options.map((o) => o.carbonGrams).toList();
    final durations = options.map((o) => o.durationMin.toDouble()).toList();
    final fares = options.map((o) => o.fareRupees.toDouble()).toList();

    double lo(List<double> v) => v.reduce((a, b) => a < b ? a : b);
    double hi(List<double> v) => v.reduce((a, b) => a > b ? a : b);

    final scored = <MobilityOption>[];
    for (var i = 0; i < options.length; i++) {
      final option = options[i];
      final carbonScore = _normalize(
        carbons[i],
        lo(carbons),
        hi(carbons),
        higherIsBetter: false,
      );
      final fastScore = _normalize(
        durations[i],
        lo(durations),
        hi(durations),
        higherIsBetter: false,
      );
      final budgetScore = _normalize(
        fares[i],
        lo(fares),
        hi(fares),
        higherIsBetter: false,
      );
      final accessScore = option.stepFreeAccessible ? 1.0 : 0.0;

      var score = switch (priority) {
        TradeoffPriority.eco =>
          carbonScore * 0.7 + budgetScore * 0.15 + fastScore * 0.15,
        TradeoffPriority.stepFree =>
          accessScore * 0.7 + carbonScore * 0.2 + fastScore * 0.1,
        TradeoffPriority.fastest =>
          fastScore * 0.7 + carbonScore * 0.15 + budgetScore * 0.15,
        TradeoffPriority.budget =>
          budgetScore * 0.7 + carbonScore * 0.15 + fastScore * 0.15,
        TradeoffPriority.balanced =>
          carbonScore * 0.3 +
              fastScore * 0.25 +
              budgetScore * 0.25 +
              accessScore * 0.2,
      };
      // Sink impractical options without hiding them.
      if (!option.practical) score -= 10.0;
      scored.add(option.copyWith(balanceScore: score));
    }

    var filtered = scored;
    if (requireStepFree) {
      final stepFreeOnly = scored.where((o) => o.stepFreeAccessible).toList();
      if (stepFreeOnly.isNotEmpty) filtered = stepFreeOnly;
    }

    final sorted = [...filtered]
      ..sort((a, b) => b.balanceScore.compareTo(a.balanceScore));
    return sorted;
  }

  static String badgeFor(MobilityOption option, List<MobilityOption> ranked) {
    if (!option.practical) return 'NOT PRACTICAL';

    final practicalOnly = ranked.where((o) => o.practical).toList();
    if (practicalOnly.isEmpty) return '';

    final greenest = practicalOnly.reduce(
      (a, b) => a.carbonGrams <= b.carbonGrams ? a : b,
    );
    final fastest = practicalOnly.reduce(
      (a, b) => a.durationMin <= b.durationMin ? a : b,
    );
    final cheapest = practicalOnly.reduce(
      (a, b) => a.fareRupees <= b.fareRupees ? a : b,
    );
    final topRanked = practicalOnly.first;

    return switch (option.mode) {
      _ when option.mode == topRanked.mode => '#1 BEST MATCH',
      _ when option.mode == greenest.mode => 'GREENEST OPTION',
      _ when option.mode == fastest.mode => 'FASTEST ROUTE',
      _ when option.mode == cheapest.mode => 'LOWEST FARE',
      _ when option.stepFreeAccessible => 'STEP-FREE ACCESSIBLE',
      _ => '',
    };
  }
}
