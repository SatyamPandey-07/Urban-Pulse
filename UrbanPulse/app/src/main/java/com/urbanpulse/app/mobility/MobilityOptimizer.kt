package com.urbanpulse.app.mobility

enum class TradeoffPriority { ECO, STEP_FREE, FASTEST, BUDGET, BALANCED }

/**
 * Multi-objective comparison across carbon, accessibility, time and cost —
 * the same Pareto-badge approach used for hospitality, applied to mobility.
 */
object MobilityOptimizer {

    private fun normalize(value: Double, min: Double, max: Double, higherIsBetter: Boolean): Double {
        if (max == min) return 1.0
        val n = (value - min) / (max - min)
        return if (higherIsBetter) n else 1 - n
    }

    /** Scores and sorts options for a given priority, and computes cross-cutting badges. Impractical options (e.g. a 20km walk) sink to the bottom and never win a badge. */
    fun rank(options: List<MobilityOption>, priority: TradeoffPriority, requireStepFree: Boolean): List<MobilityOption> {
        val carbons = options.map { it.carbonGrams }
        val durations = options.map { it.durationMin.toDouble() }
        val fares = options.map { it.fareRupees.toDouble() }

        val carbonRange = carbons.min() to carbons.max()
        val durationRange = durations.min() to durations.max()
        val fareRange = fares.min() to fares.max()

        val scored = options.mapIndexed { i, option ->
            val carbonScore = normalize(carbons[i], carbonRange.first, carbonRange.second, higherIsBetter = false)
            val fastScore = normalize(durations[i], durationRange.first, durationRange.second, higherIsBetter = false)
            val budgetScore = normalize(fares[i], fareRange.first, fareRange.second, higherIsBetter = false)
            val accessScore = if (option.stepFreeAccessible) 1.0 else 0.0

            var score = when (priority) {
                TradeoffPriority.ECO -> carbonScore * 0.7 + budgetScore * 0.15 + fastScore * 0.15
                TradeoffPriority.STEP_FREE -> accessScore * 0.7 + carbonScore * 0.2 + fastScore * 0.1
                TradeoffPriority.FASTEST -> fastScore * 0.7 + carbonScore * 0.15 + budgetScore * 0.15
                TradeoffPriority.BUDGET -> budgetScore * 0.7 + carbonScore * 0.15 + fastScore * 0.15
                TradeoffPriority.BALANCED -> carbonScore * 0.3 + fastScore * 0.25 + budgetScore * 0.25 + accessScore * 0.2
            }
            if (!option.practical) score -= 10.0 // sink impractical options (e.g. a 20km walk) without hiding them
            option.copy(balanceScore = score)
        }

        val filtered = if (requireStepFree) scored.filter { it.stepFreeAccessible }.ifEmpty { scored } else scored
        return filtered.sortedByDescending { it.balanceScore }
    }

    fun badgeFor(option: MobilityOption, ranked: List<MobilityOption>): String {
        if (!option.practical) return "NOT PRACTICAL"

        val practicalOnly = ranked.filter { it.practical }
        val greenest = practicalOnly.minByOrNull { it.carbonGrams }
        val fastest = practicalOnly.minByOrNull { it.durationMin }
        val cheapest = practicalOnly.minByOrNull { it.fareRupees }
        val topRanked = practicalOnly.firstOrNull()

        return when {
            option == topRanked -> "#1 BEST MATCH"
            option == greenest -> "GREENEST OPTION"
            option == fastest -> "FASTEST ROUTE"
            option == cheapest -> "LOWEST FARE"
            option.stepFreeAccessible -> "STEP-FREE ACCESSIBLE"
            else -> ""
        }
    }
}
