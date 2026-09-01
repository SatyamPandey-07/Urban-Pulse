package com.meenakshi.urbanpulse

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
import com.tomtom.sdk.search.model.result.SearchResult
import com.tomtom.sdk.search.online.OnlineSearch

class MedicalActivity : AppCompatActivity() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var searchApi: Search

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_medical)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        toolbar.setNavigationOnClickListener { finish() }

        recyclerView = findViewById(R.id.recyclerView)
        recyclerView.layoutManager = LinearLayoutManager(this)

        searchApi = OnlineSearch.create(this, BuildConfig.TOMTOM_API_KEY)

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            fetchMedicalPlaces()
        } else {
            Toast.makeText(this, "Location permission needed", Toast.LENGTH_SHORT).show()
        }
    }

    private fun fetchMedicalPlaces() {
        val locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        val location = if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
             locationManager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER) 
             ?: locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
        } else null

        location?.let { loc ->
            val options = SearchOptions(
                query = "hospital",
                geoBias = GeoPoint(loc.latitude, loc.longitude),
                limit = 10
            )
            
            searchApi.search(options, object : SearchCallback {
                override fun onSuccess(result: SearchResponse) {
                    val places = result.results
                    runOnUiThread {
                        recyclerView.adapter = MedicalAdapter(places, loc)
                    }
                }

                override fun onFailure(failure: SearchFailure) {
                    runOnUiThread {
                        Toast.makeText(this@MedicalActivity, "Search failed: ${failure.message}", Toast.LENGTH_SHORT).show()
                    }
                }
            })
        }
    }
}

class MedicalAdapter(
    private val places: List<SearchResult>,
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
        holder.name.text = place.place.name ?: "Medical Center"
        holder.address.text = place.place.address?.freeformAddress ?: ""
        
        // Calculate distance
        val results = FloatArray(1)
        Location.distanceBetween(
            userLocation.latitude, userLocation.longitude,
            place.place.coordinate.latitude, place.place.coordinate.longitude,
            results
        )
        holder.distance.text = "%.1f km".format(results[0] / 1000)

        holder.btnCall.visibility = View.GONE
    }

    override fun getItemCount() = places.size
}
