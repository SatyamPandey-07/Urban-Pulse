package com.urbanpulse.app.network

import com.urbanpulse.app.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Real HTTP client for the Central Registry backend (server/server.js) — the same shared
 * SQLite-backed service the web app talks to. Every call returns null/false on any failure
 * (no network, backend not running, bad response) so callers fall back to the on-device
 * SQLite cache instead of crashing or showing a broken state.
 */
object CentralRegistryClient {

    private val client = OkHttpClient.Builder()
        .connectTimeout(4, TimeUnit.SECONDS)
        .readTimeout(4, TimeUnit.SECONDS)
        .build()

    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()
    private val baseUrl get() = BuildConfig.CENTRAL_REGISTRY_BASE_URL

    data class RegistryExperience(
        val id: String,
        val name: String,
        val category: String,
        val location: String,
        val duration: Double,
        val price: Int,
        val ecoScore: Int,
        val accessibilityRating: Int,
        val accessibilityTags: List<String>,
        val sustainability: String,
        val carbonKg: Double,
        val isAvailableToday: Boolean,
        val viewsCount: Int,
        val inquiryCount: Int,
        val bookingCount: Int,
        val accessibilityConfirmCount: Int,
        val accessibilityDisputeCount: Int
    )

    data class RegistryBooking(
        val id: String,
        val experienceId: String,
        val travelerName: String,
        val partySize: Int,
        val bookingDate: String,
        val status: String
    )

    data class RegistryReport(
        val id: String,
        val experienceId: String,
        val confirmsAccessibility: Boolean,
        val note: String
    )

    data class ImpactStats(
        val experienceCount: Int,
        val bookingCount: Int,
        val travelerCount: Int,
        val accessibilityConfirmCount: Int,
        val accessibilityDisputeCount: Int,
        val bookedExperiencesCarbonFootprintKg: Double,
        val averageEcoScore: Double
    )

    private fun parseExperience(o: JSONObject): RegistryExperience {
        val tagsArray = o.optJSONArray("accessibilityTags") ?: JSONArray()
        val tags = (0 until tagsArray.length()).map { tagsArray.getString(it) }
        return RegistryExperience(
            id = o.getString("id"),
            name = o.getString("name"),
            category = o.optString("category", "General"),
            location = o.optString("location", "Mumbai"),
            duration = o.optDouble("duration", 2.0),
            price = o.optInt("price", 350),
            ecoScore = o.optInt("ecoScore", 5),
            accessibilityRating = o.optInt("accessibilityRating", 75),
            accessibilityTags = tags,
            sustainability = o.optString("sustainability", ""),
            carbonKg = o.optDouble("carbonKg", 0.3),
            isAvailableToday = o.optBoolean("isAvailableToday", true),
            viewsCount = o.optInt("viewsCount", 0),
            inquiryCount = o.optInt("inquiryCount", 0),
            bookingCount = o.optInt("bookingCount", 0),
            accessibilityConfirmCount = o.optInt("accessibilityConfirmCount", 0),
            accessibilityDisputeCount = o.optInt("accessibilityDisputeCount", 0)
        )
    }

    private fun parseBooking(o: JSONObject) = RegistryBooking(
        id = o.getString("id"),
        experienceId = o.getString("experienceId"),
        travelerName = o.optString("travelerName", "Traveler"),
        partySize = o.optInt("partySize", 1),
        bookingDate = o.optString("bookingDate", ""),
        status = o.optString("status", "confirmed")
    )

    private fun parseReport(o: JSONObject) = RegistryReport(
        id = o.getString("id"),
        experienceId = o.getString("experienceId"),
        confirmsAccessibility = o.optBoolean("confirmsAccessibility", true),
        note = o.optString("note", "")
    )

