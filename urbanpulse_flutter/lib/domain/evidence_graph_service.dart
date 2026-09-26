import '../models/evidence.dart';
import '../models/experience_listing.dart';
import '../models/hospitality_stay.dart';

/// Builds confidence-tagged claims for a listing instead of asserting
/// accessibility/sustainability facts outright. Cross-checks numeric ratings
/// against how much concrete detail backs them up and flags contradictions when
/// a claim is under-documented.
///
/// Port of `evidence/EvidenceGraphService.kt`.
abstract final class EvidenceGraphService {
  static List<EvidenceClaim> buildEvidence(HospitalityStay stay) {
    final claims = <EvidenceClaim>[];

    // No independent second source exists for sustainability claims in this
    // dataset (no live operator API or third-party certification feed) — every
    // stay's carbon figure is formatted with "kg" by the same repository code,
    // so a "does the string contain a number + kg" check would always be true
    // and isn't real corroboration. A single-source claim can therefore never
    // legitimately reach VERIFIED here; only REPORTED (specific operator
    // disclosure) or INFERRED (generic/vague) apply.
    final isSpecificEnergySource =
        stay.energySource.length > 15 &&
        stay.energySource.toLowerCase() != 'grid';
    claims.add(
      EvidenceClaim(
        claim: 'Sustainability: ${stay.energySource}',
        confidence: isSpecificEnergySource
            ? ConfidenceLevel.reported
            : ConfidenceLevel.inferred,
        sources: isSpecificEnergySource
            ? ['Operator energy disclosure: ${stay.carbonFootprintPerNight}']
            : ['Category heuristic: ${stay.category}'],
        contradiction: isSpecificEnergySource
            ? null
            : 'Energy source is generic with no specific operator disclosure to back it — '
                  'treat as a category estimate, not a confirmed practice.',
      ),
    );

    final tagCount = stay.accessibilityTags.length;
    final expectedTagsForRating = switch (stay.accessibilityRating) {
      >= 95 => 4,
      >= 90 => 3,
      _ => 2,
    };
    final underDocumented = tagCount < expectedTagsForRating;
    claims.add(
      EvidenceClaim(
        claim:
            'Accessibility: ${stay.accessibilityRating}% match, '
            '$tagCount documented feature(s)',
        confidence: underDocumented
            ? ConfidenceLevel.inferred
            : ConfidenceLevel.verified,
        sources: stay.accessibilityTags,
        contradiction: underDocumented
            ? 'Rating claims ${stay.accessibilityRating}% but only $tagCount feature(s) are '
                  'documented — treat as inferred until confirmed on-site.'
            : null,
      ),
    );

    final lowerWaste = stay.wastePolicy.toLowerCase();
    final hasZeroWastePolicy =
        lowerWaste.contains('zero') || lowerWaste.contains('biodegradable');
    claims.add(
      EvidenceClaim(
        claim: 'Waste handling: ${stay.wastePolicy}',
        confidence: hasZeroWastePolicy
            ? ConfidenceLevel.verified
            : ConfidenceLevel.reported,
        sources: const ['Operator waste policy statement'],
      ),
    );

    return claims;
  }

  /// Same confidence-tagged-claim approach as [buildEvidence], applied to
  /// general experience listings (not just hospitality stays) — the app-wide
  /// "never say Accessible: Yes outright" guarantee, not something limited to
  /// hotel/resort stays.
  static List<EvidenceClaim> buildEvidenceForExperience(ExperienceListing exp) {
    final claims = <EvidenceClaim>[];

    final tagCount = exp.accessibilityTags.length;
    final expectedTagsForRating = exp.accessibilityRating >= 90 ? 2 : 1;
    final underDocumented =
        tagCount < expectedTagsForRating ||
        exp.accessibilityTags.contains('Standard Access');

    // Real traveler reports (a genuinely independent second source, submitted
    // via the "Confirm" / "Report an issue" prompt) take priority over the
    // provider-declared tag heuristic below — this is what makes "official
    // sources + user reports" actually true.
    if (exp.accessibilityDisputeCount > 0) {
      final vsConfirming = exp.accessibilityConfirmCount > 0
          ? ' (vs. ${exp.accessibilityConfirmCount} confirming)'
          : '';
      claims.add(
        EvidenceClaim(
          claim:
              'Accessibility: ${exp.accessibilityRating}% claimed, but disputed by travelers',
          confidence: ConfidenceLevel.inferred,
          sources: [
            '${exp.accessibilityDisputeCount} traveler report(s) disputing this claim',
            ...exp.accessibilityTags,
          ],
          contradiction:
              '${exp.accessibilityDisputeCount} traveler report(s) dispute this accessibility '
              'claim$vsConfirming — treat the ${exp.accessibilityRating}% rating as unconfirmed '
              'until resolved.',
        ),
      );
    } else if (exp.accessibilityConfirmCount > 0) {
      claims.add(
        EvidenceClaim(
          claim:
              'Accessibility: ${exp.accessibilityRating}% match, '
              '$tagCount documented feature(s)',
          confidence: ConfidenceLevel.verified,
          sources: [
            '${exp.accessibilityConfirmCount} independent traveler report(s) confirming on-site',
            ...exp.accessibilityTags,
          ],
        ),
      );
    } else if (underDocumented) {
      claims.add(
        EvidenceClaim(
          claim:
              'Accessibility: ${exp.accessibilityRating}% match, '
              '$tagCount documented feature(s)',
          confidence: ConfidenceLevel.inferred,
          sources: exp.accessibilityTags,
          contradiction:
              'Rating claims ${exp.accessibilityRating}% but accessibility features '
              'are generic or under-documented, and no traveler has confirmed it yet — treat as '
              'inferred until confirmed on-site.',
        ),
      );
    } else {
      claims.add(
        EvidenceClaim(
          claim:
              'Accessibility: ${exp.accessibilityRating}% match, '
              '$tagCount documented feature(s)',
          confidence: ConfidenceLevel.reported,
          sources: exp.accessibilityTags,
          contradiction: 'Provider-declared only — no independent traveler confirmation yet.',
        ),
      );
    }

    final sustainabilityText = exp.sustainabilityPractice;
    final lower = sustainabilityText.toLowerCase();
    final isSpecificPractice =
        sustainabilityText.length > 20 &&
        (lower.contains('solar') ||
            lower.contains('organic') ||
            lower.contains('electric') ||
            lower.contains('zero') ||
            lower.contains('recycl') ||
            lower.contains('local'));
    claims.add(
      EvidenceClaim(
        claim: 'Sustainability: $sustainabilityText',
        confidence: isSpecificPractice
            ? ConfidenceLevel.reported
            : ConfidenceLevel.inferred,
        sources: isSpecificPractice
            ? const ['Provider-listed sustainability practice']
            : ['Category heuristic: ${exp.category}'],
        contradiction: isSpecificPractice
            ? null
            : 'No specific, checkable sustainability practice was provided — this is a '
                  'category-based estimate, not a verified claim.',
      ),
    );

    return claims;
  }
}
