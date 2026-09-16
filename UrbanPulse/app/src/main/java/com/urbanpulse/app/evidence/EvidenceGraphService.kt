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

    private val measuredCarbon = Regex("""\d+(\.\d+)?\s*kg""")

    fun buildEvidence(stay: HospitalityStay): List<EvidenceClaim> {
        val claims = mutableListOf<EvidenceClaim>()

        val hasMeasuredCarbon = measuredCarbon.containsMatchIn(stay.carbonFootprintPerNight)
        claims += when {
            hasMeasuredCarbon && stay.ecoScore >= 4 -> EvidenceClaim(
                claim = "Sustainability: ${stay.energySource}",
                confidence = ConfidenceLevel.VERIFIED,
                sources = listOf("Operator energy disclosure", "Measured carbon footprint: ${stay.carbonFootprintPerNight}")
            )
            hasMeasuredCarbon -> EvidenceClaim(
                claim = "Sustainability: ${stay.energySource}",
                confidence = ConfidenceLevel.REPORTED,
                sources = listOf("Operator energy disclosure")
            )
            else -> EvidenceClaim(
                claim = "Sustainability: ${stay.energySource}",
                confidence = ConfidenceLevel.INFERRED,
                sources = listOf("Category heuristic: ${stay.category}")
            )
        }

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
        claims += EvidenceClaim(
            claim = "Accessibility: ${exp.accessibilityRating}% match, $tagCount documented feature(s)",
            confidence = if (underDocumented) ConfidenceLevel.INFERRED else ConfidenceLevel.VERIFIED,
            sources = exp.accessibilityTags,
            contradiction = if (underDocumented)
                "Rating claims ${exp.accessibilityRating}% but accessibility features are generic or under-documented — treat as inferred until confirmed on-site."
            else null
        )

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
