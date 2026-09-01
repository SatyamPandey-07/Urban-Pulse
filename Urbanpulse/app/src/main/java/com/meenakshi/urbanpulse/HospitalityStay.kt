package com.meenakshi.urbanpulse

data class HospitalityStay(
    val id: String,
    val name: String,
    val category: String, // "Eco-Resort", "Green Hotel", "Sustainable Dining"
    val location: String,
    val ecoScore: Int, // 1 to 5 leaves
    val accessibilityRating: Int, // 1 to 100%
    val energySource: String, // e.g. "100% Solar & Wind"
    val wastePolicy: String, // e.g. "Zero Single-Use Plastic • Organic Composting"
    val accessibilityTags: List<String>, // e.g. ["Wheelchair Ramp", "Roll-in Shower", "Braille Elevators", "Hearing Loop"]
    val carbonFootprintPerNight: String, // e.g. "4.2 kg CO2e / night (68% below city avg)"
    val pricePerNight: String,
    val contactPhone: String
)
