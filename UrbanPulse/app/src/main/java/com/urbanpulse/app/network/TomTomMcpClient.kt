package com.urbanpulse.app.network

import com.urbanpulse.app.BuildConfig
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit

object TomTomMcpClient {

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val JSON = "application/json; charset=utf-8".toMediaType()

    fun callTool(toolName: String, arguments: Map<String, Any?>): String {
        val apiKey = BuildConfig.TOMTOM_API_KEY
        val url = "https://mcp.tomtom.com/maps"

        val jsonBody = JSONObject().apply {
            put("jsonrpc", "2.0")
            put("method", "tools/call")
            put("id", System.currentTimeMillis())
            put("params", JSONObject().apply {
                put("name", toolName)
                put("arguments", JSONObject(arguments))
            })
        }

        val body = jsonBody.toString().toRequestBody(JSON)
        val request = Request.Builder()
            .url(url)
            .addHeader("tomtom-api-key", apiKey)
            .addHeader("Accept", "application/json") // Using simpler accept header for JSON response
            .post(body)
            .build()

        try {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    return "Error: MCP Server returned code ${response.code}"
                }

                val responseBody = response.body?.string() ?: return "Error: Empty response"
                
                // Parse the JSON-RPC response
                val jsonResponse = JSONObject(responseBody)
                if (jsonResponse.has("error")) {
                    val error = jsonResponse.getJSONObject("error")
                    return "MCP Error: ${error.optString("message", "Unknown error")}"
                }

                // The result is usually inside "result" -> "content" -> list of objects
                // We'll return the raw result part for the LLM to interpret, or simplify it
                if (jsonResponse.has("result")) {
                    val result = jsonResponse.getJSONObject("result")
                    return result.toString()
                }

                return responseBody
            }
        } catch (e: IOException) {
            return "Network Error: ${e.message}"
        } catch (e: Exception) {
            return "Error calling MCP: ${e.message}"
        }
    }
}
