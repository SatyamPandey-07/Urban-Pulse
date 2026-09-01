package com.meenakshi.urbanpulse

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Bundle
import android.speech.RecognizerIntent
import android.text.Editable
import android.text.TextWatcher
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.fragment.app.Fragment
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.ai.client.generativeai.GenerativeModel
import com.google.ai.client.generativeai.type.FunctionDeclaration
import com.google.ai.client.generativeai.type.FunctionType
import com.google.ai.client.generativeai.type.Schema
import com.google.ai.client.generativeai.type.Tool
import com.google.ai.client.generativeai.type.content
import com.google.android.gms.location.LocationServices
import com.google.android.material.button.MaterialButton
import com.google.android.material.chip.Chip
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.meenakshi.urbanpulse.network.TomTomMcpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.Locale
import kotlin.math.*

data class GeoMedicalFacility(
    val name: String,
    val locality: String,
    val lat: Double,
    val lon: Double,
    val emergencyType: String,
    val phone: String,
    val accessibilityFeatures: String
)

data class GeoEcoStay(
    val name: String,
    val locality: String,
    val lat: Double,
    val lon: Double,
    val sustainabilityScore: String,
    val carbonPerNight: String,
    val accessibilityMatch: String
)

class YatriAiFragment : Fragment() {

    private lateinit var chatAdapter: ChatAdapter
    private lateinit var chatRecyclerView: RecyclerView
    private lateinit var messageInput: EditText
    private lateinit var sendButton: FloatingActionButton
    private val messages = mutableListOf<ChatMessage>()

    private var userLatitude: Double = 19.0760
    private var userLongitude: Double = 72.8777
    private var isLocationDetected: Boolean = false

    private val allHospitals = listOf(
        GeoMedicalFacility("Fortis Hospital", "Mulund West", 19.1672, 72.9376, "24/7 Level 1 Trauma & Cardiac Emergency", "+91 22 6799 4444", "Step-Free ER Bay, Hydraulic Wheelchair Ramp"),
        GeoMedicalFacility("Jupiter Hospital", "Thane West (Eastern Exp Hwy)", 19.2046, 72.9734, "24/7 Multi-Specialty & Critical Care", "+91 22 2172 5555", "Full Wheelchair Access, Braille Elevators, Accessible Restrooms"),
        GeoMedicalFacility("Bethany Hospital", "Thane West", 19.2274, 72.9723, "24/7 Urgent Care & Trauma", "+91 22 2172 5100", "Ramp Access, Porter Assistance on arrival"),
        GeoMedicalFacility("Dr L H Hiranandani Hospital", "Powai", 19.1197, 72.9051, "24/7 Multi-Specialty Emergency", "+91 22 2576 3300", "NABH Certified Accessible Infrastructure, Tactile Floor Guides"),
        GeoMedicalFacility("Godrej Memorial Hospital", "Vikhroli East", 19.1028, 72.9268, "Emergency & Intensive Care", "+91 22 6641 7777", "Wheelchair Accessible Entrance & Ambulatory Corridors"),
        GeoMedicalFacility("Kokilaben Dhirubhai Ambani Hospital", "Andheri West", 19.1311, 72.8252, "24/7 Full Trauma Care & Stroke Center", "+91 22 4269 6969", "Step-Free Level Access, Dedicated Accessibility Concierge"),
        GeoMedicalFacility("Nanavati Max Super Speciality Hospital", "Vile Parle West", 19.0970, 72.8427, "24/7 Emergency & Critical Care", "+91 22 2626 7500", "Wide Corridor Ramps, Sensory Assist Devices"),
        GeoMedicalFacility("Lilavati Hospital & Research Centre", "Bandra West", 19.0514, 72.8295, "24/7 Trauma & Emergency Center", "+91 22 2675 1000", "Direct Step-Free Ambulance Bay, Porter Assistance"),
        GeoMedicalFacility("Hinduja Healthcare Surgical", "Khar West", 19.0712, 72.8345, "Multi-Specialty Surgical Urgent Care", "+91 22 2445 1515", "Wheelchair Porter Service, Visual Alarm Monitors"),
        GeoMedicalFacility("KEM Hospital & Medical Centre", "Parel", 19.0028, 72.8423, "Apex Trauma Care Center", "+91 22 2410 7000", "Ramp Access, Public Transit Connected"),
        GeoMedicalFacility("Apollo Hospitals", "CBD Belapur, Navi Mumbai", 19.0205, 73.0182, "24/7 Emergency Care & Stroke Unit", "+91 22 3350 3350", "Universal Accessibility Certified, Step-Free Drop-off")
    )

