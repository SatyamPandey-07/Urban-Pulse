package com.urbanpulse.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Address
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Looper
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

class UserLocationManager private constructor(private val appContext: Context) {

    companion object {
        @Volatile
        private var instance: UserLocationManager? = null

        fun getInstance(context: Context): UserLocationManager =
            instance ?: synchronized(this) {
                instance ?: UserLocationManager(context.applicationContext).also { instance = it }
            }
    }

    private val fusedClient: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(appContext)

    var currentLatitude: Double = 19.0760
        private set
    var currentLongitude: Double = 72.8777
        private set
    var currentCityName: String = "Mumbai"
        private set
    var currentSubArea: String = "Maharashtra, India"
        private set
    var isGpsActive: Boolean = false
        private set

    private val listeners = mutableListOf<(lat: Double, lon: Double, city: String, region: String) -> Unit>()

    init {
        loadLastSavedLocation()
        refreshLocation()
    }

    fun addLocationListener(listener: (lat: Double, lon: Double, city: String, region: String) -> Unit) {
        listeners.add(listener)
        // Immediately notify with latest known
        listener(currentLatitude, currentLongitude, currentCityName, currentSubArea)
    }

    fun removeLocationListener(listener: (lat: Double, lon: Double, city: String, region: String) -> Unit) {
        listeners.remove(listener)
    }

    private fun loadLastSavedLocation() {
        val prefs = appContext.getSharedPreferences("urbanpulse_location", Context.MODE_PRIVATE)
        currentLatitude = prefs.getFloat("last_lat", 19.0760f).toDouble()
        currentLongitude = prefs.getFloat("last_lon", 72.8777f).toDouble()
        currentCityName = prefs.getString("last_city", "Mumbai") ?: "Mumbai"
        currentSubArea = prefs.getString("last_subarea", "Maharashtra, India") ?: "Maharashtra, India"
    }

    private fun saveLocation(lat: Double, lon: Double, city: String, subArea: String) {
        val prefs = appContext.getSharedPreferences("urbanpulse_location", Context.MODE_PRIVATE)
        prefs.edit()
            .putFloat("last_lat", lat.toFloat())
            .putFloat("last_lon", lon.toFloat())
            .putString("last_city", city)
            .putString("last_subarea", subArea)
            .apply()
    }

    @SuppressLint("MissingPermission")
    fun refreshLocation() {
        if (!hasLocationPermission()) return

        try {
            fusedClient.lastLocation.addOnSuccessListener { loc: Location? ->
                if (loc != null) {
                    updateLocation(loc.latitude, loc.longitude)
                } else {
                    val locMgr = appContext.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                    val lastKnown = locMgr?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                        ?: locMgr?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                    if (lastKnown != null) {
                        updateLocation(lastKnown.latitude, lastKnown.longitude)
                    }
                }
            }

            // Also request a single update
            val req = LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY, 30000)
                .setMinUpdateIntervalMillis(10000)
                .setMaxUpdates(1)
                .build()

            fusedClient.requestLocationUpdates(req, object : LocationCallback() {
                override fun onLocationResult(result: LocationResult) {
                    val loc = result.lastLocation ?: return
                    updateLocation(loc.latitude, loc.longitude)
                }
            }, Looper.getMainLooper())

        } catch (e: Exception) {
            // Permission or hardware exception
        }
    }

    fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                appContext,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
    }

    fun updateLocation(lat: Double, lon: Double) {
        currentLatitude = lat
        currentLongitude = lon
        isGpsActive = true

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val geocoder = Geocoder(appContext, Locale.getDefault())
                @Suppress("DEPRECATION")
                val addresses: List<Address>? = geocoder.getFromLocation(lat, lon, 1)
                if (!addresses.isNullOrEmpty()) {
                    val addr = addresses[0]
                    val city = addr.locality ?: addr.subAdminArea ?: addr.adminArea ?: "Current Location"
                    val sub = listOfNotNull(addr.subLocality, addr.adminArea, addr.countryName).joinToString(", ")
                    currentCityName = city
                    currentSubArea = if (sub.isNotBlank()) sub else "India"
                    saveLocation(lat, lon, currentCityName, currentSubArea)
                }
            } catch (e: Exception) {
                // Fallback to coordinates
            }

            withContext(Dispatchers.Main) {
                listeners.forEach { it(currentLatitude, currentLongitude, currentCityName, currentSubArea) }
            }
        }
    }

    fun calculateDistanceKm(targetLat: Double, targetLon: Double): Double {
        val results = FloatArray(1)
        Location.distanceBetween(currentLatitude, currentLongitude, targetLat, targetLon, results)
        return results[0] / 1000.0
    }
}