    suspend fun fetchExperiences(): List<RegistryExperience>? = withContext(Dispatchers.IO) {
        try {
            val req = Request.Builder().url("$baseUrl/api/experiences").get().build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext null
                val body = resp.body?.string() ?: return@withContext null
                val arr = JSONArray(body)
                (0 until arr.length()).map { parseExperience(arr.getJSONObject(it)) }
            }
        } catch (e: Exception) {
            null
        }
    }

    suspend fun createExperience(
        name: String,
        category: String,
        location: String,
        duration: Double,
        price: Int,
        ecoScore: Int,
        accessibilityRating: Int,
        accessibilityTags: List<String>,
        sustainability: String,
        carbonKg: Double
    ): RegistryExperience? = withContext(Dispatchers.IO) {
        try {
            val payload = JSONObject().apply {
                put("name", name)
                put("category", category)
                put("location", location)
                put("duration", duration)
                put("price", price)
                put("ecoScore", ecoScore)
                put("accessibilityRating", accessibilityRating)
                put("accessibilityTags", JSONArray(accessibilityTags))
                put("sustainability", sustainability)
                put("carbonKg", carbonKg)
            }
            val req = Request.Builder()
                .url("$baseUrl/api/experiences")
                .post(payload.toString().toRequestBody(jsonMediaType))
                .build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext null
                val body = resp.body?.string() ?: return@withContext null
                parseExperience(JSONObject(body))
            }
        } catch (e: Exception) {
            null
        }
    }

    suspend fun toggleAvailability(id: String): RegistryExperience? = withContext(Dispatchers.IO) {
        try {
            val req = Request.Builder()
                .url("$baseUrl/api/experiences/$id/availability")
                .patch("".toRequestBody(null))
                .build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext null
                val body = resp.body?.string() ?: return@withContext null
                parseExperience(JSONObject(body))
            }
        } catch (e: Exception) {
            null
        }
    }

    private suspend fun recordEvent(id: String, endpoint: String): RegistryExperience? = withContext(Dispatchers.IO) {
        try {
            val req = Request.Builder()
                .url("$baseUrl/api/experiences/$id/$endpoint")
                .post("".toRequestBody(null))
                .build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext null
                val body = resp.body?.string() ?: return@withContext null
                parseExperience(JSONObject(body))
            }
        } catch (e: Exception) {
            null
        }
    }

    suspend fun recordView(id: String): RegistryExperience? = recordEvent(id, "view")

    suspend fun recordInquiry(id: String): RegistryExperience? = recordEvent(id, "inquiry")

    suspend fun createBooking(experienceId: String, travelerName: String, partySize: Int, bookingDate: String): RegistryBooking? =
        withContext(Dispatchers.IO) {
            try {
                val payload = JSONObject().apply {
                    put("travelerName", travelerName)
                    put("partySize", partySize)
                    put("bookingDate", bookingDate)
                }
                val req = Request.Builder()
                    .url("$baseUrl/api/experiences/$experienceId/bookings")
                    .post(payload.toString().toRequestBody(jsonMediaType))
                    .build()
                client.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) return@withContext null
                    val body = resp.body?.string() ?: return@withContext null
                    parseBooking(JSONObject(body))
                }
            } catch (e: Exception) {
                null
            }
        }

    /** Real cross-user aggregate stats computed by the backend via SQL over actual rows —
     *  not a fabricated headline number. Mirrors the same /api/impact-stats endpoint the web app uses. */
    suspend fun fetchImpactStats(): ImpactStats? = withContext(Dispatchers.IO) {
        try {
            val req = Request.Builder().url("$baseUrl/api/impact-stats").get().build()
            client.newCall(req).execute().use { resp ->
                if (!resp.isSuccessful) return@withContext null
                val body = resp.body?.string() ?: return@withContext null
                val o = JSONObject(body)
                ImpactStats(
                    experienceCount = o.optInt("experienceCount", 0),
                    bookingCount = o.optInt("bookingCount", 0),
                    travelerCount = o.optInt("travelerCount", 0),
                    accessibilityConfirmCount = o.optInt("accessibilityConfirmCount", 0),
                    accessibilityDisputeCount = o.optInt("accessibilityDisputeCount", 0),
                    bookedExperiencesCarbonFootprintKg = o.optDouble("bookedExperiencesCarbonFootprintKg", 0.0),
                    averageEcoScore = o.optDouble("averageEcoScore", 0.0)
                )
            }
        } catch (e: Exception) {
            null
        }
    }

    suspend fun submitReport(experienceId: String, confirmsAccessibility: Boolean, note: String): RegistryReport? =
        withContext(Dispatchers.IO) {
            try {
                val payload = JSONObject().apply {
                    put("confirmsAccessibility", confirmsAccessibility)
                    put("note", note)
                }
                val req = Request.Builder()
                    .url("$baseUrl/api/experiences/$experienceId/reports")
                    .post(payload.toString().toRequestBody(jsonMediaType))
                    .build()
                client.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) return@withContext null
                    val body = resp.body?.string() ?: return@withContext null
                    parseReport(JSONObject(body))
                }
            } catch (e: Exception) {
                null
            }
        }
}
