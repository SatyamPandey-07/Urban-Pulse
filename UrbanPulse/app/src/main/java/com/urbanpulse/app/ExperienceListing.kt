package com.urbanpulse.app

data class ExperienceListing(
    val id: String,
    val name: String,
    val category: String, // "Heritage & Art", "Nature & Wildlife", "Culinary & Farming", ...
    val location: String,
    val sustainabilityPractice: String,
    val ecoScore: Int, // 1 to 5 leaves
    val accessibilityRating: Int, // 0 to 100%
    val accessibilityTags: List<String>,
    val carbonFootprintPerVisit: String, // e.g. "0.8 kg CO2e / visit"
    val pricePerPerson: String, // e.g. "₹610 / person"
    val durationHours: Double
)
