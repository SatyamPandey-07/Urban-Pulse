package com.urbanpulse.app.network

import retrofit2.http.GET
import retrofit2.http.Query

interface AirQualityService {
    @GET("v1/air-quality")
    suspend fun getAirQuality(
        @Query("latitude") lat: Double,
        @Query("longitude") lon: Double,
        @Query("current") current: String = "us_aqi",
        @Query("hourly") hourly: String = "us_aqi",
        @Query("past_days") pastDays: Int = 7,
        @Query("timezone") timezone: String = "auto"
    ): AirQualityResponse
}

data class AirQualityResponse(
    val current: CurrentAqi,
    val hourly: HourlyAqi
)

data class CurrentAqi(
    val us_aqi: Int
)

data class HourlyAqi(
    val time: List<String>,
    val us_aqi: List<Int?>
)