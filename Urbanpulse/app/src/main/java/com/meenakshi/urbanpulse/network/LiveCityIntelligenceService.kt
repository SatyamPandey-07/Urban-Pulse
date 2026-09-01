package com.meenakshi.urbanpulse.network

import com.meenakshi.urbanpulse.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.IOException
import java.util.concurrent.TimeUnit
import java.net.URLEncoder

data class LivePoiResult(
    val name: String,
    val address: String,
    val distanceMeters: Double,
    val phone: String?,
    val lat: Double,
    val lon: Double,
    val category: String?
)

data class LiveTrafficData(
    val roadName: String,
    val currentSpeedKmh: Int,
    val freeFlowSpeedKmh: Int,
    val delaySeconds: Int,
    val confidence: Double
)

data class LiveWeatherAqiData(
    val temperatureC: Double,
    val humidityPercent: Int,
    val windSpeedKmh: Double,
    val pm25: Double,
    val pm10: Double,
    val usAqi: Int,
    val condition: String
)

object LiveCityIntelligenceService {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    suspend fun searchNearbyPoi(query: String, lat: Double, lon: Double, radiusMeters: Int = 12000): List<LivePoiResult> = withContext(Dispatchers.IO) {
        val apiKey = BuildConfig.TOMTOM_API_KEY
        val encodedQuery = URLEncoder.encode(query, "UTF-8")
        val url = "https://api.tomtom.com/search/2/poiSearch/$encodedQuery.json?lat=$lat&lon=$lon&radius=$radiusMeters&limit=8&key=$apiKey"

        val request = Request.Builder().url(url).get().build()
        try {
            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext emptyList()
                val body = response.body?.string() ?: return@withContext emptyList()
                val json = JSONObject(body)
                val resultsArray = json.optJSONArray("results") ?: return@withContext emptyList()

                val list = mutableListOf<LivePoiResult>()
                for (i in 0 until resultsArray.length()) {
                    val item = resultsArray.getJSONObject(i)
                    val poi = item.optJSONObject("poi")
                    val address = item.optJSONObject("address")
                    val position = item.optJSONObject("position")
                    val dist = item.optDouble("dist", 0.0)

                    val name = poi?.optString("name", "Medical Facility") ?: "Medical Facility"
                    val freeformAddress = address?.optString("freeformAddress", "") ?: ""
                    val phone = poi?.optString("phone", null)
                    val pLat = position?.optDouble("lat", lat) ?: lat
                    val pLon = position?.optDouble("lon", lon) ?: lon
                    val cat = poi?.optJSONArray("categories")?.optString(0, null)

                    list.add(
                        LivePoiResult(
                            name = name,
                            address = freeformAddress,
                            distanceMeters = dist,
                            phone = phone,
                            lat = pLat,
                            lon = pLon,
                            category = cat
                        )
                    )
                }
                list.sortedBy { it.distanceMeters }
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    suspend fun getLiveTraffic(lat: Double, lon: Double): LiveTrafficData? = withContext(Dispatchers.IO) {
        val apiKey = BuildConfig.TOMTOM_API_KEY
        val url = "https://api.tomtom.com/traffic/services/4/flowSegmentData/relative0/10/json?point=$lat,$lon&key=$apiKey"

        val request = Request.Builder().url(url).get().build()
        try {
            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext null
                val body = response.body?.string() ?: return@withContext null
                val json = JSONObject(body)
                val flow = json.optJSONObject("flowSegmentData") ?: return@withContext null

                val curSpeed = flow.optInt("currentSpeed", 35)
                val freeSpeed = flow.optInt("freeFlowSpeed", 50)
                val delay = flow.optInt("currentDelay", 0)
                val confidence = flow.optDouble("confidence", 0.9)
                val roadName = flow.optJSONArray("coordinates")?.optJSONObject(0)?.optString("roadName", "Current Transit Artery") ?: "Nearby Arterial Road"

                LiveTrafficData(
                    roadName = roadName,
                    currentSpeedKmh = curSpeed,
                    freeFlowSpeedKmh = freeSpeed,
                    delaySeconds = delay,
                    confidence = confidence
                )
            }
        } catch (e: Exception) {
            null
        }
    }

    suspend fun getLiveWeatherAndAqi(lat: Double, lon: Double): LiveWeatherAqiData? = withContext(Dispatchers.IO) {
        try {
            val weatherUrl = "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m"
            val aqiUrl = "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=$lat&longitude=$lon&current=pm2_5,pm10,us_aqi"

            var temp = 28.0
            var humidity = 65
            var wind = 12.0
            var code = 0

            val weatherReq = Request.Builder().url(weatherUrl).get().build()
            httpClient.newCall(weatherReq).execute().use { resp ->
                if (resp.isSuccessful) {
                    val body = resp.body?.string()
                    if (body != null) {
                        val current = JSONObject(body).optJSONObject("current")
                        if (current != null) {
                            temp = current.optDouble("temperature_2m", 28.0)
                            humidity = current.optInt("relative_humidity_2m", 65)
                            wind = current.optDouble("wind_speed_10m", 12.0)
                            code = current.optInt("weather_code", 0)
                        }
                    }
                }
            }

            var pm25 = 38.0
            var pm10 = 65.0
            var aqi = 110

            val aqiReq = Request.Builder().url(aqiUrl).get().build()
            httpClient.newCall(aqiReq).execute().use { resp ->
                if (resp.isSuccessful) {
                    val body = resp.body?.string()
                    if (body != null) {
                        val current = JSONObject(body).optJSONObject("current")
                        if (current != null) {
                            pm25 = current.optDouble("pm2_5", 38.0)
                            pm10 = current.optDouble("pm10", 65.0)
                            aqi = current.optInt("us_aqi", 110)
                        }
                    }
                }
            }

            val condition = when (code) {
                0 -> "Clear Sky"
                1, 2, 3 -> "Partly Cloudy"
                45, 48 -> "Foggy / Hazy"
                51, 53, 55, 61, 63 -> "Showers"
                else -> "Cloudy"
            }

            LiveWeatherAqiData(
                temperatureC = temp,
                humidityPercent = humidity,
                windSpeedKmh = wind,
                pm25 = pm25,
                pm10 = pm10,
                usAqi = aqi,
                condition = condition
            )
        } catch (e: Exception) {
            null
        }
    }
}
