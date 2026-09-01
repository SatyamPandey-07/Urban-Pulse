package com.urbanpulse.app.data

import android.content.Context
import com.urbanpulse.app.HospitalityStay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

/**
 * Reads hospitality listings from the on-device SQLite store instead of a
 * static in-code list. The city-average comparison and "%% cleaner" copy are
 * computed from the stored numeric carbon value at read time.
 */
class HospitalityRepository(context: Context) {

    private val dbHelper = AppDatabaseHelper.getInstance(context)
    private val cityAverageCarbonKg = 13.0

    suspend fun getAllStays(): List<HospitalityStay> = withContext(Dispatchers.IO) {
        val db = dbHelper.readableDatabase
        val cursor = db.query(
            AppDatabaseHelper.TABLE_STAYS,
            null, null, null, null, null, "eco_score DESC"
        )
        val stays = mutableListOf<HospitalityStay>()
        cursor.use {
            while (it.moveToNext()) {
                val carbonKg = it.getDouble(it.getColumnIndexOrThrow("carbon_kg_per_night"))
                val priceRupees = it.getInt(it.getColumnIndexOrThrow("price_rupees"))
                val belowAvgPct = (((cityAverageCarbonKg - carbonKg) / cityAverageCarbonKg) * 100).roundToInt().coerceAtLeast(0)

                stays += HospitalityStay(
                    id = it.getString(it.getColumnIndexOrThrow("id")),
                    name = it.getString(it.getColumnIndexOrThrow("name")),
                    category = it.getString(it.getColumnIndexOrThrow("category")),
                    location = it.getString(it.getColumnIndexOrThrow("location")),
                    ecoScore = it.getInt(it.getColumnIndexOrThrow("eco_score")),
                    accessibilityRating = it.getInt(it.getColumnIndexOrThrow("accessibility_rating")),
                    energySource = it.getString(it.getColumnIndexOrThrow("energy_source")),
                    wastePolicy = it.getString(it.getColumnIndexOrThrow("waste_policy")),
                    accessibilityTags = it.getString(it.getColumnIndexOrThrow("accessibility_tags")).split("|"),
                    carbonFootprintPerNight = String.format(
                        java.util.Locale.US, "%.1f kg CO2e / night (%d%% below city avg)", carbonKg, belowAvgPct
                    ),
                    pricePerNight = String.format(java.util.Locale.US, "₹%,d / night", priceRupees),
                    contactPhone = it.getString(it.getColumnIndexOrThrow("contact_phone"))
                )
            }
        }
        stays
    }
}
