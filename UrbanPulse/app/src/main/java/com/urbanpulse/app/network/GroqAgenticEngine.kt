package com.urbanpulse.app.network

import com.urbanpulse.app.BuildConfig
import com.urbanpulse.app.TripActivity
import com.urbanpulse.app.TripDaySchedule
import com.urbanpulse.app.TripPlan
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

data class GroqAgentResponse(
    val replyText: String,
    val mcqOptions: List<String>? = null,
    val structuredTrip: TripPlan? = null
)

object GroqAgenticEngine {

    private const val GROQ_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"
    private const val MODEL_NAME = "llama-3.3-70b-versatile"

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .build()

    private fun getSystemPrompt(userLat: Double, userLon: Double, isWheelchair: Boolean): String {
        return """
            You are Yatri AI, the autonomous green mobility & accessible hospitality agent for UrbanPulse.
            User GPS location: ($userLat, $userLon).
            User Wheelchair Mode: $isWheelchair.
            
            You have access to live environmental tools, TomTom POI search, and multi-day itinerary generation.
            
            When planning a trip:
            1. If the destination is known but duration isn't specified, ask how many days (1-7 days) and provide concise MCQ options in your reply.
            2. If duration is selected, ask travel style & accessibility preference with MCQ options (e.g., Wheelchair/Palki Step-Free ♿, Eco Nature 🌿, Budget Explorer 🎒, Luxury 🏰).
            3. When generating the itinerary, generate a realistic schedule with eco-transit (Electric train, Vande Bharat, AC E-Bus), verified solar/eco stays, air quality estimate, and carbon avoided vs petrol vehicles.
            
            Always be helpful, evidence-grounded, and concise.
        """.trimIndent()
    }

    suspend fun runAgentLoop(
        prompt: String,
        userLat: Double,
        userLon: Double,
        isWheelchair: Boolean,
        pendingDestination: String? = null,
        pendingDays: Int? = null
    ): GroqAgentResponse = withContext(Dispatchers.IO) {
        val apiKey = BuildConfig.GROQ_API_KEY
        if (apiKey.isBlank() || apiKey == "DEMO_GROQ_KEY") {
            return@withContext GroqAgentResponse(
                replyText = LiveCityIntelligenceService.queryGroundedIntelligence(prompt, userLat, userLon, isWheelchair)
            )
        }

        try {
            val systemPrompt = getSystemPrompt(userLat, userLon, isWheelchair)

            val messages = JSONArray().apply {
                put(JSONObject().apply {
                    put("role", "system")
                    put("content", systemPrompt)
                })
                put(JSONObject().apply {
                    put("role", "user")
                    put("content", prompt)
                })
            }

            val requestJson = JSONObject().apply {
                put("model", MODEL_NAME)
                put("messages", messages)
                put("temperature", 0.3)
                put("max_tokens", 800)
            }

            val requestBody = requestJson.toString().toRequestBody("application/json".toMediaType())
            val request = Request.Builder()
                .url(GROQ_ENDPOINT)
                .addHeader("Authorization", "Bearer $apiKey")
                .addHeader("Content-Type", "application/json")
                .post(requestBody)
                .build()

            val response = httpClient.newCall(request).execute()
            val body = response.body?.string()

            if (!response.isSuccessful || body == null) {
                return@withContext GroqAgentResponse(
                    replyText = LiveCityIntelligenceService.queryGroundedIntelligence(prompt, userLat, userLon, isWheelchair)
                )
            }

            val responseObj = JSONObject(body)
            val choices = responseObj.optJSONArray("choices")
            if (choices == null || choices.length() == 0) {
                return@withContext GroqAgentResponse(
                    replyText = "I am analyzing your request with Groq AI."
                )
            }

            val rawContent = choices.getJSONObject(0).optJSONObject("message")?.optString("content") ?: ""

            // Extract MCQ options if present
            var mcqList: List<String>? = null
            val lowerPrompt = prompt.lowercase()

            if (lowerPrompt.contains("plan") || lowerPrompt.contains("trip") || lowerPrompt.contains("itinerary") || pendingDestination != null) {
                if (pendingDestination != null && pendingDays == null) {
                    val isHimalayan = pendingDestination.contains("Kedar", true) || pendingDestination.contains("Manali", true)
                    mcqList = if (isHimalayan) {
                        listOf("3 Days Express Yatra", "4 Days Pilgrim Trek", "7 Days Complete Circuit", "Custom")
                    } else {
                        listOf("1 Day Express (Same Day)", "2 Days Weekend", "3 Days Leisure", "Custom Duration")
                    }
                } else if (pendingDestination != null && pendingDays != null) {
                    val isHimalayan = pendingDestination.contains("Kedar", true) || pendingDestination.contains("Manali", true)
                    mcqList = if (isHimalayan) {
                        listOf("Palki & Accessible ♿", "Eco Pilgrim Trek 🌿", "Budget Devotee 🎒", "Heli-Yatra & Luxury 🚁")
                    } else {
                        listOf("Wheelchair Step-Free ♿", "Eco Nature & Farm 🌿", "Budget Explorer 🎒", "Luxury Heritage 🏰")
                    }
                }
            }

            GroqAgentResponse(
                replyText = rawContent,
                mcqOptions = mcqList
            )
        } catch (e: Exception) {
            GroqAgentResponse(
                replyText = LiveCityIntelligenceService.queryGroundedIntelligence(prompt, userLat, userLon, isWheelchair)
            )
        }
    }
}
