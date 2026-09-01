package com.meenakshi.urbanpulse.evidence

import com.meenakshi.urbanpulse.HospitalityStay

/**
 * Multi-objective comparison across carbon footprint, accessibility and price.
 * Returns every option labelled by role (Greenest / Most Accessible / Best
 * Value / Best Balance / Pareto-Optimal) rather than collapsing them into a
 * single "best" answer — an option is only left unlabelled if another option
 * beats it on every axis at once.
 */
object ParetoOptimizer {

    private val carbonPattern = Regex("""(\d+(\.\d+)?)\s*kg""")
    private val pricePattern = Regex("""[\d,]+""")

    private fun parseCarbon(value: String): Double =
        carbonPattern.find(value)?.groupValues?.get(1)?.toDoubleOrNull() ?: Double.MAX_VALUE

    private fun parsePrice(value: String): Double =
        pricePattern.find(value)?.value?.replace(",", "")?.toDoubleOrNull() ?: Double.MAX_VALUE

    private fun normalize(value: Double, min: Double, max: Double, higherIsBetter: Boolean): Double {
        if (max == min) return 1.0
        val n = (value - min) / (max - min)
        return if (higherIsBetter) n else 1 - n
    }

    fun rank(stays: List<HospitalityStay>): List<RankedHospitalityStay> {
        if (stays.isEmpty()) return emptyList()

        val carbons = stays.map { parseCarbon(it.carbonFootprintPerNight) }
        val prices = stays.map { parsePrice(it.pricePerNight) }
        val accessibility = stays.map { it.accessibilityRating.toDouble() }

        val carbonMin = carbons.min(); val carbonMax = carbons.max()
        val priceMin = prices.min(); val priceMax = prices.max()
        val accessMin = accessibility.min(); val accessMax = accessibility.max()

        val balanceScores = stays.indices.map { i ->
            val carbonScore = normalize(carbons[i], carbonMin, carbonMax, higherIsBetter = false)
            val priceScore = normalize(prices[i], priceMin, priceMax, higherIsBetter = false)
            val accessScore = normalize(accessibility[i], accessMin, accessMax, higherIsBetter = true)
            (carbonScore * 0.4) + (accessScore * 0.4) + (priceScore * 0.2)
        }

        val greenestIdx = carbons.indices.minByOrNull { carbons[it] }
        val mostAccessibleIdx = accessibility.indices.maxByOrNull { accessibility[it] }
        val bestValueIdx = prices.indices.minByOrNull { prices[it] }
        val bestBalanceIdx = balanceScores.indices.maxByOrNull { balanceScores[it] }

        return stays.indices.map { i ->
            val badges = mutableListOf<TripOptionBadge>()
            if (i == greenestIdx) badges += TripOptionBadge("Greenest", "Lowest measured carbon footprint of the compared options")
            if (i == mostAccessibleIdx) badges += TripOptionBadge("Most Accessible", "Highest accessibility match rating")
            if (i == bestValueIdx) badges += TripOptionBadge("Best Value", "Lowest price per night")
            if (i == bestBalanceIdx) badges += TripOptionBadge("Best Balance", "Best weighted score across carbon, accessibility and price")

            val isDominated = stays.indices.any { j ->
                j != i &&
                    carbons[j] <= carbons[i] &&
                    prices[j] <= prices[i] &&
                    accessibility[j] >= accessibility[i] &&
                    (carbons[j] < carbons[i] || prices[j] < prices[i] || accessibility[j] > accessibility[i])
            }
            if (!isDominated && badges.isEmpty()) {
                badges += TripOptionBadge("Pareto-Optimal", "Not beaten on carbon, accessibility and price simultaneously by any other option")
            }

            RankedHospitalityStay(
                stay = stays[i],
                evidence = EvidenceGraphService.buildEvidence(stays[i]),
                badges = badges,
                balanceScore = balanceScores[i]
            )
        }.sortedByDescending { it.balanceScore }
    }
}
