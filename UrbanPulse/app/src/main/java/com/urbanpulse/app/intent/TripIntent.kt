package com.urbanpulse.app.intent

/** Structured trip constraints extracted from a traveler's plain-language request. */
data class TripIntent(
    val prioritizeCarbon: Boolean = false,
    val prioritizeAccessibility: Boolean = false,
    val prioritizeSpeed: Boolean = false,
    val prioritizeBudget: Boolean = false,
    val requireWheelchairAccess: Boolean = false,
    val requireSolarEnergy: Boolean = false,
    val requireZeroWaste: Boolean = false,
    val maxPriceRupees: Int? = null,
    val searchKeywords: String = "",
    val parsedBy: String = "rules"
)