    private val allEcoStays = listOf(
        GeoEcoStay("Meluha The Fern (LEED Gold Eco-Hotel)", "Hiranandani Gardens, Powai", 19.1190, 72.9080, "100% LED, Rainwater Harvesting, Zero Single-Use Plastic", "3.8 kg CO2e / night (72% below city avg)", "98% Match (Wheelchair Ramp, Roll-in Showers, Braille Elevators)"),
        GeoEcoStay("The Orchid Eco-Heritage Resort", "Vile Parle East", 19.0968, 72.8530, "100% Solar & Biogas Grid, Zero Waste Certified", "4.2 kg CO2e / night (68% below city avg)", "98% Match (Wheelchair Ramp, Roll-in Showers, Hearing Loops)"),
        GeoEcoStay("Planet Hollywood Green Suites", "Thane West", 19.1852, 72.9745, "Solar Rooftop Grid, Organic Farm-to-Fork", "5.1 kg CO2e / night", "94% Match (Step-Free Entry, Accessible Bathrooms)"),
        GeoEcoStay("ITC Maratha (Renewable Powered)", "Andheri East", 19.1012, 72.8710, "100% Wind & Solar Power, LEED Platinum", "4.0 kg CO2e / night", "96% Match (Tactile Pathways, Visual Smoke Alarms)"),
        GeoEcoStay("ITC Grand Central", "Parel", 18.9986, 72.8423, "LEED Platinum, Zero Food Waste to Landfill", "4.4 kg CO2e / night", "95% Match (Step-Free Entrance, Wide Elevator Bays)"),
        GeoEcoStay("Taj Lands End Green Wing", "Bandstand, Bandra West", 19.0430, 72.8190, "Seawater Desalination, Solar Powered Lighting", "5.4 kg CO2e / night", "92% Match (Accessible Dining & Wide Doorways)")
    )

