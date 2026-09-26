import 'experience_listing.dart';
import 'hospitality_stay.dart';

/// Confidence tiers for a claim in the Evidence Graph.
///
/// - [verified] — corroborated by two or more independent signals
///   (e.g. a measured figure + operator disclosure)
/// - [reported] — stated by a single source (e.g. operator disclosure only)
/// - [inferred] — derived from a heuristic when direct evidence is thin or
///   inconsistent
/// - [unknown]  — no signal available
enum ConfidenceLevel {
  verified('Verified', '✅'),
  reported('Reported', '🟡'),
  inferred('Inferred', '🔵'),
  unknown('Unknown', '⚪');

  const ConfidenceLevel(this.label, this.icon);

  final String label;
  final String icon;
}

class EvidenceClaim {
  const EvidenceClaim({
    required this.claim,
    required this.confidence,
    required this.sources,
    this.contradiction,
  });

  final String claim;
  final ConfidenceLevel confidence;
  final List<String> sources;
  final String? contradiction;
}

class TripOptionBadge {
  const TripOptionBadge(this.label, this.reason);

  final String label;
  final String reason;
}

class RankedHospitalityStay {
  const RankedHospitalityStay({
    required this.stay,
    required this.evidence,
    required this.badges,
    required this.balanceScore,
  });

  final HospitalityStay stay;
  final List<EvidenceClaim> evidence;
  final List<TripOptionBadge> badges;
  final double balanceScore;
}

class RankedExperience {
  const RankedExperience({
    required this.experience,
    required this.badges,
    required this.balanceScore,
  });

  final ExperienceListing experience;
  final List<TripOptionBadge> badges;
  final double balanceScore;
}
