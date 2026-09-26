/// Port of `mobility/MobilityModels.kt`.
enum TravelMode {
  walk('Walking'),
  cycle('Cycling'),
  metro('Electric Metro'),
  bus('Electric AC Bus'),
  evCab('Shared EV Rideshare'),
  taxi('Conventional Petrol Cab');

  const TravelMode(this.label);

  final String label;
}

class MobilityOption {
  const MobilityOption({
    required this.mode,
    required this.distanceKm,
    required this.durationMin,
    required this.fareRupees,
    required this.carbonGrams,
    required this.stepFreeAccessible,
    required this.accessibilityNote,
    this.practical = true,
    this.impracticalReason,
    this.balanceScore = 0.0,
  });

  final TravelMode mode;
  final double distanceKm;
  final int durationMin;
  final int fareRupees;
  final double carbonGrams;
  final bool stepFreeAccessible;
  final String accessibilityNote;

  /// False when the mode is not a realistic choice at this distance (e.g. a 20km
  /// walk). Impractical options sink in the ranking but are never hidden.
  final bool practical;
  final String? impracticalReason;
  final double balanceScore;

  /// CO2 avoided per passenger versus the conventional petrol taxi baseline.
  double carbonAvoidedVsBaseline(double baselineGrams) {
    final avoided = baselineGrams - carbonGrams;
    return avoided < 0 ? 0 : avoided;
  }

  MobilityOption copyWith({double? balanceScore}) => MobilityOption(
    mode: mode,
    distanceKm: distanceKm,
    durationMin: durationMin,
    fareRupees: fareRupees,
    carbonGrams: carbonGrams,
    stepFreeAccessible: stepFreeAccessible,
    accessibilityNote: accessibilityNote,
    practical: practical,
    impracticalReason: impracticalReason,
    balanceScore: balanceScore ?? this.balanceScore,
  );
}
