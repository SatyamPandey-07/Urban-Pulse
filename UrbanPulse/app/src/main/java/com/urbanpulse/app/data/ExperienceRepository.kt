package com.urbanpulse.app.data

import android.content.Context
import com.urbanpulse.app.ExperienceListing
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.math.roundToInt

/** Reads experience/activity listings from the on-device SQLite store — the "inclusive experience discovery" data source. */
class ExperienceRepository(context: Context) {

    private val dbHelper = AppDatabaseHelper.getInstance(context)
    private val categoryAverageCarbonKg = 1.4

    suspend fun getAllExperiences(): List<ExperienceListing> = withContext(Dispatchers.IO) {
        val db = dbHelper.readableDatabase
        val cursor = db.query(
            AppDatabaseHelper.TABLE_EXPERIENCES,
            null, null, null, null, null, "eco_score DESC"
        )
        val experiences = mutableListOf<ExperienceListing>()
        cursor.use {
            while (it.moveToNext()) {
                val carbonKg = it.getDouble(it.getColumnIndexOrThrow("carbon_kg_per_visit"))
                val priceRupees = it.getInt(it.getColumnIndexOrThrow("price_rupees"))
                val belowAvgPct = (((categoryAverageCarbonKg - carbonKg) / categoryAverageCarbonKg) * 100).roundToInt().coerceAtLeast(0)

                val id = it.getString(it.getColumnIndexOrThrow("id"))
                val name = it.getString(it.getColumnIndexOrThrow("name"))
                val category = it.getString(it.getColumnIndexOrThrow("category"))
                val isIndoor = category.contains("Culinary", true) || category.contains("Craft", true) || 
                    category.contains("Workshop", true) || category.contains("Art", true) || category.contains("Heritage", true)
                val tags = if (isIndoor) listOf("Child-Friendly", "Family", "Indoor", "Rain-Safe") else listOf("Family", "Outdoor", "Nature")
                val isAvailable = availabilityOverrides[id] ?: true

                experiences += ExperienceListing(
                    id = id,
                    name = name,
                    category = category,
                        location = it.getString(it.getColumnIndexOrThrow("location")),
                        sustainabilityPractice = it.getString(it.getColumnIndexOrThrow("sustainability_practice")),
                        ecoScore = it.getInt(it.getColumnIndexOrThrow("eco_score")),
                        accessibilityRating = it.getInt(it.getColumnIndexOrThrow("accessibility_rating")),
                        accessibilityTags = it.getString(it.getColumnIndexOrThrow("accessibility_tags")).split("|"),
                        carbonFootprintPerVisit = String.format(
                            Locale.US, "%.1f kg CO2e / visit (%d%% below category avg)", carbonKg, belowAvgPct
                        ),
                        pricePerPerson = String.format(Locale.US, "₹%,d / person", priceRupees),
                        durationHours = it.getDouble(it.getColumnIndexOrThrow("duration_hours")),
                        isAvailableToday = isAvailable,
                        travelerTags = tags,
                        viewsCount = 110 + (Math.abs(id.hashCode()) % 85)
                    )
                }
            }
            experiences
        }

    fun toggleAvailability(id: String, available: Boolean) {
        availabilityOverrides[id] = available
    }

    suspend fun getAdaptiveExperiences(
        isRain: Boolean = false,
        maxDuration: Double = 3.0,
        familyOnly: Boolean = false
    ): List<ExperienceListing> {
        val all = getAllExperiences().filter { it.isAvailableToday }
        return all.filter { exp ->
            val matchRain = !isRain || exp.travelerTags.contains("Indoor") || exp.travelerTags.contains("Rain-Safe")
            val matchDuration = exp.durationHours <= maxDuration
            val matchFamily = !familyOnly || exp.travelerTags.contains("Child-Friendly")
            matchRain && matchDuration && matchFamily
        }
    }

    suspend fun addExperience(
        name: String,
        category: String,
        location: String,
        sustainabilityPractice: String,
        accessibilityTags: List<String>,
        accessibilityRating: Int = 90,
        ecoScore: Int = 4,
        carbonKg: Double = 0.5,
        priceRupees: Int = 350,
        durationHours: Double = 2.0
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            val db = dbHelper.writableDatabase
            val values = android.content.ContentValues().apply {
                put("id", "exp_${System.currentTimeMillis()}")
                put("name", name)
                put("category", category)
                put("location", location)
                put("sustainability_practice", sustainabilityPractice)
                put("eco_score", ecoScore)
                put("accessibility_rating", accessibilityRating)
                put("accessibility_tags", accessibilityTags.joinToString("|"))
                put("carbon_kg_per_visit", carbonKg)
                put("price_rupees", priceRupees)
                put("duration_hours", durationHours)
            }
            val rowId = db.insert(AppDatabaseHelper.TABLE_EXPERIENCES, null, values)
            rowId != -1L
        } catch (e: Exception) {
            false
        }
    }

    companion object {
        private val availabilityOverrides = mutableMapOf<String, Boolean>()
    }
}
