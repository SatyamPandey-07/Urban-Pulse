package com.meenakshi.urbanpulse

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.chip.Chip
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.tomtom.sdk.location.GeoPoint
import com.tomtom.sdk.map.display.MapOptions
import com.tomtom.sdk.map.display.TomTomMap
import com.tomtom.sdk.map.display.camera.CameraOptions
import com.tomtom.sdk.map.display.common.screen.Padding
import com.tomtom.sdk.map.display.ui.MapFragment
import com.tomtom.sdk.search.Search
import com.tomtom.sdk.search.SearchCallback
import com.tomtom.sdk.search.SearchOptions
import com.tomtom.sdk.search.SearchResponse
import com.tomtom.sdk.search.common.error.SearchFailure
import com.tomtom.sdk.search.online.OnlineSearch

class LiveMapFragment : Fragment() {

    private var tomtomMap: TomTomMap? = null
    private var searchApi: Search? = null
    private lateinit var etMapSearch: EditText
    private lateinit var btnClearSearch: ImageButton
    private lateinit var rvSearchResults: RecyclerView
    private lateinit var searchAdapter: SearchAdapter
    private lateinit var tvLiveStatusTitle: TextView
    private lateinit var tvLiveStatusSubtitle: TextView

    private val defaultCityPoint = GeoPoint(19.0760, 72.8777) // Mumbai default coordinates

    private val locationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        if (permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
            permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true) {
            moveToCurrentLocation()
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_live_map, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        etMapSearch = view.findViewById(R.id.etMapSearch)
        btnClearSearch = view.findViewById(R.id.btnClearSearch)
        rvSearchResults = view.findViewById(R.id.rvSearchResults)
        tvLiveStatusTitle = view.findViewById(R.id.tvLiveStatusTitle)
        tvLiveStatusSubtitle = view.findViewById(R.id.tvLiveStatusSubtitle)

        // Initialize Map
        val mapOptions = MapOptions(mapKey = BuildConfig.TOMTOM_API_KEY)
        val mapFragment = MapFragment.newInstance(mapOptions)
        childFragmentManager.beginTransaction()
            .replace(R.id.map_container, mapFragment)
            .commit()

        mapFragment.getMapAsync { map ->
            tomtomMap = map
            val cameraOptions = CameraOptions(
                position = defaultCityPoint,
                zoom = 12.0
            )
            tomtomMap?.moveCamera(cameraOptions)
            checkLocationAndCenter()
        }

        // Initialize Search API
        context?.let { ctx ->
            searchApi = OnlineSearch.create(ctx, BuildConfig.TOMTOM_API_KEY)
        }

        setupSearch()
        setupChips(view)
        setupFabs(view)
    }

    private fun setupSearch() {
        rvSearchResults.layoutManager = LinearLayoutManager(context)
        searchAdapter = SearchAdapter(emptyList()) { result ->
            rvSearchResults.visibility = View.GONE
            etMapSearch.setText(result.place.name ?: "")
            val coordinate = result.place.coordinate
            val targetPoint = GeoPoint(coordinate.latitude, coordinate.longitude)
            tomtomMap?.moveCamera(CameraOptions(position = targetPoint, zoom = 15.0))
            tvLiveStatusTitle.text = "📍 ${result.place.name ?: "Selected Location"}"
            tvLiveStatusSubtitle.text = result.place.address?.freeformAddress ?: "Coordinates: ${coordinate.latitude}, ${coordinate.longitude}"
        }
        rvSearchResults.adapter = searchAdapter

        etMapSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                btnClearSearch.visibility = if (!s.isNullOrEmpty()) View.VISIBLE else View.GONE
            }
            override fun afterTextChanged(s: Editable?) {}
        })

        btnClearSearch.setOnClickListener {
            etMapSearch.text.clear()
            rvSearchResults.visibility = View.GONE
        }

        etMapSearch.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                val query = etMapSearch.text.toString().trim()
                if (query.isNotEmpty()) performSearch(query)
                true
            } else false
        }
    }

    private fun performSearch(query: String) {
        val search = searchApi ?: return
        val currentPoint = getCurrentGeoPoint() ?: defaultCityPoint
        val options = SearchOptions(
            query = query,
            geoBias = currentPoint,
            limit = 5
        )

        search.search(options, object : SearchCallback {
            override fun onSuccess(result: SearchResponse) {
                activity?.runOnUiThread {
                    if (result.results.isNotEmpty()) {
                        searchAdapter.updateResults(result.results)
                        rvSearchResults.visibility = View.VISIBLE
                    } else {
                        Toast.makeText(context, "No places found for '$query'", Toast.LENGTH_SHORT).show()
                    }
                }
            }

            override fun onFailure(failure: SearchFailure) {
                activity?.runOnUiThread {
                    Toast.makeText(context, "Search unavailable: ${failure.message}", Toast.LENGTH_SHORT).show()
                }
            }
        })
    }

    private fun setupChips(view: View) {
        view.findViewById<Chip>(R.id.chipHospitals).setOnClickListener {
            val intent = Intent(activity, MedicalActivity::class.java)
            startActivity(intent)
        }

        view.findViewById<Chip>(R.id.chipTraffic).setOnClickListener {
            tvLiveStatusTitle.text = "🚦 Live Traffic Active"
            tvLiveStatusSubtitle.text = "Real-time congestion tracking enabled • Smooth flow"
            Toast.makeText(context, "Live Traffic Layer Enabled", Toast.LENGTH_SHORT).show()
        }

        view.findViewById<Chip>(R.id.chipIncidents).setOnClickListener {
            val intent = Intent(activity, IncidentsActivity::class.java)
            startActivity(intent)
        }

        view.findViewById<Chip>(R.id.chipEco).setOnClickListener {
            tvLiveStatusTitle.text = "🌿 Eco Route Mode"
            tvLiveStatusSubtitle.text = "Optimized for lowest carbon emissions and smooth cruising"
            Toast.makeText(context, "Eco Routing Enabled: -18% CO2 estimate", Toast.LENGTH_SHORT).show()
        }

        view.findViewById<Chip>(R.id.chipEV).setOnClickListener {
            performSearch("EV charging station")
        }
    }

    private fun setupFabs(view: View) {
        view.findViewById<FloatingActionButton>(R.id.fabMyLocation).setOnClickListener {
            checkLocationAndCenter()
        }

        view.findViewById<FloatingActionButton>(R.id.fabTrafficToggle).setOnClickListener {
            Toast.makeText(context, "Live Traffic overlay updated", Toast.LENGTH_SHORT).show()
        }

        view.findViewById<FloatingActionButton>(R.id.fabReportHazard).setOnClickListener {
            startActivity(Intent(activity, ReportIncidentActivity::class.java))
        }

        view.findViewById<View>(R.id.btnAskYatri).setOnClickListener {
            (activity as? MainActivity)?.switchToTab(3)
        }
    }

    private fun checkLocationAndCenter() {
        val ctx = context ?: return
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            moveToCurrentLocation()
        } else {
            locationPermissionLauncher.launch(arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ))
        }
    }

    private fun moveToCurrentLocation() {
        val point = getCurrentGeoPoint() ?: defaultCityPoint
        tomtomMap?.moveCamera(CameraOptions(position = point, zoom = 14.5))
        Toast.makeText(context, "Centered on your location", Toast.LENGTH_SHORT).show()
    }

    private fun getCurrentGeoPoint(): GeoPoint? {
        val ctx = context ?: return null
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return null
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            val loc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                ?: lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            if (loc != null) return GeoPoint(loc.latitude, loc.longitude)
        }
        return null
    }
}
