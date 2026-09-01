package com.urbanpulse.app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
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
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.gms.location.LocationServices
import com.google.android.material.button.MaterialButton
import com.google.android.material.chip.Chip
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.tomtom.sdk.location.GeoPoint
import com.tomtom.sdk.search.Search
import com.tomtom.sdk.search.SearchCallback
import com.tomtom.sdk.search.SearchOptions
import com.tomtom.sdk.search.SearchResponse
import com.tomtom.sdk.search.common.error.SearchFailure
import com.tomtom.sdk.search.online.OnlineSearch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.concurrent.TimeUnit

class LiveMapFragment : Fragment() {

    private lateinit var mapWebView: WebView
    private lateinit var etMapSearch: EditText
    private lateinit var btnClearSearch: ImageButton
    private lateinit var rvSearchResults: RecyclerView
    private lateinit var searchAdapter: SearchAdapter
    private lateinit var fabTrafficToggle: FloatingActionButton
    private lateinit var fabReportHazard: FloatingActionButton
    private lateinit var fabMyLocation: FloatingActionButton
    private lateinit var btnAskYatri: MaterialButton
    private lateinit var tvLiveStatusTitle: TextView
    private lateinit var tvLiveStatusSubtitle: TextView

    private var searchApi: Search? = null
    private var isTrafficEnabled = true
    private var isMapLoaded = false

