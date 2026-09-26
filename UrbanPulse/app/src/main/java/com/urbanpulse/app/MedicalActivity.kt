package com.urbanpulse.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.button.MaterialButton
import com.tomtom.sdk.location.GeoPoint
import com.tomtom.sdk.search.Search
import com.tomtom.sdk.search.SearchCallback
import com.tomtom.sdk.search.common.error.SearchFailure
import com.tomtom.sdk.search.SearchOptions
import com.tomtom.sdk.search.SearchResponse
import com.tomtom.sdk.search.online.OnlineSearch

data class MedicalFacility(
    val name: String,
    val address: String,
    val phone: String,
    val latitude: Double,
    val longitude: Double
)

class MedicalActivity : AppCompatActivity() {

    private lateinit var recyclerView: RecyclerView
    private var searchApi: Search? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_medical)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        toolbar.setNavigationOnClickListener { finish() }

        recyclerView = findViewById(R.id.recyclerView)
        recyclerView.layoutManager = LinearLayoutManager(this)

        try {
            searchApi = OnlineSearch.create(this, BuildConfig.TOMTOM_API_KEY)
        } catch (e: Exception) {
            // SDK fallback
        }

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        ) {
            fetchMedicalPlaces()
        } else {
            // Load with default / network location
            fetchMedicalPlaces()
        }
    }

    private fun fetchMedicalPlaces() {
        val locMgr = UserLocationManager.getInstance(this)
        val lat = locMgr.currentLatitude
        val lon = locMgr.currentLongitude
        val userLoc = Location("UserLoc").apply {
            latitude = lat
            longitude = lon
        }

        lifecycleScope.launch {
            val poiList = withContext(Dispatchers.IO) {
                LiveCityIntelligenceService.searchNearbyPoi("hospital", lat, lon)
            }

            if (poiList.isNotEmpty()) {
                val places = poiList.map {
                    MedicalFacility(
                        name = it.name,
                        address = it.address,
                        phone = it.phone ?: "+91 22 4365 4365",
                        latitude = it.lat,
                        longitude = it.lon
                    )
                }
                recyclerView.adapter = MedicalAdapter(places, userLoc)
            } else {
                loadEmergencyMedicalFallback(userLoc)
            }
        }
    }

    private fun loadEmergencyMedicalFallback(userLoc: Location) {
        val verifiedHospitals = listOf(
            MedicalFacility("Fortis Hospital Mulund (24/7 Trauma)", "Mulund Goregaon Link Rd, Mumbai", "+91 22 4365 4365", 19.1728, 72.9564),
            MedicalFacility("Jupiter Hospital (Step-Free Critical Care)", "Eastern Express Highway, Thane West", "+91 22 2172 5555", 19.2050, 72.9734),
            MedicalFacility("Lilavati Hospital & Research Centre", "A-791, Bandra Reclamation, Bandra West", "+91 22 2675 1000", 19.0514, 72.8295),
            MedicalFacility("KEM Hospital & Medical College", "Acharya Donde Marg, Parel, Mumbai", "+91 22 2410 7000", 19.0024, 72.8427),
            MedicalFacility("Hiranandani Hospital", "Hillside Avenue, Hiranandani Gardens, Powai", "+91 22 2576 3300", 19.1197, 72.9126),
            MedicalFacility("Apex Super Speciality Hospital", "Borivali West, Mumbai", "+91 22 6156 5656", 19.2307, 72.8567)
        )
        // Sort by distance to user
        val sorted = verifiedHospitals.sortedBy { h ->
            val results = FloatArray(1)
            Location.distanceBetween(userLoc.latitude, userLoc.longitude, h.latitude, h.longitude, results)
            results[0]
        }
        recyclerView.adapter = MedicalAdapter(sorted, userLoc)
    }
}

class MedicalAdapter(
    private val places: List<MedicalFacility>,
    private val userLocation: Location
) : RecyclerView.Adapter<MedicalAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val name: TextView = view.findViewById(R.id.tvPlaceName)
        val address: TextView = view.findViewById(R.id.tvAddress)
        val distance: TextView = view.findViewById(R.id.tvDistance)
        val btnCall: MaterialButton = view.findViewById(R.id.btnCall)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_medical_place, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val place = places[position]
        holder.name.text = place.name
        holder.address.text = place.address

        val results = FloatArray(1)
        Location.distanceBetween(
            userLocation.latitude, userLocation.longitude,
            place.latitude, place.longitude,
            results
        )
        val distKm = results[0] / 1000.0
        holder.distance.text = String.format(java.util.Locale.US, "%.1f km away", distKm)

        holder.btnCall.visibility = View.VISIBLE
        holder.btnCall.text = "Call ${if (place.phone.startsWith("+")) "Hospital" else "108"}"
        holder.btnCall.setOnClickListener { v ->
            val dialIntent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:${place.phone}"))
            v.context.startActivity(dialIntent)
        }
    }

    override fun getItemCount() = places.size
}
