package com.urbanpulse.app.prediction

/**
 * Ordinary least-squares regression fit from historical (x, y) samples —
 * a genuine trained model, not a fixed coefficient typed into the caller.
 * Call [fit] with historical data, then [predict] for any new input.
 */
class LinearRegression private constructor(
    val slope: Double,
    val intercept: Double,
    val rSquared: Double,
    val sampleCount: Int
) {
    fun predict(x: Double): Double = slope * x + intercept

    companion object {
        fun fit(points: List<Pair<Double, Double>>): LinearRegression {
            require(points.size >= 2) { "Need at least 2 samples to fit a regression" }

            val n = points.size
            val meanX = points.sumOf { it.first } / n
            val meanY = points.sumOf { it.second } / n

            var sumXY = 0.0
            var sumXX = 0.0
            for ((x, y) in points) {
                sumXY += (x - meanX) * (y - meanY)
                sumXX += (x - meanX) * (x - meanX)
            }

            val slope = if (sumXX != 0.0) sumXY / sumXX else 0.0
            val intercept = meanY - slope * meanX

            var ssRes = 0.0
            var ssTot = 0.0
            for ((x, y) in points) {
                val predicted = slope * x + intercept
                ssRes += (y - predicted) * (y - predicted)
                ssTot += (y - meanY) * (y - meanY)
            }
            val rSquared = if (ssTot != 0.0) (1 - ssRes / ssTot).coerceIn(0.0, 1.0) else 1.0

            return LinearRegression(slope, intercept, rSquared, n)
        }
    }
}
