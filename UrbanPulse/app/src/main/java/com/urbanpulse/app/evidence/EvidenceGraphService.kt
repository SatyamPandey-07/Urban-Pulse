package com.urbanpulse.app.evidence

import com.urbanpulse.app.ExperienceListing
import com.urbanpulse.app.HospitalityStay

/**
 * Builds confidence-tagged claims for a stay instead of asserting
 * accessibility/sustainability facts outright. Cross-checks numeric
 * ratings against how much concrete detail backs them up and flags
 * contradictions when a claim is under-documented.
 */
object EvidenceGraphService {

    fun buildEvidence(stay: HospitalityStay): List<EvidenceClaim> {
        val claims = mutableListOf<EvidenceClaim>()

        // No independent second source exists for sustainability claims in this dataset (no live
        // operator API or third-party certification feed) — every stay's carbon figure is formatted
        // with "kg" by the same repository code, so a "does the string contain a number + kg" check
        // would always be true and isn't real corroboration. A single-source claim can therefore
        // never legitimately reach VERIFIED here; only REPORTED (specific operator disclosure) or
        // INFERRED (generic/vague) apply.
        val isSpecificEnergySource = stay.energySource.length > 15 && !stay.energySource.equals("Grid", ignoreCase = true)
        claims += EvidenceClaim(
            claim = "Sustainability: ${stay.energySource}",
            confidence = if (isSpecificEnergySource) ConfidenceLevel.REPORTED else ConfidenceLevel.INFERRED,
            sources = if (isSpecificEnergySource) listOf("Operator energy disclosure: ${stay.carbonFootprintPerNight}") else listOf("Category heuristic: ${stay.category}"),
            contradiction = if (!isSpecificEnergySource)
                "Energy source is generic with no specific operator disclosure to back it — treat as a category estimate, not a confirmed practice."
            else null
        )

        val tagCount = stay.accessibilityTags.size
        val expectedTagsForRating = when {
            stay.accessibilityRating >= 95 -> 4
            stay.accessibilityRating >= 90 -> 3
            else -> 2
        }
        val underDocumented = tagCount < expectedTagsForRating
        claims += EvidenceClaim(
            claim = "Accessibility: ${stay.accessibilityRating}% match, $tagCount documented feature(s)",
            confidence = if (underDocumented) ConfidenceLevel.INFERRED else ConfidenceLevel.VERIFIED,
            sources = stay.accessibilityTags,
            contradiction = if (underDocumented)
                "Rating claims ${stay.accessibilityRating}% but only $tagCount feature(s) are documented — treat as inferred until confirmed on-site."
            else null
        )

        val hasZeroWastePolicy = stay.wastePolicy.contains("Zero", ignoreCase = true) ||
            stay.wastePolicy.contains("Biodegradable", ignoreCase = true)
        claims += EvidenceClaim(
            claim = "Waste handling: ${stay.wastePolicy}",
            confidence = if (hasZeroWastePolicy) ConfidenceLevel.VERIFIED else ConfidenceLevel.REPORTED,
            sources = listOf("Operator waste policy statement")
        )

        return claims
    }

    /**
     * Same confidence-tagged-claim approach as [buildEvidence], applied to general experience
     * listings (not just hospitality stays) — the app-wide "never say Accessible: Yes outright"
     * guarantee the pitch describes, not something limited to hotel/resort stays.
     */
    fun buildEvidenceForExperience(exp: ExperienceListing): List<EvidenceClaim> {
        val claims = mutableListOf<EvidenceClaim>()

        val tagCount = exp.accessibilityTags.size
        val expectedTagsForRating = when {
            exp.accessibilityRating >= 90 -> 2
            exp.accessibilityRating >= 80 -> 1
            else -> 1
        }
        val underDocumented = tagCount < expectedTagsForRating || exp.accessibilityTags.contains("Standard Access")

        // Real traveler reports (a genuinely independent second source, submitted via the
        // "Confirm" / "Report an issue" prompt) take priority over the provider-declared tag
        // heuristic below — this is what makes "official sources + user reports" actually true.
        claims += when {
            exp.accessibilityDisputeCount > 0 -> EvidenceClaim(
                claim = "Accessibility: ${exp.accessibilityRating}% claimed, but disputed by travelers",
                confidence = ConfidenceLevel.INFERRED,
                sources = listOf("${exp.accessibilityDisputeCount} traveler report(s) disputing this claim") + exp.accessibilityTags,
                contradiction = "${exp.accessibilityDisputeCount} traveler report(s) dispute this accessibility claim" +
                    (if (exp.accessibilityConfirmCount > 0) " (vs. ${exp.accessibilityConfirmCount} confirming)" else "") +
                    " — treat the ${exp.accessibilityRating}% rating as unconfirmed until resolved."
            )
            exp.accessibilityConfirmCount > 0 -> EvidenceClaim(
                claim = "Accessibility: ${exp.accessibilityRating}% match, $tagCount documented feature(s)",
                confidence = ConfidenceLevel.VERIFIED,
                sources = listOf("${exp.accessibilityConfirmCount} independent traveler report(s) confirming on-site") + exp.accessibilityTags
            )
            underDocumented -> EvidenceClaim(
                claim = "Accessibility: ${exp.accessibilityRating}% match, $tagCount documented feature(s)",
                confidence = ConfidenceLevel.INFERRED,
                sources = exp.accessibilityTags,
                contradiction = "Rating claims ${exp.accessibilityRating}% but accessibility features are generic or under-documented, and no traveler has confirmed it yet — treat as inferred until confirmed on-site."
            )
            else -> EvidenceClaim(
                claim = "Accessibility: ${exp.accessibilityRating}% match, $tagCount documented feature(s)",
                confidence = ConfidenceLevel.REPORTED,
                sources = exp.accessibilityTags,
                contradiction = "Provider-declared only — no independent traveler confirmation yet."
            )
        }

        val sustainabilityText = exp.sustainabilityPractice
        val isSpecificPractice = sustainabilityText.length > 20 &&
            (sustainabilityText.contains("solar", true) || sustainabilityText.contains("organic", true) ||
                sustainabilityText.contains("electric", true) || sustainabilityText.contains("zero", true) ||
                sustainabilityText.contains("recycl", true) || sustainabilityText.contains("local", true))
        claims += EvidenceClaim(
            claim = "Sustainability: $sustainabilityText",
            confidence = if (isSpecificPractice) ConfidenceLevel.REPORTED else ConfidenceLevel.INFERRED,
            sources = if (isSpecificPractice) listOf("Provider-listed sustainability practice") else listOf("Category heuristic: ${exp.category}"),
            contradiction = if (!isSpecificPractice)
                "No specific, checkable sustainability practice was provided — this is a category-based estimate, not a verified claim."
            else null
        )

        return claims
    }
}
