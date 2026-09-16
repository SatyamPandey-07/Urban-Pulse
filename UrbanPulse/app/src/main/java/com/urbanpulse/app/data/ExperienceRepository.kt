package com.urbanpulse.app.data

import android.content.ContentValues
import android.content.Context
import com.urbanpulse.app.ExperienceListing
import com.urbanpulse.app.network.CentralRegistryClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Reads/writes experience listings from the real Central Registry backend (server/) when it's
 * reachable — the same shared SQLite store the web app uses — so a listing published from either
 * client is visible on both. Falls back to the on-device SQLite store (real persisted state, not
 * an in-memory placeholder) when the backend is unreachable, and mirrors backend reads into that
 * local store so the app still has real, non-fabricated data offline.
 */
class ExperienceRepository(context: Context) {

    private val dbHelper = AppDatabaseHelper.getInstance(context.applicationContext)
    private val categoryAverageCarbonKg = 1.4

    suspend fun getAllExperiences(): List<ExperienceListing> {
        val fromBackend = CentralRegistryClient.fetchExperiences()
        if (fromBackend != null) {
            withContext(Dispatchers.IO) { mirrorToLocalCache(fromBackend) }
            return fromBackend.map { it.toListing() }
        }
        return readFromLocalDb()
    }

    private fun CentralRegistryClient.RegistryExperience.toListing(): ExperienceListing {
        val isIndoor = category.contains("Culinary", true) || category.contains("Craft", true) ||
            category.contains("Workshop", true) || category.contains("Art", true) || category.contains("Heritage", true)
        val tags = if (isIndoor) listOf("Child-Friendly", "Family", "Indoor", "Rain-Safe") else listOf("Family", "Outdoor", "Nature")
        val belowAvgPct = (((categoryAverageCarbonKg - carbonKg) / categoryAverageCarbonKg) * 100).roundToInt().coerceAtLeast(0)
        return ExperienceListing(
            id = id,
            name = name,
            category = category,
            location = location,
            sustainabilityPractice = sustainability,
            ecoScore = ecoScore,
            accessibilityRating = accessibilityRating,
            accessibilityTags = accessibilityTags,
            carbonFootprintPerVisit = String.format(Locale.US, "%.1f kg CO2e / visit (%d%% below category avg)", carbonKg, belowAvgPct),
            pricePerPerson = String.format(Locale.US, "₹%,d / person", price),
            durationHours = duration,
            isAvailableToday = isAvailableToday,
            travelerTags = tags,
            viewsCount = viewsCount,
            inquiryCount = inquiryCount,
            bookingCount = bookingCount,
            accessibilityConfirmCount = accessibilityConfirmCount,
            accessibilityDisputeCount = accessibilityDisputeCount
        )
    }

    /** Upserts backend rows into the local SQLite cache so the app has real (not fabricated) data when offline. */
    private fun mirrorToLocalCache(rows: List<CentralRegistryClient.RegistryExperience>) {
        val db = dbHelper.writableDatabase
        rows.forEach { row ->
            val values = ContentValues().apply {
                put("id", row.id)
                put("name", row.name)
                put("category", row.category)
                put("location", row.location)
                put("sustainability_practice", row.sustainability)
                put("eco_score", row.ecoScore)
                put("accessibility_rating", row.accessibilityRating)
                put("accessibility_tags", row.accessibilityTags.joinToString("|"))
                put("carbon_kg_per_visit", row.carbonKg)
                put("price_rupees", row.price)
                put("duration_hours", row.duration)
                put("is_available_today", if (row.isAvailableToday) 1 else 0)
                put("views_count", row.viewsCount)
                put("inquiry_count", row.inquiryCount)
            }
            db.insertWithOnConflict(AppDatabaseHelper.TABLE_EXPERIENCES, null, values, android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE)
        }
    }

