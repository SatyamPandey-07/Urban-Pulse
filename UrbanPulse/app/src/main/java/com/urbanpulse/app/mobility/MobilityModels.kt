package com.urbanpulse.app.mobility

enum class TravelMode(val label: String) {
    METRO("Electric Metro"),
    BUS("Electric AC Bus"),
    EV_CAB("Shared EV Rideshare"),
    TAXI("Conventional Petrol Cab")
}

data class MobilityOption(
    val mode: TravelMode,
    val distanceKm: Double,
    val durationMin: Int,
    val fareRupees: Int,
    val carbonGrams: Double,
    val stepFreeAccessible: Boolean,
    val accessibilityNote: String,
    val balanceScore: Double = 0.0
) {
    /** CO2 avoided per passenger versus the conventional petrol taxi baseline. */
    fun carbonAvoidedVsBaseline(baselineGrams: Double): Double = (baselineGrams - carbonGrams).coerceAtLeast(0.0)
}

data class RankedMobilityOptions(
    val options: List<MobilityOption>,
    val badges: Map<TravelMode, List<String>>
)
