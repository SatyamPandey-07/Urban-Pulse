package com.urbanpulse.app.trip

import android.content.Context
import android.content.SharedPreferences

data class SelectedStay(
    val id: String,
    val name: String,
    val carbonKgPerNight: Double,
    val priceRupees: Int
)

data class SelectedMobility(
    val modeLabel: String,
    val carbonGrams: Double,
    val fareRupees: Int,
    val distanceKm: Double
)

data class SelectedExperiences(
    val names: List<String>,
    val totalCarbonKg: Double,
    val totalPriceRupees: Int
)

/**
 * Remembers the traveler's current stay + transport choice across screens so
 * a combined trip-level summary can be computed, instead of Hospitality and
 * Green Route Planner staying two independent, unconnected optimizers.
 */
object TripPlanManager {

    private const val PREF_NAME = "urbanpulse_trip_plan"

    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        prefs = context.applicationContext.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
    }

    fun setSelectedStay(stay: SelectedStay) {
        prefs.edit()
            .putString("stay_id", stay.id)
            .putString("stay_name", stay.name)
            .putFloat("stay_carbon_kg", stay.carbonKgPerNight.toFloat())
            .putInt("stay_price", stay.priceRupees)
            .apply()
    }

    fun getSelectedStay(): SelectedStay? {
        val id = prefs.getString("stay_id", null) ?: return null
        return SelectedStay(
            id = id,
            name = prefs.getString("stay_name", "") ?: "",
            carbonKgPerNight = prefs.getFloat("stay_carbon_kg", 0f).toDouble(),
            priceRupees = prefs.getInt("stay_price", 0)
        )
    }

    fun setSelectedMobility(mobility: SelectedMobility) {
        prefs.edit()
            .putString("mobility_label", mobility.modeLabel)
            .putFloat("mobility_carbon_grams", mobility.carbonGrams.toFloat())
            .putInt("mobility_fare", mobility.fareRupees)
            .putFloat("mobility_distance_km", mobility.distanceKm.toFloat())
            .apply()
    }

    fun getSelectedMobility(): SelectedMobility? {
        val label = prefs.getString("mobility_label", null) ?: return null
        return SelectedMobility(
            modeLabel = label,
            carbonGrams = prefs.getFloat("mobility_carbon_grams", 0f).toDouble(),
            fareRupees = prefs.getInt("mobility_fare", 0),
            distanceKm = prefs.getFloat("mobility_distance_km", 0f).toDouble()
        )
    }

    fun setSelectedExperiences(experiences: SelectedExperiences) {
        prefs.edit()
            .putString("experience_names", experiences.names.joinToString("|"))
            .putFloat("experience_total_carbon_kg", experiences.totalCarbonKg.toFloat())
            .putInt("experience_total_price", experiences.totalPriceRupees)
            .apply()
    }

    fun getSelectedExperiences(): SelectedExperiences? {
        val namesJoined = prefs.getString("experience_names", null) ?: return null
        return SelectedExperiences(
            names = namesJoined.split("|"),
            totalCarbonKg = prefs.getFloat("experience_total_carbon_kg", 0f).toDouble(),
            totalPriceRupees = prefs.getInt("experience_total_price", 0)
        )
    }
}
