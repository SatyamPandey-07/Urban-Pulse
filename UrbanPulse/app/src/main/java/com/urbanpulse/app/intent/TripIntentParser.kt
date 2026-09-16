package com.urbanpulse.app.intent

import com.google.ai.client.generativeai.GenerativeModel
import com.google.gson.Gson
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
 * Turns a traveler's free-text request into structured [TripIntent] constraints.
 * Tries the real Groq LPU cloud first (sub-400ms structured JSON extraction, matching
 * the pitch), falls back to Gemini if Groq is unavailable/fails, and finally falls back
 * to a deterministic keyword parser so the feature still works with no live config at all.
 */
object TripIntentParser {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    private val groqCandidateModels = listOf("openai/gpt-oss-120b", "groq/compound", "openai/gpt-oss-20b")

    private const val INTENT_SCHEMA = """
        Respond with ONLY a raw JSON object (no markdown fences, no commentary) matching exactly this shape:
        {
          "prioritizeCarbon": boolean,
          "prioritizeAccessibility": boolean,
          "prioritizeSpeed": boolean,
          "prioritizeBudget": boolean,
          "requireWheelchairAccess": boolean,
          "requireSolarEnergy": boolean,
          "requireZeroWaste": boolean,
          "maxPriceRupees": number or null,
          "searchKeywords": short string of the most relevant place/category keywords, or ""
        }
    """

    private data class RawIntentJson(
        val prioritizeCarbon: Boolean? = null,
        val prioritizeAccessibility: Boolean? = null,
        val prioritizeSpeed: Boolean? = null,
        val prioritizeBudget: Boolean? = null,
        val requireWheelchairAccess: Boolean? = null,
        val requireSolarEnergy: Boolean? = null,
        val requireZeroWaste: Boolean? = null,
        val maxPriceRupees: Int? = null,
        val searchKeywords: String? = null
    )

    suspend fun parse(freeText: String, groqApiKey: String, geminiApiKey: String): TripIntent = withContext(Dispatchers.IO) {
        if (freeText.isBlank()) return@withContext TripIntent()

        if (groqApiKey.isNotEmpty() && groqApiKey != "DEMO_GROQ_KEY" && groqApiKey != "null") {
            try {
                return@withContext parseWithGroq(freeText, groqApiKey)
            } catch (_: Exception) {
                // Fall through to Gemini, then rules — never block the user on an LLM failure.
            }
        }

        if (geminiApiKey.isNotEmpty() && geminiApiKey != "DEMO_GEMINI_KEY" && geminiApiKey != "null") {
            try {
                return@withContext parseWithGemini(freeText, geminiApiKey)
            } catch (_: Exception) {
                // Fall through to rule-based parsing.
            }
        }
        parseWithRules(freeText)
    }