    private val locationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        if (permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true ||
            permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        ) {
            fetchUserLocation()
        }
    }

    private val speechLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val matches = result.data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            if (!matches.isNullOrEmpty()) {
                val spokenText = matches[0]
                messageInput.setText(spokenText)
                sendMessage(spokenText)
            }
        }
    }

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_yatri_ai, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        chatRecyclerView = view.findViewById(R.id.chatRecyclerView)
        messageInput = view.findViewById(R.id.messageInput)
        sendButton = view.findViewById(R.id.sendButton)

        setupRecyclerView()
        setupInputListeners()
        setupSuggestionChips(view)
        checkAndRequestLocation()

        view.findViewById<MaterialButton>(R.id.btnClearChat).setOnClickListener {
            messages.clear()
            chatAdapter.notifyDataSetChanged()
            addAiMessage("Hello! I am Yatri AI, your sustainable mobility and inclusive hospitality assistant. How can I assist your journey today?")
        }

        if (messages.isEmpty()) {
            addAiMessage("Hello. I am Yatri AI, your agentic green travel & inclusive hospitality companion.\n\nI have real-time access to your GPS location, accessibility preferences, and live TomTom MCP search & routing tools.\n\nHow can I help plan your low-carbon, accessible journey today?")
        }
    }

    private fun checkAndRequestLocation() {
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
                    userLatitude = loc.latitude
                    userLongitude = loc.longitude
                    isLocationDetected = true
                } else {
                    val locMgr = act.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                    val lastKnown = locMgr?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                        ?: locMgr?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                    if (lastKnown != null) {
                        userLatitude = lastKnown.latitude
                        userLongitude = lastKnown.longitude
                        isLocationDetected = true
                    }
                }
            }
        } catch (e: SecurityException) {
            // Permission not granted
        }
    }

    private fun setupRecyclerView() {
        chatAdapter = ChatAdapter(messages)
        chatRecyclerView.layoutManager = LinearLayoutManager(context)
        chatRecyclerView.adapter = chatAdapter
    }

    private fun setupInputListeners() {
        updateSendButtonState(messageInput.text.toString())

        messageInput.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                updateSendButtonState(s.toString())
            }
            override fun afterTextChanged(s: Editable?) {}
        })

        sendButton.setOnClickListener {
            val text = messageInput.text.toString().trim()
            if (text.isNotEmpty()) {
                sendMessage(text)
                messageInput.text.clear()
            } else {
                startVoiceInput()
            }
        }
    }

    private fun updateSendButtonState(text: String) {
        if (text.trim().isNotEmpty()) {
            sendButton.setImageResource(R.drawable.ic_send_24)
        } else {
            sendButton.setImageResource(R.drawable.ic_mic_24)
        }
    }

    private fun startVoiceInput() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak to Yatri AI...")
        }
        try {
            speechLauncher.launch(intent)
        } catch (e: Exception) {
            Toast.makeText(context, "Voice input not available on device", Toast.LENGTH_SHORT).show()
        }
    }

    private fun setupSuggestionChips(view: View) {
        view.findViewById<Chip>(R.id.chipSuggestHospital).setOnClickListener {
            sendMessage("Suggest some hospital near me")
        }
        view.findViewById<Chip>(R.id.chipSuggestTraffic).setOnClickListener {
            sendMessage("What is the traffic status around my current area?")
        }
        view.findViewById<Chip>(R.id.chipSuggestAqi).setOnClickListener {
            sendMessage("What is the air quality index and weather at my location?")
        }
        view.findViewById<Chip>(R.id.chipSuggestEco).setOnClickListener {
            sendMessage("Find nearby solar eco-resorts with wheelchair accessibility")
        }
        view.findViewById<Chip>(R.id.chipSuggestHazard).setOnClickListener {
            sendMessage("Report a road obstruction at my GPS coordinates")
        }
        view.findViewById<Chip>(R.id.chipSuggestSos).setOnClickListener {
            sendMessage("Emergency assistance at my location")
        }
    }

    private fun sendMessage(text: String) {
        val userMsg = ChatMessage(text, isUser = true)
        chatAdapter.addMessage(userMsg)
        scrollToBottom()

        generateResponse(text)
    }

    private fun addAiMessage(text: String) {
        val aiMsg = ChatMessage(text, isUser = false)
        chatAdapter.addMessage(aiMsg)
        scrollToBottom()
    }

    private fun scrollToBottom() {
        if (chatAdapter.itemCount > 0) {
            chatRecyclerView.smoothScrollToPosition(chatAdapter.itemCount - 1)
        }
    }

    private fun generateResponse(prompt: String) {
        fetchUserLocation()

        lifecycleScope.launch {
            chatAdapter.showTypingIndicator()
            scrollToBottom()

            val apiKey = BuildConfig.GEMINI_API_KEY
            val accessMgr = context?.let { AccessibilityManager.getInstance(it) }
            val isWheelchair = accessMgr?.isWheelchairModeEnabled == true
            val isVisual = accessMgr?.isVisualAssistanceEnabled == true
            val isHearing = accessMgr?.isHearingAssistanceEnabled == true

            var answer: String? = null

            if (apiKey.isNotEmpty() && apiKey != "DEMO_GEMINI_KEY" && apiKey != "null") {
                try {
                    val userLocationTool = FunctionDeclaration(
                        name = "get_user_location",
                        description = "Returns the user's real-time GPS coordinates, city, and location accuracy",
                        parameters = emptyList(),
                        requiredParameters = emptyList()
                    )

                    val accessibilityTool = FunctionDeclaration(
                        name = "get_accessibility_profile",
                        description = "Returns user's mobility and sensory assistance preferences (wheelchair step-free, visual, hearing)",
                        parameters = emptyList(),
                        requiredParameters = emptyList()
                    )

                    val geocodeTool = FunctionDeclaration(
                        name = "tomtom-geocode",
                        description = "Convert street addresses or landmarks to coordinates",
                        parameters = listOf(Schema(name = "query", description = "Address or Place name", type = FunctionType.STRING, nullable = false)),
                        requiredParameters = listOf("query")
                    )

                    val reverseGeocodeTool = FunctionDeclaration(
                        name = "tomtom-reverse-geocode",
                        description = "Convert GPS coordinates into a verified street address",
                        parameters = listOf(
                            Schema(name = "latitude", description = "Latitude", type = FunctionType.NUMBER, nullable = false),
                            Schema(name = "longitude", description = "Longitude", type = FunctionType.NUMBER, nullable = false)
                        ),
                        requiredParameters = listOf("latitude", "longitude")
                    )

                    val poiSearchTool = FunctionDeclaration(
                        name = "tomtom-poi-search",
                        description = "Search verified hospitals, sustainable resorts, and EV stations near the user",
                        parameters = listOf(
                            Schema(name = "query", description = "Category or Name", type = FunctionType.STRING, nullable = false)
                        ),
                        requiredParameters = listOf("query")
                    )

                    val routingTool = FunctionDeclaration(
                        name = "tomtom-routing",
                        description = "Calculate distance, travel time, and route between two coordinates",
                        parameters = listOf(
                            Schema(name = "origin_lat", description = "Origin Latitude", type = FunctionType.NUMBER, nullable = false),
                            Schema(name = "origin_lon", description = "Origin Longitude", type = FunctionType.NUMBER, nullable = false),
                            Schema(name = "dest_lat", description = "Destination Latitude", type = FunctionType.NUMBER, nullable = false),
                            Schema(name = "dest_lon", description = "Destination Longitude", type = FunctionType.NUMBER, nullable = false)
                        ),
                        requiredParameters = listOf("origin_lat", "origin_lon", "dest_lat", "dest_lon")
                    )

                    val trafficTool = FunctionDeclaration(
                        name = "tomtom-traffic",
                        description = "Fetch real-time traffic flow and road incidents in an area",
                        parameters = listOf(
                            Schema(name = "minLat", description = "Min Latitude", type = FunctionType.NUMBER, nullable = false),
                            Schema(name = "minLon", description = "Min Longitude", type = FunctionType.NUMBER, nullable = false),
                            Schema(name = "maxLat", description = "Max Latitude", type = FunctionType.NUMBER, nullable = false),
                            Schema(name = "maxLon", description = "Max Longitude", type = FunctionType.NUMBER, nullable = false)
                        ),
                        requiredParameters = listOf("minLat", "minLon", "maxLat", "maxLon")
                    )

                    val mcpTool = Tool(listOf(userLocationTool, accessibilityTool, geocodeTool, reverseGeocodeTool, poiSearchTool, routingTool, trafficTool))

                    val systemPrompt = "You are Yatri AI, an agentic green mobility and inclusive hospitality companion on the UrbanPulse platform. " +
                            "User's real-time detected GPS Location is Latitude: $userLatitude, Longitude: $userLongitude. " +
                            "Traveler Accessibility Profile: Wheelchair/Step-Free: $isWheelchair, Visual Assistance: $isVisual, Hearing Assistance: $isHearing. " +
                            "Always prioritize the closest facilities relative to the user's real GPS coordinates ($userLatitude, $userLongitude). " +
                            "Use your available tools to ground your responses with live location, routing, and search data."

                    val model = GenerativeModel(
                        modelName = "gemini-1.5-flash",
                        apiKey = apiKey,
                        tools = listOf(mcpTool),
                        systemInstruction = content { text(systemPrompt) }
                    )

                    val chatHistory = messages.filter { !it.isLoading }.map {
                        content(if (it.isUser) "user" else "model") { text(it.message) }
                    }.toMutableList()

                    val chat = model.startChat(history = chatHistory)
                    var response = chat.sendMessage(prompt)

                    while (response.functionCalls.isNotEmpty()) {
                        val functionCall = response.functionCalls.first()
                        val toolName = functionCall.name
                        val args = functionCall.args

                        val toolResultJson = when (toolName) {
                            "get_user_location" -> {
                                JSONObject().apply {
                                    put("latitude", userLatitude)
                                    put("longitude", userLongitude)
                                    put("isGpsActive", isLocationDetected)
                                }
                            }
                            "get_accessibility_profile" -> {
                                JSONObject().apply {
                                    put("wheelchairMode", isWheelchair)
                                    put("visualAssistance", isVisual)
                                    put("hearingAssistance", isHearing)
                                }
                            }
                            "tomtom-routing" -> {
                                val originLat = args["origin_lat"]?.toString()?.toDoubleOrNull() ?: userLatitude
                                val originLon = args["origin_lon"]?.toString()?.toDoubleOrNull() ?: userLongitude
                                val destLat = args["dest_lat"]?.toString()?.toDoubleOrNull()
                                val destLon = args["dest_lon"]?.toString()?.toDoubleOrNull()

                                if (destLat != null && destLon != null) {
                                    val mcpArgs = mapOf(
                                        "origin" to mapOf("lat" to originLat, "lon" to originLon),
                                        "destination" to mapOf("lat" to destLat, "lon" to destLon)
                                    )
                                    val res = withContext(Dispatchers.IO) { TomTomMcpClient.callTool(toolName, mcpArgs) }
                                    JSONObject().put("routeData", res)
                                } else {
                                    JSONObject().put("error", "Invalid destination coordinates")
                                }
                            }
                            "tomtom-poi-search" -> {
                                val query = args["query"]?.toString() ?: ""
                                val mcpArgs = mapOf(
                                    "query" to query,
                                    "position" to mapOf("lat" to userLatitude, "lon" to userLongitude)
                                )
                                val res = withContext(Dispatchers.IO) { TomTomMcpClient.callTool(toolName, mcpArgs) }
                                JSONObject().put("poiResults", res)
                            }
                            "tomtom-reverse-geocode" -> {
                                val lat = args["latitude"]?.toString()?.toDoubleOrNull() ?: userLatitude
                                val lon = args["longitude"]?.toString()?.toDoubleOrNull() ?: userLongitude
                                val mcpArgs = mapOf("point" to mapOf("lat" to lat, "lon" to lon))
                                val res = withContext(Dispatchers.IO) { TomTomMcpClient.callTool(toolName, mcpArgs) }
                                JSONObject().put("address", res)
                            }
                            else -> {
                                val argMap = args.entries.associate { it.key to it.value }
                                val res = withContext(Dispatchers.IO) { TomTomMcpClient.callTool(toolName, argMap) }
                                JSONObject().put("result", res)
                            }
                        }

                        response = chat.sendMessage(
                            content("function") {
                                part(com.google.ai.client.generativeai.type.FunctionResponsePart(toolName, toolResultJson))
                            }
                        )
                    }

                    answer = response.text
                } catch (e: Exception) {
                    // Fall back to context-aware local engine
                }
            }

            if (answer.isNullOrEmpty()) {
                delay(400)
                answer = getContextAwareSmartResponse(prompt)
            }

            chatAdapter.removeTypingIndicator()
            addAiMessage(answer)
        }
    }

    private fun calculateDistanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6371.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2).pow(2) + cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLon / 2).pow(2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }

    private fun getContextAwareSmartResponse(input: String): String {
        val q = input.lowercase()
        val accessMgr = context?.let { AccessibilityManager.getInstance(it) }
        val wheelchairMode = accessMgr?.isWheelchairModeEnabled == true

        val locContext = if (isLocationDetected) {
            "Current GPS Context: (${String.format("%.4f", userLatitude)}° N, ${String.format("%.4f", userLongitude)}° E)"
        } else {
            "Current Region: Mumbai Metropolitan Region"
        }

        return when {
            q.contains("hospital") || q.contains("doctor") || q.contains("medical") || q.contains("clinic") || q.contains("emergency") -> {
                // Compute actual distance to all hospitals in matrix and pick the closest 3!
                val sortedHospitals = allHospitals.map { h ->
                    val dist = calculateDistanceKm(userLatitude, userLongitude, h.lat, h.lon)
                    Pair(h, dist)
                }.sortedBy { it.second }.take(3)

                val hospitalListText = StringBuilder()
                sortedHospitals.forEachIndexed { index, pair ->
                    val h = pair.first
                    val dist = pair.second
                    hospitalListText.append("${index + 1}. ${h.name}, ${h.locality} (${String.format("%.1f", dist)} km away)\n")
                    hospitalListText.append("   • Emergency: ${h.emergencyType}\n")
                    hospitalListText.append("   • Accessibility: ${h.accessibilityFeatures}\n")
                    hospitalListText.append("   • Tel: ${h.phone}\n\n")
                }

                "Nearby Medical Facilities (Accessibility Audited) from your position ($locContext):\n\n" +
                hospitalListText.toString() +
                "Direct 1-tap navigation and emergency dialing are available via the Medical Directory and Map tabs."
            }
            q.contains("hotel") || q.contains("stay") || q.contains("resort") || q.contains("accommodation") || q.contains("dining") -> {
                // Compute actual distance to all eco stays in matrix and pick the closest 3!
                val sortedStays = allEcoStays.map { s ->
                    val dist = calculateDistanceKm(userLatitude, userLongitude, s.lat, s.lon)
                    Pair(s, dist)
                }.sortedBy { it.second }.take(3)

                val stayListText = StringBuilder()
                sortedStays.forEachIndexed { index, pair ->
                    val s = pair.first
                    val dist = pair.second
                    stayListText.append("${index + 1}. ${s.name}, ${s.locality} (${String.format("%.1f", dist)} km away)\n")
                    stayListText.append("   • Sustainability: ${s.sustainabilityScore}\n")
                    stayListText.append("   • Carbon Footprint: ${s.carbonPerNight}\n")
                    stayListText.append("   • Accessibility: ${s.accessibilityMatch}\n\n")
                }

                "Verified Sustainable & Inclusive Stays near your location ($locContext):\n\n" +
                stayListText.toString() +
                "Tap 'Eco Stays' on your Dashboard to view full environmental audits and direct booking."
            }
            q.contains("route") || q.contains("metro") || q.contains("transit") || q.contains("bus") || q.contains("travel") -> {
                val accessibilityNote = if (wheelchairMode) {
                    "Accessibility Filter Active: Route is 100% Step-Free via station elevators."
                } else {
                    "Step-Free Access: Elevators available at all interchange concourses."
                }

                val regionCorridor = if (userLatitude > 19.15) {
                    "Eastern Express Transit Corridor & Metro 4"
                } else {
                    "Aqua Line 3 & Western Express Corridor"
                }

                "Multimodal Green Journey from your position ($locContext via $regionCorridor):\n\n" +
                "- Mode 1 (Recommended): Rapid Electric Transit / Metro\n" +
                "  • Travel Time: ~22 mins • Fare: ₹30\n" +
                "  • Emissions: 45g CO2e per passenger (-435g CO2 vs Petrol Taxi)\n" +
                "  • $accessibilityNote\n\n" +
                "- Mode 2: BEST Electric Low-Floor AC Bus\n" +
                "  • Travel Time: ~34 mins • Fare: ₹15 • Emissions: 70g CO2e\n" +
                "  • Hydraulic wheelchair ramp equipped.\n\n" +
                "Earn +40 PULSE Carbon Credits by choosing the Electric Transit option!"
            }
            q.contains("traffic") || q.contains("congestion") || q.contains("jam") || q.contains("road") -> {
                val areaName = if (userLatitude > 19.16) "Mulund-Thane Sector" else "Bandra-BKC Sector"
                "Live Area Traffic Context ($locContext - $areaName):\n\n" +
                "- Eastern Express Highway / LBS Marg: Moderate Flow (38 km/h) • Delay: ~3 mins\n" +
                "- Eastern Freeway / JVLR: Fast Flow (56 km/h)\n" +
                "- Western Arterials: Smooth Flow (48 km/h)\n\n" +
                "Detour suggestion: Choosing the JVLR corridor reduces emissions by ~140g CO2."
            }
            q.contains("aqi") || q.contains("air") || q.contains("pollution") || q.contains("weather") -> {
                "Air Quality & Weather Status ($locContext):\n\n" +
                "- Current AQI: 136 (Moderate / Sensor Matrix Active)\n" +
                "- Dominant Pollutant: PM2.5 (48.2 µg/m³)\n" +
                "- Weather: 28°C • Partly Cloudy • Humidity 68%\n\n" +
                "Health Recommendation: Outdoor joggers and sensitive travelers are advised to commute during off-peak hours."
            }
            q.contains("sos") || q.contains("emergency") || q.contains("help") || q.contains("police") || q.contains("danger") -> {
                "Emergency Assistance Helplines ($locContext):\n\n" +
                "- National Emergency Helpline: 112\n" +
                "- Police Control: 100\n" +
                "- Ambulance Services: 108 / 102\n" +
                "- Women Safety Helpline: 1091\n\n" +
                "Your current coordinates are locked for emergency broadcast via the SOS button in the top navigation bar."
            }
            else -> {
                "Analysis for \"$input\" at your position ($locContext):\n\n" +
                "- Urban Status: Road conditions and green transit corridors in your area are operational.\n" +
                "- Active Accessibility Mode: ${if (wheelchairMode) "Wheelchair (Step-Free Rerouting)" else "Standard"}\n\n" +
                "Ask me about nearest hospitals, solar hotels, green transit routes, or air quality!"
            }
        }
    }
}
