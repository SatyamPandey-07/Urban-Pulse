package com.urbanpulse.app.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class HotelMetricSample(
    val occupancyPercent: Double,
    val energyKwh: Double,
    val waterLiters: Double,
    val foodWasteKg: Double
)

/** Reads the historical occupancy/energy/water/waste log used to train the forecast models. */
class HotelMetricsRepository(context: Context) {

    private val dbHelper = AppDatabaseHelper.getInstance(context)

    suspend fun getHistory(): List<HotelMetricSample> = withContext(Dispatchers.IO) {
        val db = dbHelper.readableDatabase
        val cursor = db.query(
            AppDatabaseHelper.TABLE_HISTORY,
            null, null, null, null, null, "day_index ASC"
        )
        val samples = mutableListOf<HotelMetricSample>()
        cursor.use {
            while (it.moveToNext()) {
                samples += HotelMetricSample(
                    occupancyPercent = it.getDouble(it.getColumnIndexOrThrow("occupancy_percent")),
                    energyKwh = it.getDouble(it.getColumnIndexOrThrow("energy_kwh")),
                    waterLiters = it.getDouble(it.getColumnIndexOrThrow("water_liters")),
                    foodWasteKg = it.getDouble(it.getColumnIndexOrThrow("food_waste_kg"))
                )
            }
        }
        samples
    }
}
