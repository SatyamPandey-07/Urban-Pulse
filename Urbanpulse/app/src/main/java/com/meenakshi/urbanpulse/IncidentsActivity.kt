package com.meenakshi.urbanpulse

import android.Manifest
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Bundle
import android.text.format.DateUtils
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import coil.load
import com.google.android.material.appbar.MaterialToolbar
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

class IncidentsActivity : AppCompatActivity() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var progressBar: ProgressBar

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_incidents)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        toolbar.setNavigationOnClickListener { finish() }

        recyclerView = findViewById(R.id.recyclerView)
        progressBar = findViewById(R.id.progressBar)
        recyclerView.layoutManager = LinearLayoutManager(this)

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            fetchIncidents()
        } else {
            Toast.makeText(this, "Location permission needed to view incidents", Toast.LENGTH_SHORT).show()
        }
    }

    private fun fetchIncidents() {
        progressBar.visibility = View.VISIBLE
        
        val locationManager = getSystemService(LOCATION_SERVICE) as LocationManager
        val userLocation = if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
             locationManager.getLastKnownLocation(LocationManager.GPS_PROVIDER)
        } else null

        if (userLocation == null) {
            Toast.makeText(this, "Could not get current location", Toast.LENGTH_SHORT).show()
            progressBar.visibility = View.GONE
            return
        }
        
        lifecycleScope.launch {
            try {
                val db = FirebaseFirestore.getInstance()
                val snapshot = db.collection("incidents")
                    .orderBy("timestamp", Query.Direction.DESCENDING)
                    .limit(50) // Get latest 50
                    .get()
                    .await()
                
                val incidents = snapshot.toObjects(Incident::class.java)
                
                // Calculate distance and sort
                val sortedIncidents = incidents.sortedBy { incident ->
                    val results = FloatArray(1)
                    Location.distanceBetween(
                        userLocation.latitude, userLocation.longitude,
                        incident.location?.latitude ?: 0.0,
                        incident.location?.longitude ?: 0.0,
                        results
                    )
                    results[0]
                }
                
                recyclerView.adapter = IncidentsAdapter(sortedIncidents, userLocation)
                progressBar.visibility = View.GONE
                
            } catch (e: Exception) {
                progressBar.visibility = View.GONE
                Toast.makeText(this@IncidentsActivity, "Failed to load incidents: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }
}

class IncidentsAdapter(
    private val incidents: List<Incident>,
    private val userLocation: Location
) : RecyclerView.Adapter<IncidentsAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val image: ImageView = view.findViewById(R.id.imgIncident)
        val type: TextView = view.findViewById(R.id.tvIncidentType)
        val distance: TextView = view.findViewById(R.id.tvDistance)
        val description: TextView = view.findViewById(R.id.tvDescription)
        val timestamp: TextView = view.findViewById(R.id.tvTimestamp)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_incident, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val incident = incidents[position]
        
        holder.image.load(incident.imageUrl)
        holder.type.text = incident.type
        holder.description.text = incident.description
        
        incident.timestamp?.let {
            holder.timestamp.text = DateUtils.getRelativeTimeSpanString(it.time, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS)
        }
        
        val results = FloatArray(1)
        Location.distanceBetween(
            userLocation.latitude, userLocation.longitude,
            incident.location?.latitude ?: 0.0,
            incident.location?.longitude ?: 0.0,
            results
        )
        holder.distance.text = "%.1f km away".format(results[0] / 1000)
    }

    override fun getItemCount() = incidents.size
}
