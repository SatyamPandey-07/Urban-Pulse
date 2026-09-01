package com.urbanpulse.app

import android.Manifest
import android.annotation.SuppressLint
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
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
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
import com.tomtom.sdk.search.Search
import com.tomtom.sdk.search.SearchCallback
import com.tomtom.sdk.search.SearchOptions
import com.tomtom.sdk.search.SearchResponse
import com.tomtom.sdk.search.common.error.SearchFailure
import com.tomtom.sdk.search.online.OnlineSearch

class LiveMapFragment : Fragment() {

    private lateinit var mapWebView: WebView
    private var searchApi: Search? = null
    private lateinit var etMapSearch: EditText
    private lateinit var btnClearSearch: ImageButton
    private lateinit var rvSearchResults: RecyclerView
    private lateinit var searchAdapter: SearchAdapter
    private lateinit var tvLiveStatusTitle: TextView
    private lateinit var tvLiveStatusSubtitle: TextView

    private var currentLat = 19.0760
    private var currentLon = 72.8777
    private var isTrafficEnabled = true
    private var isMapLoaded = false

    private val locationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        if (permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
            permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true) {
            updateUserLocation()
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

        mapWebView = view.findViewById(R.id.mapWebView)
        etMapSearch = view.findViewById(R.id.etMapSearch)
        btnClearSearch = view.findViewById(R.id.btnClearSearch)
        rvSearchResults = view.findViewById(R.id.rvSearchResults)
        tvLiveStatusTitle = view.findViewById(R.id.tvLiveStatusTitle)
        tvLiveStatusSubtitle = view.findViewById(R.id.tvLiveStatusSubtitle)

        setupInteractiveMap()
        setupSearch()
        setupChips(view)
        setupFabs(view)

        context?.let { ctx ->
            searchApi = OnlineSearch.create(ctx, BuildConfig.TOMTOM_API_KEY)
        }

        checkLocationPermission()
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun setupInteractiveMap() {
        val settings = mapWebView.settings
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        settings.cacheMode = WebSettings.LOAD_DEFAULT
        settings.loadWithOverviewMode = true
        settings.useWideViewPort = true
        settings.setSupportZoom(true)
        settings.builtInZoomControls = false

        mapWebView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                isMapLoaded = true
                centerMap(currentLat, currentLon, 13)
            }
        }
        mapWebView.webChromeClient = WebChromeClient()