    private fun parseWithGroq(freeText: String, apiKey: String): TripIntent {
        val prompt = "Extract structured travel-planning constraints from this traveler request.\n$INTENT_SCHEMA\n\nTraveler request: \"${freeText.replace("\"", "'")}\""

        for (modelName in groqCandidateModels) {
            try {
                val messagesArray = JSONArray().apply {
                    put(JSONObject().apply {
                        put("role", "system")
                        put("content", "You are a structured data extraction engine. Reply with raw JSON only, never prose.")
                    })
                    put(JSONObject().apply {
                        put("role", "user")
                        put("content", prompt)
                    })
                }
                val requestJson = JSONObject().apply {
                    put("model", modelName)
                    put("messages", messagesArray)
                    put("temperature", 0.1)
                    put("max_tokens", 300)
                }
                val requestBody = requestJson.toString().toRequestBody("application/json".toMediaType())
                val request = Request.Builder()
                    .url("https://api.groq.com/openai/v1/chat/completions")
                    .addHeader("Authorization", "Bearer $apiKey")
                    .addHeader("Content-Type", "application/json")
                    .post(requestBody)
                    .build()

                httpClient.newCall(request).execute().use { response ->
                    val body = response.body?.string()
                    if (response.isSuccessful && body != null) {
                        val content = JSONObject(body).optJSONArray("choices")
                            ?.optJSONObject(0)?.optJSONObject("message")?.optString("content")
                        if (!content.isNullOrBlank()) {
                            val jsonText = content.trim().removePrefix("```json").removePrefix("```").removeSuffix("```").trim()
                            val parsed = Gson().fromJson(jsonText, RawIntentJson::class.java)
                            return TripIntent(
                                prioritizeCarbon = parsed.prioritizeCarbon ?: false,
                                prioritizeAccessibility = parsed.prioritizeAccessibility ?: false,
                                prioritizeSpeed = parsed.prioritizeSpeed ?: false,
                                prioritizeBudget = parsed.prioritizeBudget ?: false,
                                requireWheelchairAccess = parsed.requireWheelchairAccess ?: false,
                                requireSolarEnergy = parsed.requireSolarEnergy ?: false,
                                requireZeroWaste = parsed.requireZeroWaste ?: false,
                                maxPriceRupees = parsed.maxPriceRupees,
                                searchKeywords = parsed.searchKeywords ?: "",
                                parsedBy = "groq"
                            )
                        }
                    }
                }
            } catch (e: Exception) {
                // Try next candidate model
            }
        }
        throw IllegalStateException("All Groq candidate models failed")
    }

    private suspend fun parseWithGemini(freeText: String, apiKey: String): TripIntent {
        val model = GenerativeModel(modelName = "gemini-1.5-flash", apiKey = apiKey)
        val prompt = """
            Extract structured travel-planning constraints from this traveler request.
            Respond with ONLY a raw JSON object (no markdown fences, no commentary) matching exactly this shape:
            {
              "prioritizeCarbon": boolean,
              "prioritizeAccessibility": boolean,
              "prioritizeSpeed": boolean,
              "prioritizeBudget": boolean,
              "requireWheelchairAccess": boolean,
              "requireSolarEnergy": boolean,
              "requireZeroWaste": boolean,
              "maxPriceRupees": number or null,
              "searchKeywords": short string of the most relevant place/category keywords, or ""
            }

            Traveler request: "${freeText.replace("\"", "'")}"
        """.trimIndent()

        val response = model.generateContent(prompt)
        val rawText = response.text?.trim() ?: throw IllegalStateException("Empty Gemini response")
        val jsonText = rawText.removePrefix("```json").removePrefix("```").removeSuffix("```").trim()

        val parsed = Gson().fromJson(jsonText, RawIntentJson::class.java)
        return TripIntent(
            prioritizeCarbon = parsed.prioritizeCarbon ?: false,
            prioritizeAccessibility = parsed.prioritizeAccessibility ?: false,
            prioritizeSpeed = parsed.prioritizeSpeed ?: false,
            prioritizeBudget = parsed.prioritizeBudget ?: false,
            requireWheelchairAccess = parsed.requireWheelchairAccess ?: false,
            requireSolarEnergy = parsed.requireSolarEnergy ?: false,
            requireZeroWaste = parsed.requireZeroWaste ?: false,
            maxPriceRupees = parsed.maxPriceRupees,
            searchKeywords = parsed.searchKeywords ?: "",
            parsedBy = "gemini"
        )
    }

    /** Deterministic fallback — no network, no API key, always available. */
    private fun parseWithRules(freeText: String): TripIntent {
        val text = freeText.lowercase()

        val prioritizeCarbon = listOf("green", "eco", "carbon", "sustainable", "emission").any { text.contains(it) }
        val prioritizeAccessibility = listOf("accessible", "accessibility", "wheelchair", "disab").any { text.contains(it) }
        val prioritizeSpeed = listOf("fast", "quick", "urgent", "asap", "hurry").any { text.contains(it) }
        val prioritizeBudget = listOf("cheap", "budget", "affordable", "low cost", "inexpensive").any { text.contains(it) }
        val requireWheelchair = listOf("wheelchair", "step-free", "step free").any { text.contains(it) }
        val requireSolar = text.contains("solar")
        val requireZeroWaste = listOf("zero waste", "zero-waste", "no plastic", "plastic-free").any { text.contains(it) }

        val priceMatch = Regex("""(?:under|below|less than|max)?\s*(?:rs\.?|₹)\s*([\d,]+)""", RegexOption.IGNORE_CASE)
            .find(text)
            ?: Regex("""([\d,]+)\s*(?:rs\.?|rupees|₹)""", RegexOption.IGNORE_CASE).find(text)
        val maxPrice = priceMatch?.groupValues?.get(1)?.replace(",", "")?.toIntOrNull()

        val keywordStopWords = setOf(
            "i", "want", "a", "to", "the", "for", "with", "and", "trip", "hotel", "travel", "need", "looking",
            "cheap", "green", "eco", "wheelchair", "accessible", "fast", "under", "rs", "rupees"
        )
        val keywords = text.split(Regex("\\W+"))
            .filter { it.length > 2 && it !in keywordStopWords }
            .take(4)
            .joinToString(" ")

        return TripIntent(
            prioritizeCarbon = prioritizeCarbon,
            prioritizeAccessibility = prioritizeAccessibility,
            prioritizeSpeed = prioritizeSpeed,
            prioritizeBudget = prioritizeBudget,
            requireWheelchairAccess = requireWheelchair,
            requireSolarEnergy = requireSolar,
            requireZeroWaste = requireZeroWaste,
            maxPriceRupees = maxPrice,
            searchKeywords = keywords,
            parsedBy = "rules"
        )
    }
}
