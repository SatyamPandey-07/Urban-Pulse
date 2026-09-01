package com.urbanpulse.app.viewmodel

import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.urbanpulse.app.network.AirQualityResponse
import com.urbanpulse.app.network.AirQualityService
import com.urbanpulse.app.network.OpenMeteoService
import com.urbanpulse.app.network.WeatherResponse
import kotlinx.coroutines.launch
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

class DashboardViewModel : ViewModel() {

    private val _weatherData = MutableLiveData<WeatherResponse?>()
    val weatherData: LiveData<WeatherResponse?> = _weatherData

    private val _aqiData = MutableLiveData<AirQualityResponse?>()
    val aqiData: LiveData<AirQualityResponse?> = _aqiData

    private val _error = MutableLiveData<String?>()
    val error: LiveData<String?> = _error

    private val weatherService: OpenMeteoService by lazy {
        Retrofit.Builder()
            .baseUrl("https://api.open-meteo.com/")
            .addConverterFactory(GsonConverterFactory.create())
            .build()
            .create(OpenMeteoService::class.java)
    }

    private val aqiService: AirQualityService by lazy {
        Retrofit.Builder()
            .baseUrl("https://air-quality-api.open-meteo.com/")
            .addConverterFactory(GsonConverterFactory.create())
            .build()
            .create(AirQualityService::class.java)
    }

    fun fetchDashboardData(lat: Double = 19.0760, lon: Double = 72.8777) {
        // Only fetch if data is missing
        if (_weatherData.value != null && _aqiData.value != null) {
            return
        }

        viewModelScope.launch {
            try {
                val weather = weatherService.getWeather(lat, lon)
                _weatherData.value = weather

                val aqi = aqiService.getAirQuality(lat, lon)
                _aqiData.value = aqi
                
                _error.value = null
            } catch (e: Exception) {
                _error.value = e.message
                e.printStackTrace()
            }
        }
    }
    
    fun refresh(lat: Double, lon: Double) {
        _weatherData.value = null
        _aqiData.value = null
        fetchDashboardData(lat, lon)
    }
}
