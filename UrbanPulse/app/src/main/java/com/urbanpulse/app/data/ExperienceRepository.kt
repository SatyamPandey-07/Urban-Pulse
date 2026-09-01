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

                experiences += ExperienceListing(
                    id = it.getString(it.getColumnIndexOrThrow("id")),
                    name = it.getString(it.getColumnIndexOrThrow("name")),
                    category = it.getString(it.getColumnIndexOrThrow("category")),
                    location = it.getString(it.getColumnIndexOrThrow("location")),
                    sustainabilityPractice = it.getString(it.getColumnIndexOrThrow("sustainability_practice")),
                    ecoScore = it.getInt(it.getColumnIndexOrThrow("eco_score")),
                    accessibilityRating = it.getInt(it.getColumnIndexOrThrow("accessibility_rating")),
                    accessibilityTags = it.getString(it.getColumnIndexOrThrow("accessibility_tags")).split("|"),
                    carbonFootprintPerVisit = String.format(
                        Locale.US, "%.1f kg CO2e / visit (%d%% below category avg)", carbonKg, belowAvgPct
                    ),
                    pricePerPerson = String.format(Locale.US, "₹%,d / person", priceRupees),
                    durationHours = it.getDouble(it.getColumnIndexOrThrow("duration_hours"))
                )
            }
        }
        experiences
    }
}
