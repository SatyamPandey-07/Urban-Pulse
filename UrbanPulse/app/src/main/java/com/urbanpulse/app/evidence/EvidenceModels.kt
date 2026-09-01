package com.urbanpulse.app.evidence

import com.urbanpulse.app.HospitalityStay

/**
 * Confidence tiers for a claim in the Evidence Graph.
 * VERIFIED  — corroborated by two or more independent signals (e.g. a measured figure + operator disclosure)
 * REPORTED  — stated by a single source (e.g. operator disclosure only)
 * INFERRED  — derived from a heuristic when direct evidence is thin or inconsistent
 * UNKNOWN   — no signal available
 */
enum class ConfidenceLevel(val label: String, val icon: String) {
    VERIFIED("Verified", "✅"),
    REPORTED("Reported", "🟡"),
    INFERRED("Inferred", "🔵"),
    UNKNOWN("Unknown", "⚪")
}

data class EvidenceClaim(
    val claim: String,
    val confidence: ConfidenceLevel,
    val sources: List<String>,
    val contradiction: String? = null
)

data class TripOptionBadge(
    val label: String,
    val reason: String
)

data class RankedHospitalityStay(
    val stay: HospitalityStay,
    val evidence: List<EvidenceClaim>,
    val badges: List<TripOptionBadge>,
    val balanceScore: Double
)
