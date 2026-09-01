package com.meenakshi.urbanpulse.viewmodel

import androidx.lifecycle.ViewModel
import com.meenakshi.urbanpulse.HospitalityStay
import com.meenakshi.urbanpulse.evidence.ParetoOptimizer
import com.meenakshi.urbanpulse.evidence.RankedHospitalityStay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class HospitalityViewModel : ViewModel() {

    enum class ChipFilter { ALL, WHEELCHAIR, SOLAR, ZERO_WASTE, BRAILLE }

    private val allStays = listOf(
        HospitalityStay(
            id = "stay_1",
            name = "The Orchid Eco-Heritage Resort",
            category = "Certified Eco-Resort",
            location = "Vile Parle, Mumbai",
            ecoScore = 5,
            accessibilityRating = 98,
            energySource = "100% Solar & Biogas Grid",
            wastePolicy = "Zero Single-Use Plastic • In-house Composting",
            accessibilityTags = listOf("Wheelchair Ramp", "Roll-in Shower", "Braille Elevators", "Hearing Loop"),
            carbonFootprintPerNight = "4.2 kg CO2e / night (68% below city avg)",
            pricePerNight = "₹4,200 / night",
            contactPhone = "+91 22 2616 4040"
        ),
        HospitalityStay(
            id = "stay_2",
            name = "ITC Grand Central Green Hotel",
            category = "LEED Platinum Luxury Stay",
            location = "Parel, Mumbai",
            ecoScore = 5,
            accessibilityRating = 95,
            energySource = "Wind Farm Powered • 100% LED Sensor Lighting",
            wastePolicy = "Zero Food Waste to Landfill • Treated Greywater",
            accessibilityTags = listOf("Step-Free Entrance", "Tactile Pathways", "Accessible Parking", "Visual Smoke Alarms"),
            carbonFootprintPerNight = "5.1 kg CO2e / night (60% below city avg)",
            pricePerNight = "₹7,800 / night",
            contactPhone = "+91 22 2410 1010"
        ),
        HospitalityStay(
            id = "stay_3",
            name = "Bandra Farm-to-Table Eco Bistro & Suites",
            category = "Sustainable Boutique Stay",
            location = "Bandra West, Mumbai",
            ecoScore = 4,
            accessibilityRating = 92,
            energySource = "Rooftop Solar Array • EV Fast Chargers",
            wastePolicy = "Local Organic Sourcing • Rainwater Harvesting",
            accessibilityTags = listOf("Wheelchair Accessible Dining", "Wide Doorways", "Accessible Restrooms"),
            carbonFootprintPerNight = "3.8 kg CO2e / night (72% below city avg)",
            pricePerNight = "₹3,500 / night",
            contactPhone = "+91 22 2640 5500"
        ),
        HospitalityStay(
            id = "stay_4",
            name = "Sanjay Gandhi Nature Lodge & Eco-Cabins",
            category = "Bio-Reserve Retreat",
            location = "Borivali, Mumbai",
            ecoScore = 5,
            accessibilityRating = 88,
            energySource = "Off-grid Solar • Passive Natural Cooling",
            wastePolicy = "100% Biodegradable • Dry Toilet Systems",
            accessibilityTags = listOf("Gentle Slope Boardwalks", "Audio Trail Guides", "Guide Dog Friendly"),
            carbonFootprintPerNight = "1.9 kg CO2e / night (88% below city avg)",
            pricePerNight = "₹2,400 / night",
            contactPhone = "+91 22 2886 0389"
        )
    )

    private val allRanked: List<RankedHospitalityStay> = ParetoOptimizer.rank(allStays)

    private var query: String = ""
    private var chipFilter: ChipFilter = ChipFilter.ALL

    private val _rankedStays = MutableStateFlow(allRanked)
    val rankedStays: StateFlow<List<RankedHospitalityStay>> = _rankedStays.asStateFlow()

    fun updateQuery(newQuery: String) {
        query = newQuery
        applyFilters()
    }

    fun updateChipFilter(filter: ChipFilter) {
        chipFilter = filter
        applyFilters()
    }

    private fun applyFilters() {
        val q = query.trim().lowercase()
        _rankedStays.value = allRanked.filter { ranked ->
            val stay = ranked.stay
            val matchesQuery = q.isEmpty() ||
                stay.name.lowercase().contains(q) ||
                stay.location.lowercase().contains(q) ||
                stay.category.lowercase().contains(q)

            val matchesChip = when (chipFilter) {
                ChipFilter.ALL -> true
                ChipFilter.WHEELCHAIR -> stay.accessibilityTags.any { it.contains("Wheelchair", true) || it.contains("Step-Free", true) }
                ChipFilter.SOLAR -> stay.energySource.contains("Solar", true)
                ChipFilter.ZERO_WASTE -> stay.wastePolicy.contains("Zero", true)
                ChipFilter.BRAILLE -> stay.accessibilityTags.any { it.contains("Braille", true) || it.contains("Tactile", true) }
            }

            matchesQuery && matchesChip
        }
    }
}