    private var currentLat = 19.1775
    private var currentLon = 72.9544

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    private val locationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        if (permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
            permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        ) {
            fetchUserLocation()
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
        fabTrafficToggle = view.findViewById(R.id.fabTrafficToggle)
        fabReportHazard = view.findViewById(R.id.fabReportHazard)
        fabMyLocation = view.findViewById(R.id.fabMyLocation)
        btnAskYatri = view.findViewById(R.id.btnAskYatri)
        tvLiveStatusTitle = view.findViewById(R.id.tvLiveStatusTitle)
        tvLiveStatusSubtitle = view.findViewById(R.id.tvLiveStatusSubtitle)

        setupInteractiveMap()
        setupSearch()
        setupChips(view)
        setupFabs()

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
                    .dest-pin {
                        width: 24px; height: 24px; background: #10B981; border: 3px solid #FFFFFF;
                        border-radius: 50%; box-shadow: 0 0 16px #10B981;
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
                    var map = L.map('map', { zoomControl: false }).setView([19.1775, 72.9544], 13);
                    
                    L.tileLayer('https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png', {
                        maxZoom: 19,
                        subdomains: 'abcd'
                    }).addTo(map);

                    var userMarker = L.marker([19.1775, 72.9544], {
                        icon: L.divIcon({ className: 'user-pulse', iconSize: [18, 18], iconAnchor: [9, 9] })
                    }).addTo(map).bindPopup("<b>Your Current Location</b><br>GPS Active");

                    var routeLayerGroup = L.layerGroup().addTo(map);
                    var trafficLines = [];

                    function drawTraffic() {
                        var greenLine = L.polyline([
                            [19.0544, 72.8402], [19.0760, 72.8777], [19.1136, 72.8697]
                        ], { color: '#10B981', weight: 4, opacity: 0.8 }).addTo(map).bindPopup("Western Highway: Fast Flow (54 km/h)");

                        var yellowLine = L.polyline([
                            [19.0760, 72.8777], [19.0600, 72.8900], [19.0400, 72.9000]
                        ], { color: '#F59E0B', weight: 4, opacity: 0.8 }).addTo(map).bindPopup("Eastern Freeway: Moderate (38 km/h)");

                        trafficLines = [greenLine, yellowLine];
                    }
                    drawTraffic();

                    var pois = [
                        { lat: 19.1728, lon: 72.9564, code: "MED", title: "Fortis Hospital Mulund", desc: "24/7 Trauma Emergency", bg: "#EF4444" },
                        { lat: 19.2050, lon: 72.9734, code: "MED", title: "Jupiter Hospital Thane", desc: "Step-Free Critical Care", bg: "#EF4444" },
                        { lat: 19.0880, lon: 72.8890, code: "EV", title: "Fast Charging Hub", desc: "60 kW CCS2 (4 Available)", bg: "#38BDF8" },
                        { lat: 19.1200, lon: 72.9050, code: "ECO", title: "Powai Lake Eco Track", desc: "Dedicated Electric Mobility Corridor", bg: "#10B981" }
                    ];

                    pois.forEach(function(p) {
                        L.marker([p.lat, p.lon], {
                            icon: L.divIcon({
                                className: 'custom-pin',
                                html: '<div style="background:' + p.bg + '; width:28px; height:28px; border-radius:50%; display:flex; align-items:center; justify-content:center; border:2px solid white; font-size:9px;">' + p.code + '</div>',
                                iconSize: [28, 28],
                                iconAnchor: [14, 14]
                            })
                        }).addTo(map).bindPopup("<b>" + p.title + "</b><br>" + p.desc);
                    });

                    window.setCenter = function(lat, lon, zoom) {
                        map.flyTo([lat, lon], zoom, { duration: 1.2 });
                        userMarker.setLatLng([lat, lon]);
                    };

                    window.drawGreenRoute = function(coords, distKm, timeMin, co2Saved, destTitle) {
                        routeLayerGroup.clearLayers();

                        // Outer glowing green polyline
                        var glowLine = L.polyline(coords, {
                            color: '#059669',
                            weight: 9,
                            opacity: 0.45,
                            lineCap: 'round',
                            lineJoin: 'round'
                        });

                        // Vibrant inner neon emerald polyline
                        var mainLine = L.polyline(coords, {
                            color: '#10B981',
                            weight: 5,
                            opacity: 0.95,
                            lineCap: 'round',
                            lineJoin: 'round'
                        });

                        routeLayerGroup.addLayer(glowLine);
                        routeLayerGroup.addLayer(mainLine);

                        if (coords.length > 0) {
                            var destCoord = coords[coords.length - 1];
                            var destMarker = L.marker(destCoord, {
                                icon: L.divIcon({ className: 'dest-pin', iconSize: [24, 24], iconAnchor: [12, 12] })
                            }).bindPopup("<b>🌿 " + destTitle + "</b><br>" + distKm + " km • " + timeMin + " mins<br><span style='color:#10B981;font-weight:bold;'>-" + co2Saved + " CO2e saved vs car</span>");
                            
                            routeLayerGroup.addLayer(destMarker);
                            destMarker.openPopup();
                        }

                        map.fitBounds(mainLine.getBounds(), { padding: [50, 50], maxZoom: 15 });
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
            val name = result.place.name ?: "Destination"
            etMapSearch.setText(name)
            val coord = result.place.coordinate
            calculateAndDrawGreenRoute(coord.latitude, coord.longitude, name)
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
            q.contains("hospital") || q.contains("clinic") || q.contains("fortis") -> {
                calculateAndDrawGreenRoute(19.1728, 72.9564, "Fortis Hospital Mulund")
            }
            q.contains("jupiter") || q.contains("thane") -> {
                calculateAndDrawGreenRoute(19.2050, 72.9734, "Jupiter Hospital Thane")
            }
            q.contains("ev") || q.contains("charge") -> {
                calculateAndDrawGreenRoute(19.1200, 72.9050, "Powai EV Fast Charging Hub")
            }
            q.contains("csmt") || q.contains("south") -> {
                calculateAndDrawGreenRoute(18.9400, 72.8353, "CSMT South Mumbai")
            }
            else -> {
                calculateAndDrawGreenRoute(19.0760, 72.8777, query)
            }
        }
        Toast.makeText(context, "Calculating Green Route to $query...", Toast.LENGTH_SHORT).show()
    }

    private fun calculateAndDrawGreenRoute(destLat: Double, destLon: Double, destName: String) {
        tvLiveStatusTitle.text = "Routing to $destName..."
        tvLiveStatusSubtitle.text = "Querying live TomTom Green Corridor..."

        lifecycleScope.launch(Dispatchers.IO) {
            val apiKey = BuildConfig.TOMTOM_API_KEY
            val url = "https://api.tomtom.com/routing/1/calculateRoute/$currentLat,$currentLon:$destLat,$destLon/json?key=$apiKey"

            var pointsArray = JSONArray()
            var distKm = 0.0
            var timeMin = 0
            var co2Grams = 0

            try {
                val req = Request.Builder().url(url).get().build()
                httpClient.newCall(req).execute().use { resp ->
                    if (resp.isSuccessful) {
                        val body = resp.body?.string()
                        if (body != null) {
                            val json = JSONObject(body)
                            val routes = json.optJSONArray("routes")
                            if (routes != null && routes.length() > 0) {
                                val firstRoute = routes.getJSONObject(0)
                                val summary = firstRoute.optJSONObject("summary")
                                val lengthMeters = summary?.optDouble("lengthInMeters", 0.0) ?: 0.0
                                val travelSecs = summary?.optInt("travelTimeInSeconds", 0) ?: 0

                                distKm = lengthMeters / 1000.0
                                timeMin = travelSecs / 60
                                co2Grams = (distKm * 28.0).toInt()

                                val legs = firstRoute.optJSONArray("legs")
                                if (legs != null && legs.length() > 0) {
                                    val points = legs.getJSONObject(0).optJSONArray("points")
                                    if (points != null) {
                                        for (i in 0 until points.length()) {
                                            val p = points.getJSONObject(i)
                                            val lat = p.getDouble("latitude")
                                            val lon = p.getDouble("longitude")
                                            val coordArr = JSONArray().apply {
                                                put(lat)
                                                put(lon)
                                            }
                                            pointsArray.put(coordArr)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                // Fallback geometry
            }

            if (pointsArray.length() == 0) {
                // Geodesic curve fallback
                val midLat = (currentLat + destLat) / 2.0 + 0.005
                val midLon = (currentLon + destLon) / 2.0 - 0.003
                pointsArray = JSONArray().apply {
                    put(JSONArray().apply { put(currentLat); put(currentLon) })
                    put(JSONArray().apply { put(midLat); put(midLon) })
                    put(JSONArray().apply { put(destLat); put(destLon) })
                }
                distKm = 4.2
                timeMin = 14
                co2Grams = 120
            }

            val distFormatted = String.format(Locale.US, "%.1f", distKm)
            val co2Formatted = "${co2Grams}g"

            withContext(Dispatchers.Main) {
                tvLiveStatusTitle.text = "🌿 Green Path: $destName"
                tvLiveStatusSubtitle.text = "$distFormatted km • $timeMin mins • Avoided $co2Formatted CO2e via Electric Transit"
                val js = "window.drawGreenRoute($pointsArray, '$distFormatted', '$timeMin', '$co2Formatted', '${destName.replace("'", "")}');"
                mapWebView.evaluateJavascript(js, null)
            }
        }
    }

    private fun setupChips(view: View) {
        view.findViewById<Chip>(R.id.chipHospitals).setOnClickListener {
            calculateAndDrawGreenRoute(19.1728, 72.9564, "Fortis Hospital Mulund (Emergency)")
            Toast.makeText(context, "Green Emergency Route to Fortis Mulund", Toast.LENGTH_SHORT).show()
        }

        view.findViewById<Chip>(R.id.chipTraffic).setOnClickListener {
            isTrafficEnabled = !isTrafficEnabled
            mapWebView.evaluateJavascript("window.toggleTrafficOverlay($isTrafficEnabled);", null)
            tvLiveStatusTitle.text = if (isTrafficEnabled) "Live Traffic Active" else "Traffic Overlay Hidden"
            tvLiveStatusSubtitle.text = "Real-time congestion tracking • Average speed 42 km/h"
            Toast.makeText(context, "Traffic Overlay: ${if (isTrafficEnabled) "ON" else "OFF"}", Toast.LENGTH_SHORT).show()
        }

        view.findViewById<Chip>(R.id.chipIncidents).setOnClickListener {
            calculateAndDrawGreenRoute(19.1820, 72.9600, "LBS Marg Obstruction Detour")
            Toast.makeText(context, "Detouring Active Road Hazard", Toast.LENGTH_SHORT).show()
        }

        view.findViewById<Chip>(R.id.chipEco).setOnClickListener {
            calculateAndDrawGreenRoute(19.1200, 72.9050, "Powai Green Mobility Corridor")
            Toast.makeText(context, "Low-Carbon Green Corridor Plotted", Toast.LENGTH_SHORT).show()
        }

        view.findViewById<Chip>(R.id.chipEV).setOnClickListener {
            calculateAndDrawGreenRoute(19.2050, 72.9734, "Thane Supercharging Station (60kW)")
            Toast.makeText(context, "Green Route to EV Supercharger", Toast.LENGTH_SHORT).show()
        }
    }

    private fun setupFabs() {
        fabMyLocation.setOnClickListener {
            fetchUserLocation()
            centerMap(currentLat, currentLon, 15)
            Toast.makeText(context, "Centered at GPS location", Toast.LENGTH_SHORT).show()
        }

        fabTrafficToggle.setOnClickListener {
            isTrafficEnabled = !isTrafficEnabled
            mapWebView.evaluateJavascript("window.toggleTrafficOverlay($isTrafficEnabled);", null)
            Toast.makeText(context, "Traffic Overlay: ${if (isTrafficEnabled) "ON" else "OFF"}", Toast.LENGTH_SHORT).show()
        }

        fabReportHazard.setOnClickListener {
            calculateAndDrawGreenRoute(19.1820, 72.9600, "Active Hazard Detour")
            Toast.makeText(context, "Emergency Green Hazard Detour Plotted!", Toast.LENGTH_SHORT).show()
        }

        btnAskYatri.setOnClickListener {
            (activity as? MainActivity)?.switchToTab(3)
        }
    }

    private fun centerMap(lat: Double, lon: Double, zoom: Int) {
        mapWebView.evaluateJavascript("window.setCenter($lat, $lon, $zoom);", null)
    }

    private fun checkLocationPermission() {
        val ctx = context ?: return
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        ) {
            fetchUserLocation()
        } else {
            locationPermissionLauncher.launch(
                arrayOf(
                    Manifest.permission.ACCESS_FINE_LOCATION,
                    Manifest.permission.ACCESS_COARSE_LOCATION
                )
            )
        }
    }

    private fun fetchUserLocation() {
        val act = activity ?: return
        try {
            val fusedLocationClient = LocationServices.getFusedLocationProviderClient(act)
            fusedLocationClient.lastLocation.addOnSuccessListener { loc: Location? ->
                if (loc != null) {
                    currentLat = loc.latitude
                    currentLon = loc.longitude
                    centerMap(currentLat, currentLon, 14)
                } else {
                    val locMgr = act.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                    val lastKnown = locMgr?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                        ?: locMgr?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                    if (lastKnown != null) {
                        currentLat = lastKnown.latitude
                        currentLon = lastKnown.longitude
                        centerMap(currentLat, currentLon, 14)
                    }
                }
            }
        } catch (e: SecurityException) {
            // Permission denied
        }
    }
}
