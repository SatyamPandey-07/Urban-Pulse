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

object GroqApiClient {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .build()

    // Active high-performance models available on user's Groq account
    private val candidateModels = listOf(
        "openai/gpt-oss-120b",
        "groq/compound",
        "openai/gpt-oss-20b",
        "groq/compound-mini"
    )

    suspend fun queryGroq(
        userPrompt: String,
        systemPrompt: String = "You are Yatri AI, an expert sustainable travel & smart mobility assistant for UrbanPulse. When asked general questions, math, or travel questions, answer naturally, accurately, and concisely."
    ): String? = withContext(Dispatchers.IO) {
        val apiKey = BuildConfig.GROQ_API_KEY
        if (apiKey.isBlank() || apiKey == "DEMO_GROQ_KEY") return@withContext null

        for (modelName in candidateModels) {
            try {
                val messagesArray = JSONArray().apply {
                    put(JSONObject().apply {
                        put("role", "system")
                        put("content", systemPrompt)
                    })
                    put(JSONObject().apply {
                        put("role", "user")
                        put("content", userPrompt)
                    })
                }

                val requestJson = JSONObject().apply {
                    put("model", modelName)
                    put("messages", messagesArray)
                    put("temperature", 0.4)
                    put("max_tokens", 800)
                }

                val requestBody = requestJson.toString().toRequestBody("application/json".toMediaType())
                val request = Request.Builder()
                    .url("https://api.groq.com/openai/v1/chat/completions")
                    .addHeader("Authorization", "Bearer $apiKey")
                    .addHeader("Content-Type", "application/json")
                    .post(requestBody)
                    .build()

                val response = httpClient.newCall(request).execute()
                val body = response.body?.string()
                if (response.isSuccessful && body != null) {
                    val json = JSONObject(body)
                    val choices = json.optJSONArray("choices")
                    if (choices != null && choices.length() > 0) {
                        val message = choices.getJSONObject(0).optJSONObject("message")
                        val content = message?.optString("content")
                        if (!content.isNullOrBlank()) {
                            return@withContext content
                        }
                    }
                }
            } catch (e: Exception) {
                // Try next candidate model
            }
        }
        null
    }
}
