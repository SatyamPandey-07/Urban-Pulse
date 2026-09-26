import '../models/evidence.dart';
import '../models/experience_listing.dart';
import 'multi_objective_ranker.dart';

/// Same multi-objective ranking approach as `ParetoOptimizer`, applied to
/// activities/experiences instead of stays — carbon, accessibility and price,
/// with a Pareto-dominance check so nothing is silently hidden.
///
/// Port of `evidence/ExperienceOptimizer.kt`.
abstract final class ExperienceOptimizer {
  static const _reasons = BadgeReasons(
    greenest: 'Lowest carbon footprint of the compared experiences',
    mostAccessible: 'Highest accessibility rating',
    bestValue: 'Lowest price per person',
    bestBalance: 'Best weighted score across carbon, accessibility and price',
    paretoOptimal:
        'Not beaten on carbon, accessibility and price simultaneously '
        'by any other experience',
  );

  static List<RankedExperience> rank(List<ExperienceListing> experiences) {
    if (experiences.isEmpty) return const [];

    final ranked = rankMultiObjective(
      carbons: experiences
          .map((e) => parseCarbon(e.carbonFootprintPerVisit))
          .toList(),
      prices: experiences.map((e) => parsePrice(e.pricePerPerson)).toList(),
      accessibility: experiences
          .map((e) => e.accessibilityRating.toDouble())
          .toList(),
      reasons: _reasons,
    );

    return ranked
        .map(
          (entry) => RankedExperience(
            experience: experiences[entry.index],
            badges: entry.badges,
            balanceScore: entry.balanceScore,
          ),
        )
        .toList();
  }
}