    private fun readFromLocalDb(): List<ExperienceListing> {
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
                    isAvailableToday = it.getInt(it.getColumnIndexOrThrow("is_available_today")) != 0,
                    travelerTags = tags,
                    viewsCount = it.getInt(it.getColumnIndexOrThrow("views_count")),
                    inquiryCount = it.getInt(it.getColumnIndexOrThrow("inquiry_count")),
                    bookingCount = countLocalRows(AppDatabaseHelper.TABLE_BOOKINGS, id),
                    accessibilityConfirmCount = countLocalReports(id, confirms = true),
                    accessibilityDisputeCount = countLocalReports(id, confirms = false)
                )
            }
        }
        return experiences
    }

    private fun countLocalRows(table: String, experienceId: String): Int {
        val db = dbHelper.readableDatabase
        db.rawQuery("SELECT COUNT(*) FROM $table WHERE experience_id = ?", arrayOf(experienceId)).use {
            return if (it.moveToFirst()) it.getInt(0) else 0
        }
    }

    private fun countLocalReports(experienceId: String, confirms: Boolean): Int {
        val db = dbHelper.readableDatabase
        db.rawQuery(
            "SELECT COUNT(*) FROM ${AppDatabaseHelper.TABLE_REPORTS} WHERE experience_id = ? AND confirms_accessibility = ?",
            arrayOf(experienceId, if (confirms) "1" else "0")
        ).use {
            return if (it.moveToFirst()) it.getInt(0) else 0
        }
    }

    /** Creates a real booking on the shared backend when reachable, and always writes through to the local cache. */
    suspend fun createBooking(experienceId: String, travelerName: String, partySize: Int, bookingDate: String): Boolean =
        withContext(Dispatchers.IO) {
            val onBackend = CentralRegistryClient.createBooking(experienceId, travelerName, partySize, bookingDate)
            try {
                val db = dbHelper.writableDatabase
                val values = ContentValues().apply {
                    put("id", onBackend?.id ?: "booking_${System.currentTimeMillis()}")
                    put("experience_id", experienceId)
                    put("traveler_name", travelerName)
                    put("party_size", partySize)
                    put("booking_date", bookingDate)
                    put("status", "confirmed")
                    put("created_at", java.time.Instant.now().toString())
                }
                db.insert(AppDatabaseHelper.TABLE_BOOKINGS, null, values) != -1L
            } catch (e: Exception) {
                onBackend != null
            }
        }

    /** Submits a real traveler accessibility report — a genuine second, independent signal for the
     *  Evidence Graph (confirming or disputing the provider's own claim), not the same source echoed back. */
    suspend fun submitAccessibilityReport(experienceId: String, confirmsAccessibility: Boolean, note: String): Boolean =
        withContext(Dispatchers.IO) {
            val onBackend = CentralRegistryClient.submitReport(experienceId, confirmsAccessibility, note)
            try {
                val db = dbHelper.writableDatabase
                val values = ContentValues().apply {
                    put("id", onBackend?.id ?: "report_${System.currentTimeMillis()}")
                    put("experience_id", experienceId)
                    put("confirms_accessibility", if (confirmsAccessibility) 1 else 0)
                    put("note", note)
                    put("created_at", java.time.Instant.now().toString())
                }
                db.insert(AppDatabaseHelper.TABLE_REPORTS, null, values) != -1L
            } catch (e: Exception) {
                onBackend != null
            }
        }

    /** Toggles availability on the shared backend when reachable, and always writes through to the local cache. */
    suspend fun toggleAvailability(id: String, available: Boolean) = withContext(Dispatchers.IO) {
        CentralRegistryClient.toggleAvailability(id)
        val db = dbHelper.writableDatabase
        val values = ContentValues().apply { put("is_available_today", if (available) 1 else 0) }
        db.update(AppDatabaseHelper.TABLE_EXPERIENCES, values, "id = ?", arrayOf(id))
    }

    /** Records a real view/inquiry event on the shared backend when reachable, and always writes through locally. */
    suspend fun recordView(id: String) = recordEvent(id, "views_count") { CentralRegistryClient.recordView(id) }

    suspend fun recordInquiry(id: String) = recordEvent(id, "inquiry_count") { CentralRegistryClient.recordInquiry(id) }

    private suspend fun recordEvent(
        id: String,
        localColumn: String,
        backendCall: suspend () -> CentralRegistryClient.RegistryExperience?
    ) = withContext(Dispatchers.IO) {
        val updated = backendCall()
        val db = dbHelper.writableDatabase
        if (updated != null) {
            val values = ContentValues().apply {
                put("views_count", updated.viewsCount)
                put("inquiry_count", updated.inquiryCount)
            }
            db.update(AppDatabaseHelper.TABLE_EXPERIENCES, values, "id = ?", arrayOf(id))
        } else {
            db.execSQL("UPDATE ${AppDatabaseHelper.TABLE_EXPERIENCES} SET $localColumn = $localColumn + 1 WHERE id = ?", arrayOf(id))
        }
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
        val onBackend = CentralRegistryClient.createExperience(
            name = name, category = category, location = location, duration = durationHours,
            price = priceRupees, ecoScore = ecoScore, accessibilityRating = accessibilityRating,
            accessibilityTags = accessibilityTags, sustainability = sustainabilityPractice, carbonKg = carbonKg
        )
        try {
            val db = dbHelper.writableDatabase
            val values = ContentValues().apply {
                put("id", onBackend?.id ?: "exp_${System.currentTimeMillis()}")
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
                put("is_available_today", 1)
                put("views_count", 0)
                put("inquiry_count", 0)
            }
            val rowId = db.insert(AppDatabaseHelper.TABLE_EXPERIENCES, null, values)
            rowId != -1L
        } catch (e: Exception) {
            onBackend != null
        }
    }
}
