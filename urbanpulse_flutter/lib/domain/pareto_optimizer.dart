import '../models/evidence.dart';
import '../models/hospitality_stay.dart';
import 'evidence_graph_service.dart';
import 'multi_objective_ranker.dart';

/// Multi-objective comparison of hospitality stays across carbon footprint,
/// accessibility and price. Port of `evidence/ParetoOptimizer.kt`.
abstract final class ParetoOptimizer {
  static const _reasons = BadgeReasons(
    greenest: 'Lowest measured carbon footprint of the compared options',
    mostAccessible: 'Highest accessibility match rating',
    bestValue: 'Lowest price per night',
    bestBalance: 'Best weighted score across carbon, accessibility and price',
    paretoOptimal:
        'Not beaten on carbon, accessibility and price simultaneously '
        'by any other option',
  );

  static List<RankedHospitalityStay> rank(List<HospitalityStay> stays) {
    if (stays.isEmpty) return const [];

    final ranked = rankMultiObjective(
      carbons: stays
          .map((s) => parseCarbon(s.carbonFootprintPerNight))
          .toList(),
      prices: stays.map((s) => parsePrice(s.pricePerNight)).toList(),
      accessibility: stays
          .map((s) => s.accessibilityRating.toDouble())
          .toList(),
      reasons: _reasons,
    );

    return ranked
        .map(
          (entry) => RankedHospitalityStay(
            stay: stays[entry.index],
            evidence: EvidenceGraphService.buildEvidence(stays[entry.index]),
            badges: entry.badges,
            balanceScore: entry.balanceScore,
          ),
        )
        .toList();
  }
}