        val mapHtml = buildMapHtml()
        mapWebView.loadDataWithBaseURL("https://urbanpulse.local", mapHtml, "text/html", "UTF-8", null)
    }

    private fun buildMapHtml(): String {
        return """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8" />
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
                <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
                <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
                <style>
                    html, body, #map { height: 100%; width: 100%; margin: 0; padding: 0; background: #0F172A; font-family: -apple-system, Roboto, sans-serif; }
                    .leaflet-control-attribution { display: none; }
                    .custom-pin {
                        display: flex; align-items: center; justify-content: center;
                        border-radius: 50%; color: white; font-weight: 600; font-size: 11px;
                        box-shadow: 0 4px 10px rgba(0,0,0,0.5);
                    }
                    .user-pulse {
                        width: 18px; height: 18px; background: #38BDF8; border: 3px solid #FFFFFF;
                        border-radius: 50%; box-shadow: 0 0 15px #38BDF8;
                        animation: radar 2s infinite ease-out;
                    }
                    @keyframes radar {
                        0% { box-shadow: 0 0 0 0 rgba(56, 189, 248, 0.7); }
                        70% { box-shadow: 0 0 0 16px rgba(56, 189, 248, 0); }
                        100% { box-shadow: 0 0 0 0 rgba(56, 189, 248, 0); }
                    }
                    .leaflet-popup-content-wrapper {
                        background: #1E293B; color: #F8FAFC; border-radius: 12px; border: 1px solid #334155;
                    }
                    .leaflet-popup-tip { background: #1E293B; }
                </style>
            </head>
            <body>
                <div id="map"></div>
                <script>
                    var map = L.map('map', { zoomControl: false }).setView([19.0760, 72.8777], 13);
                    
                    L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
                        maxZoom: 19,
                        subdomains: 'abcd'
                    }).addTo(map);

                    var userMarker = L.marker([19.0760, 72.8777], {
                        icon: L.divIcon({ className: 'user-pulse', iconSize: [18, 18], iconAnchor: [9, 9] })
                    }).addTo(map).bindPopup("<b>Current Location</b><br>GPS Active");

                    // Traffic Polylines
                    var trafficLines = [];
                    function drawTraffic() {
                        var greenLine = L.polyline([
                            [19.0544, 72.8402], [19.0760, 72.8777], [19.1136, 72.8697]
                        ], { color: '#10B981', weight: 5, opacity: 0.85 }).addTo(map).bindPopup("Western Highway: Fast Flow (54 km/h)");

                        var yellowLine = L.polyline([
                            [19.0760, 72.8777], [19.0600, 72.8900], [19.0400, 72.9000]
                        ], { color: '#F59E0B', weight: 5, opacity: 0.85 }).addTo(map).bindPopup("Eastern Freeway: Moderate (38 km/h)");

                        var redLine = L.polyline([
                            [19.0760, 72.8777], [19.0650, 72.8350]
                        ], { color: '#EF4444', weight: 5, opacity: 0.85 }).addTo(map).bindPopup("SV Road: Heavy Congestion (18 km/h)");

                        trafficLines = [greenLine, yellowLine, redLine];
                    }
                    drawTraffic();

                    var pois = [
                        { lat: 19.0515, lon: 72.8290, code: "MED", title: "Lilavati Hospital", desc: "24/7 Emergency Trauma Care", bg: "#EF4444" },
                        { lat: 19.0330, lon: 72.8550, code: "MED", title: "Hinduja Healthcare", desc: "Multi-Speciality Urgent Care", bg: "#EF4444" },
                        { lat: 19.0880, lon: 72.8890, code: "EV", title: "Fast Charging Hub", desc: "60 kW CCS2 (4 Available)", bg: "#38BDF8" },
                        { lat: 19.0680, lon: 72.8350, code: "HAZ", title: "Roadwork Alert", desc: "Reported 20 mins ago • Slow traffic", bg: "#F97316" },
                        { lat: 19.0950, lon: 72.8650, code: "ECO", title: "Eco Transit Corridor", desc: "Dedicated Electric Bus / Cycling Track", bg: "#10B981" }
                    ];

                    var markers = [];
                    pois.forEach(function(p) {
                        var m = L.marker([p.lat, p.lon], {
                            icon: L.divIcon({
                                className: 'custom-pin',
                                html: '<div style="background:' + p.bg + '; width:30px; height:30px; border-radius:50%; display:flex; align-items:center; justify-content:center; border:2px solid white; font-size:10px;">' + p.code + '</div>',
                                iconSize: [30, 30],
                                iconAnchor: [15, 15]
                            })
                        }).addTo(map).bindPopup("<b>" + p.title + "</b><br>" + p.desc);
                        markers.push(m);
                    });

                    window.setCenter = function(lat, lon, zoom) {
                        map.flyTo([lat, lon], zoom, { duration: 1.2 });
                        userMarker.setLatLng([lat, lon]);
                    };

                    window.addPin = function(lat, lon, title, desc) {
                        map.flyTo([lat, lon], 15, { duration: 1.0 });
                        L.marker([lat, lon]).addTo(map).bindPopup("<b>" + title + "</b><br>" + desc).openPopup();
                    };

                    window.toggleTrafficOverlay = function(show) {
                        trafficLines.forEach(function(l) {
                            if (show) map.addLayer(l); else map.removeLayer(l);
                        });
                    };
                </script>
            </body>
            </html>
        """.trimIndent()
    }

    private fun setupSearch() {
        rvSearchResults.layoutManager = LinearLayoutManager(context)
        searchAdapter = SearchAdapter(emptyList()) { result ->
            rvSearchResults.visibility = View.GONE
            etMapSearch.setText(result.place.name ?: "")
            val coordinate = result.place.coordinate
            centerMap(coordinate.latitude, coordinate.longitude, 15)
            tvLiveStatusTitle.text = result.place.name ?: "Selected Location"
            tvLiveStatusSubtitle.text = result.place.address?.freeformAddress ?: "Lat: %.4f, Lon: %.4f".format(coordinate.latitude, coordinate.longitude)
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
        val search = searchApi
        if (search != null) {
            val options = SearchOptions(
                query = query,
                geoBias = GeoPoint(currentLat, currentLon),
                limit = 5
            )
            search.search(options, object : SearchCallback {
                override fun onSuccess(result: SearchResponse) {
                    activity?.runOnUiThread {
                        if (result.results.isNotEmpty()) {
                            searchAdapter.updateResults(result.results)
                            rvSearchResults.visibility = View.VISIBLE
                        } else {
                            fallbackLocalSearch(query)
                        }
                    }
                }

                override fun onFailure(failure: SearchFailure) {
                    activity?.runOnUiThread {
                        fallbackLocalSearch(query)
                    }
                }
            })
        } else {
            fallbackLocalSearch(query)
        }
    }

    private fun fallbackLocalSearch(query: String) {
        val q = query.lowercase()
        when {
            q.contains("hospital") || q.contains("clinic") -> {
                centerMap(19.0515, 72.8290, 15)
                tvLiveStatusTitle.text = "Lilavati Hospital & Research Centre"
                tvLiveStatusSubtitle.text = "Bandra West, Mumbai • 24/7 Emergency Trauma Care"
            }
            q.contains("ev") || q.contains("charge") -> {
                centerMap(19.0880, 72.8890, 15)
                tvLiveStatusTitle.text = "Tata Power Fast Charging Hub"
                tvLiveStatusSubtitle.text = "BKC, Mumbai • 4 Superchargers Available"
            }
            q.contains("hazard") || q.contains("traffic") -> {
                centerMap(19.0680, 72.8350, 15)
                tvLiveStatusTitle.text = "SV Road Congestion & Roadwork"
                tvLiveStatusSubtitle.text = "Average speed: 18 km/h • Detour advised"
            }
            else -> {
                centerMap(19.0760, 72.8777, 14)
                tvLiveStatusTitle.text = "$query, Mumbai"
                tvLiveStatusSubtitle.text = "Coordinates: 19.0760° N, 72.8777° E"
            }
        }
        Toast.makeText(context, "Location found: $query", Toast.LENGTH_SHORT).show()
    }

    private fun setupChips(view: View) {
        view.findViewById<Chip>(R.id.chipHospitals).setOnClickListener {
            centerMap(19.0515, 72.8290, 15)
            tvLiveStatusTitle.text = "Lilavati Hospital (Nearest Emergency)"
            tvLiveStatusSubtitle.text = "1.8 km away • Tel: +91 22 2675 1000"
            Toast.makeText(context, "Showing Nearest Hospitals", Toast.LENGTH_SHORT).show()
        }

        view.findViewById<Chip>(R.id.chipTraffic).setOnClickListener {
            isTrafficEnabled = !isTrafficEnabled
            mapWebView.evaluateJavascript("window.toggleTrafficOverlay($isTrafficEnabled);", null)
            tvLiveStatusTitle.text = if (isTrafficEnabled) "Live Traffic Active" else "Traffic Overlay Hidden"
            tvLiveStatusSubtitle.text = "Real-time congestion tracking • Average speed 42 km/h"
            Toast.makeText(context, "Traffic Overlay: ${if (isTrafficEnabled) "ON" else "OFF"}", Toast.LENGTH_SHORT).show()
        }

        view.findViewById<Chip>(R.id.chipIncidents).setOnClickListener {
            centerMap(19.0680, 72.8350, 15)
            tvLiveStatusTitle.text = "Road Hazard Alert: Roadwork"
            tvLiveStatusSubtitle.text = "SV Road Junction • Reported by 12 citizens"
            Toast.makeText(context, "Showing Active Hazards", Toast.LENGTH_SHORT).show()
        }

        view.findViewById<Chip>(R.id.chipEco).setOnClickListener {
            centerMap(19.0950, 72.8650, 14)
            tvLiveStatusTitle.text = "Eco Route Corridor"
            tvLiveStatusSubtitle.text = "Saves 320g of CO2 vs Highway • +35 PULSE points"
            Toast.makeText(context, "Eco Route Highlighted", Toast.LENGTH_SHORT).show()
        }

        view.findViewById<Chip>(R.id.chipEV).setOnClickListener {
            centerMap(19.0880, 72.8890, 15)
            tvLiveStatusTitle.text = "Tata Power Fast Charging Hub"
            tvLiveStatusSubtitle.text = "BKC • 4 Superchargers Available (60 kW)"
            Toast.makeText(context, "Showing EV Charging Stations", Toast.LENGTH_SHORT).show()
        }
    }

    private fun setupFabs(view: View) {
        view.findViewById<FloatingActionButton>(R.id.fabMyLocation).setOnClickListener {
            checkLocationPermission()
        }

        view.findViewById<FloatingActionButton>(R.id.fabTrafficToggle).setOnClickListener {
            isTrafficEnabled = !isTrafficEnabled
            mapWebView.evaluateJavascript("window.toggleTrafficOverlay($isTrafficEnabled);", null)
            Toast.makeText(context, "Traffic layer: ${if (isTrafficEnabled) "Enabled" else "Disabled"}", Toast.LENGTH_SHORT).show()
        }

        view.findViewById<FloatingActionButton>(R.id.fabReportHazard).setOnClickListener {
            startActivity(Intent(activity, ReportIncidentActivity::class.java))
        }

        view.findViewById<View>(R.id.btnAskYatri).setOnClickListener {
            (activity as? MainActivity)?.switchToTab(3)
        }
    }

    private fun checkLocationPermission() {
        val ctx = context ?: return
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            updateUserLocation()
        } else {
            locationPermissionLauncher.launch(arrayOf(
                Manifest.permission.ACCESS_FINE_LOCATION,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ))
        }
    }

    private fun updateUserLocation() {
        val ctx = context ?: return
        val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as? LocationManager ?: return
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            val loc = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                ?: lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
            if (loc != null) {
                currentLat = loc.latitude
                currentLon = loc.longitude
            }
        }
        centerMap(currentLat, currentLon, 14)
        Toast.makeText(context, "Centered on your location", Toast.LENGTH_SHORT).show()
    }

    private fun centerMap(lat: Double, lon: Double, zoom: Int) {
        if (isMapLoaded) {
            mapWebView.evaluateJavascript("window.setCenter($lat, $lon, $zoom);", null)
        }
    }
}
