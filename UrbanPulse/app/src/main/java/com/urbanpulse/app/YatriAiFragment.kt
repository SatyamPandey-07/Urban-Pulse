package com.urbanpulse.app

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
import com.urbanpulse.app.network.LiveCityIntelligenceService
import com.urbanpulse.app.network.TomTomMcpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.Locale

class YatriAiFragment : Fragment() {

    private lateinit var chatAdapter: ChatAdapter
    private lateinit var chatRecyclerView: RecyclerView
    private lateinit var messageInput: EditText
    private lateinit var sendButton: FloatingActionButton
    private val messages = mutableListOf<ChatMessage>()

    private var userLatitude: Double = 19.0760
    private var userLongitude: Double = 72.8777
    private var isLocationDetected: Boolean = false

    // Multi-turn Trip Planning State Machine
    private var pendingTripDestination: String? = null
    private var pendingTripDays: Int = 2
    private var pendingTripStyle: String = "Eco Nature"

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
            pendingTripDestination = null
            addAiMessage("Hello! I am Yatri AI, your sustainable mobility and inclusive hospitality assistant. How can I assist your journey today?")
        }

        if (messages.isEmpty()) {
            addAiMessage("Hello! I am Yatri AI, your agentic green travel & inclusive hospitality companion.\n\nI can plan multi-day eco-itineraries, calculate low-carbon transit routes, find verified step-free stays, and query real-time TomTom & Open-Meteo environmental tools.\n\nTry asking: \"Plan a trip to Lonavala\" or \"Find accessible eco-resorts near me\"!")
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
        chatAdapter = ChatAdapter(
            messages,
            onMcqOptionSelected = { selectedOption ->
                sendMessage(selectedOption)
            },
            onSaveTripClicked = { trip ->
                context?.let { ctx ->
                    TripRepository.addTrip(ctx, trip)
                    Toast.makeText(ctx, "✅ Saved \"${trip.title}\" to My Trips!", Toast.LENGTH_SHORT).show()
                }
            },
            onViewTripClicked = { trip ->
                val intent = Intent(context, TripDetailActivity::class.java).apply {
                    putExtra("EXTRA_TRIP_PLAN", trip)
                }
                startActivity(intent)
            }
        )
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
        view.findViewById<Chip>(R.id.chipSuggestTripLonavala).setOnClickListener {
            sendMessage("Plan a trip to Lonavala")
        }
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

    private fun addAiMessage(text: String, mcq: QuickMcqQuestion? = null, trip: TripPlan? = null) {
        val aiMsg = ChatMessage(text, isUser = false, mcqQuestion = mcq, generatedTrip = trip)
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

            val lowerPrompt = prompt.lowercase()

            // 1. Check if user is answering a pending Days MCQ question
            if (pendingTripDestination != null && (lowerPrompt.contains("day") || lowerPrompt.contains("express") || lowerPrompt.contains("weekend") || lowerPrompt.contains("leisure") || lowerPrompt.matches(Regex(".*\\b[1-7]\\b.*")))) {
                chatAdapter.removeTypingIndicator()
                val days = when {
                    lowerPrompt.contains("1") || lowerPrompt.contains("express") -> 1
                    lowerPrompt.contains("3") || lowerPrompt.contains("leisure") -> 3
                    else -> 2
                }
                pendingTripDays = days
                val dest = pendingTripDestination ?: "Lonavala"

                addAiMessage(
                    text = "Got it! A **$days-Day trip to $dest** is selected.\n\nNow, what is your preferred travel style and accessibility requirement?",
                    mcq = QuickMcqQuestion(
                        questionId = "style_mcq",
                        questionText = "Select travel style",
                        options = listOf(
                            "Wheelchair Step-Free ♿",
                            "Eco Nature & Farm 🌿",
                            "Budget Explorer 🎒",
                            "Luxury Heritage 🏰"
                        )
                    )
                )
                return@launch
            }

            // 2. Check if user is answering the Style MCQ question
            if (pendingTripDestination != null && (lowerPrompt.contains("wheelchair") || lowerPrompt.contains("step-free") || lowerPrompt.contains("eco") || lowerPrompt.contains("nature") || lowerPrompt.contains("budget") || lowerPrompt.contains("luxury") || lowerPrompt.contains("heritage"))) {
                chatAdapter.removeTypingIndicator()
                val dest = pendingTripDestination ?: "Lonavala"
                val days = pendingTripDays
                val isAccessible = lowerPrompt.contains("wheelchair") || lowerPrompt.contains("step-free")
                val style = if (isAccessible) "Wheelchair Step-Free" else "Eco Nature"

                val generatedTrip = buildDynamicTrip(dest, days, isAccessible, style)

                addAiMessage(
                    text = "🌿 **Your $days-Day Sustainable & Accessible Itinerary for $dest is Ready!**\n\n" +
                            "• 🚆 **Transit Option**: ${generatedTrip.travelMode} (Cost: ₹${generatedTrip.transitCostInr})\n" +
                            "• 🏨 **Verified Eco Stay**: ${generatedTrip.hotelName} (Rating: ★ ${generatedTrip.hotelRating})\n" +
                            "• ♿ **Accessibility**: ${if (generatedTrip.isStepFreeAccessible) "100% Level Boarding & Elevator Concourses" else "Standard Concourse"}\n" +
                            "• 💨 **Air Quality**: ${generatedTrip.aqiStatus}\n" +
                            "• 💰 **Estimated Budget**: ₹${generatedTrip.totalBudgetInr}\n" +
                            "• 🌱 **Carbon Avoided**: -${generatedTrip.co2SavedKg} kg CO2e vs petrol taxi!\n\n" +
                            "You can save this trip to your **Trips tab** or open the full timeline below:",
                    trip = generatedTrip
                )
                pendingTripDestination = null
                return@launch
            }

            // 3. Check if user is asking to plan a trip to a destination
            if (lowerPrompt.contains("plan") || lowerPrompt.contains("trip") || lowerPrompt.contains("itinerary") || lowerPrompt.contains("lonavala") || lowerPrompt.contains("alibaug") || lowerPrompt.contains("mahabaleshwar") || lowerPrompt.contains("matheran")) {
                chatAdapter.removeTypingIndicator()
                val dest = when {
                    lowerPrompt.contains("alibaug") -> "Alibaug"
                    lowerPrompt.contains("mahabaleshwar") -> "Mahabaleshwar"
                    lowerPrompt.contains("matheran") -> "Matheran"
                    lowerPrompt.contains("pune") -> "Pune"
                    lowerPrompt.contains("goa") -> "Goa"
                    else -> "Lonavala"
                }
                pendingTripDestination = dest

                addAiMessage(
                    text = "I would be happy to design a smart, low-carbon, and accessible itinerary to **$dest**! 🌲\n\nHow many days are you planning for this trip?",
                    mcq = QuickMcqQuestion(
                        questionId = "days_mcq",
                        questionText = "Select trip duration",
                        options = listOf(
                            "1 Day Express (Same Day)",
                            "2 Days Weekend",
                            "3 Days Leisure",
                            "Custom Duration"
                        )
                    )
                )
                return@launch
            }

            // 4. Intelligent Local Grounded Engine
            val isWheelchair = context?.let { AccessibilityManager.getInstance(it) }?.isWheelchairModeEnabled == true
            val localResponse = withContext(Dispatchers.IO) {
                LiveCityIntelligenceService.queryGroundedIntelligence(
                    userPrompt = prompt,
                    userLat = userLatitude,
                    userLon = userLongitude,
                    isWheelchair = isWheelchair
                )
            }

            chatAdapter.removeTypingIndicator()
            addAiMessage(localResponse)
        }
    }

    private fun buildDynamicTrip(destination: String, days: Int, isAccessible: Boolean, style: String): TripPlan {
        return when {
            destination.contains("Alibaug", true) -> {
                TripPlan(
                    id = "trip_dyn_alibaug_${System.currentTimeMillis()}",
                    destination = "Alibaug",
                    title = "Alibaug Coastal & Marine Eco-Trail",
                    durationDays = days,
                    travelDates = "Upcoming Weekend ($days Days)",
                    travelMode = "Ro-Pax Electric Hybrid Ferry (Bhaucha Dhakka)",
                    co2SavedKg = (12.2 * days),
                    pulsePointsEarned = (100 * days),
                    isCompleted = false,
                    hotelName = "Radisson Blu Resort (LEED Gold Certified)",
                    hotelRating = 4.7,
                    isStepFreeAccessible = true,
                    totalBudgetInr = (2400 * days),
                    aqiStatus = "Pristine Coastal Breeze (AQI 34)",
                    transitCostInr = 380,
                    dailyItinerary = listOf(
                        TripDaySchedule(
                            dayNumber = 1,
                            dayTitle = "Mandwa Port & Coastal Heritage",
                            activities = listOf(
                                TripActivity("08:30 AM", "Ro-Pax Level-Boarding Ferry", "Ferry Wharf Mumbai to Mandwa Port (Low Emission)", "Train", true, 45, 380),
                                TripActivity("10:30 AM", "Electric Feeder Shuttle", "Mandwa to Radisson Blu Resort", "E-Bus", true, 20, 40),
                                TripActivity("01:00 PM", "Kolaba Marine Fort Viewing", "Step-free ramp concourse with solar audio guide", "Walk", true, 0, 50),
                                TripActivity("05:30 PM", "Varsoli Beach Sunset Trail", "Zero-plastic mangrove pedestrian trail", "Walk", true, 0, 0)
                            )
                        )
                    )
                )
            }
            destination.contains("Mahabaleshwar", true) -> {
                TripPlan(
                    id = "trip_dyn_mahabaleshwar_${System.currentTimeMillis()}",
                    destination = "Mahabaleshwar",
                    title = "Mahabaleshwar Strawberry & Agro-Retreat",
                    durationDays = days,
                    travelDates = "Upcoming Weekend ($days Days)",
                    travelMode = "MSRTC Electric AC Shivshahi Bus",
                    co2SavedKg = (24.0 * days),
                    pulsePointsEarned = (120 * days),
                    isCompleted = false,
                    hotelName = "Courtyard by Marriott Eco Valley",
                    hotelRating = 4.8,
                    isStepFreeAccessible = true,
                    totalBudgetInr = (3200 * days),
                    aqiStatus = "Fresh Mountain Valley (AQI 22)",
                    transitCostInr = 450,
                    dailyItinerary = listOf(
                        TripDaySchedule(
                            dayNumber = 1,
                            dayTitle = "Organic Berry Farms & Viewpoints",
                            activities = listOf(
                                TripActivity("07:00 AM", "MSRTC Electric AC Coach", "Mumbai Dadar to Mahabaleshwar Bus Stand", "E-Bus", true, 60, 450),
                                TripActivity("12:30 PM", "Mapro Organic Farm Tour", "Zero-waste agro-tourism with level pathways", "Walk", true, 0, 0),
                                TripActivity("04:30 PM", "Venna Lake Solar Boat Ride", "Electric propelled boat with wheelchair hoist", "Walk", true, 5, 150)
                            )
                        )
                    )
                )
            }
            else -> {
                // Lonavala & default
                TripPlan(
                    id = "trip_dyn_lonavala_${System.currentTimeMillis()}",
                    destination = "Lonavala",
                    title = "Lonavala $days-Day Green & Inclusive Retreat",
                    durationDays = days,
                    travelDates = "Upcoming Weekend ($days Days)",
                    travelMode = "Electric Express Train (Indrayani / Deccan Exp)",
                    co2SavedKg = (9.2 * days),
                    pulsePointsEarned = (125 * days),
                    isCompleted = false,
                    hotelName = "The Machan Solar Resort (100% Green Energy)",
                    hotelRating = 4.8,
                    isStepFreeAccessible = true,
                    totalBudgetInr = (2100 * days),
                    aqiStatus = "Clean Western Ghats Air (AQI 28)",
                    transitCostInr = 150,
                    dailyItinerary = listOf(
                        TripDaySchedule(
                            dayNumber = 1,
                            dayTitle = "Scenic Ridge & Heritage Caves",
                            activities = listOf(
                                TripActivity("07:10 AM", "Indrayani Express Electric Train", "Dadar to Lonavala (Electric Rail • Level Boarding)", "Train", true, 28, 75),
                                TripActivity("09:45 AM", "Step-Free Check-in", "The Machan Solar Treehouse Resort", "Hotel", true, 0, 0),
                                TripActivity("11:30 AM", "Karla Caves Accessible Plaza", "Ancient rock-cut Buddhist shrine with paved lower ramp", "E-Bus", true, 40, 50),
                                TripActivity("04:00 PM", "Bhushi Dam Walking Corridor", "Rainwater conservation reserve with clean pedestrian pathway", "Walk", true, 0, 0)
                            )
                        ),
                        TripDaySchedule(
                            dayNumber = 2,
                            dayTitle = "Tiger's Leap & Ryewood Botanical Garden",
                            activities = listOf(
                                TripActivity("09:00 AM", "Ryewood Botanical Garden", "Step-free paved floral trail and sensory herb garden", "Walk", true, 0, 0),
                                TripActivity("01:30 PM", "Tiger's Leap Panoramic View", "Electric tourist shuttle to cliffside platform", "E-Bus", true, 30, 60),
                                TripActivity("06:15 PM", "Deccan Express Return Rail", "Lonavala Station to Mumbai CSMT", "Train", true, 28, 75)
                            )
                        )
                    )
                )
            }
        }
    }
}
