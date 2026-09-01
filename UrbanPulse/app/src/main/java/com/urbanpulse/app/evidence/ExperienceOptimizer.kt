package com.urbanpulse.app.evidence

import com.urbanpulse.app.ExperienceListing

data class RankedExperience(
    val experience: ExperienceListing,
    val badges: List<TripOptionBadge>,
    val balanceScore: Double
)

/**
 * Same multi-objective ranking approach as [ParetoOptimizer], applied to
 * activities/experiences instead of stays — carbon, accessibility and price,
 * with a Pareto-dominance check so nothing is silently hidden.
 */
object ExperienceOptimizer {

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

    fun rank(experiences: List<ExperienceListing>): List<RankedExperience> {
        if (experiences.isEmpty()) return emptyList()

        val carbons = experiences.map { parseCarbon(it.carbonFootprintPerVisit) }
        val prices = experiences.map { parsePrice(it.pricePerPerson) }
        val accessibility = experiences.map { it.accessibilityRating.toDouble() }

        val carbonMin = carbons.min(); val carbonMax = carbons.max()
        val priceMin = prices.min(); val priceMax = prices.max()
        val accessMin = accessibility.min(); val accessMax = accessibility.max()

        val balanceScores = experiences.indices.map { i ->
            val carbonScore = normalize(carbons[i], carbonMin, carbonMax, higherIsBetter = false)
            val priceScore = normalize(prices[i], priceMin, priceMax, higherIsBetter = false)
            val accessScore = normalize(accessibility[i], accessMin, accessMax, higherIsBetter = true)
            (carbonScore * 0.4) + (accessScore * 0.4) + (priceScore * 0.2)
        }

        val greenestIdx = carbons.indices.minByOrNull { carbons[it] }
        val mostAccessibleIdx = accessibility.indices.maxByOrNull { accessibility[it] }
        val bestValueIdx = prices.indices.minByOrNull { prices[it] }
        val bestBalanceIdx = balanceScores.indices.maxByOrNull { balanceScores[it] }

        return experiences.indices.map { i ->
            val badges = mutableListOf<TripOptionBadge>()
            if (i == greenestIdx) badges += TripOptionBadge("Greenest", "Lowest carbon footprint of the compared experiences")
            if (i == mostAccessibleIdx) badges += TripOptionBadge("Most Accessible", "Highest accessibility rating")
            if (i == bestValueIdx) badges += TripOptionBadge("Best Value", "Lowest price per person")
            if (i == bestBalanceIdx) badges += TripOptionBadge("Best Balance", "Best weighted score across carbon, accessibility and price")

            val isDominated = experiences.indices.any { j ->
                j != i &&
                    carbons[j] <= carbons[i] &&
                    prices[j] <= prices[i] &&
                    accessibility[j] >= accessibility[i] &&
                    (carbons[j] < carbons[i] || prices[j] < prices[i] || accessibility[j] > accessibility[i])
            }
            if (!isDominated && badges.isEmpty()) {
                badges += TripOptionBadge("Pareto-Optimal", "Not beaten on carbon, accessibility and price simultaneously by any other experience")
            }

            RankedExperience(
                experience = experiences[i],
                badges = badges,
                balanceScore = balanceScores[i]
            )
        }.sortedByDescending { it.balanceScore }
    }
}
