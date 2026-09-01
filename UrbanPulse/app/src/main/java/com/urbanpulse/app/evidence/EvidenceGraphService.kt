package com.urbanpulse.app.evidence

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
}
