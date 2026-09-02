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
import com.google.android.gms.location.LocationServices
import com.google.android.material.button.MaterialButton
import com.google.android.material.chip.Chip
import com.google.android.material.floatingactionbutton.FloatingActionButton
import android.location.Geocoder
import com.urbanpulse.app.network.GroqAgenticEngine
import com.urbanpulse.app.network.GroqApiClient
import com.urbanpulse.app.network.LiveCityIntelligenceService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale
import com.urbanpulse.app.data.ExperienceRepository
import com.urbanpulse.app.evidence.ExperienceOptimizer
import com.urbanpulse.app.evidence.RankedExperience
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.materialswitch.MaterialSwitch

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
            addAiMessage("Hello! I am Yatri AI, your agentic green travel & inclusive hospitality companion.\n\nI can plan multi-day eco-itineraries for any destination (e.g. Kedarnath, Lonavala, Alibaug, Manali), calculate low-carbon transit routes, and find verified step-free stays.\n\nTry asking: \"Plan a trip to Kedarnath\" or \"Plan a trip to Lonavala\"!")
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

    private var userCityName: String = "Mumbai"

    private fun fetchUserLocation() {
        val act = activity ?: return
        try {
            val fusedLocationClient = LocationServices.getFusedLocationProviderClient(act)
            fusedLocationClient.lastLocation.addOnSuccessListener { loc: Location? ->
                if (loc != null) {
                    userLatitude = loc.latitude
                    userLongitude = loc.longitude
                    isLocationDetected = true
                    resolveCityName(loc.latitude, loc.longitude)
                } else {
                    val locMgr = act.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                    val lastKnown = locMgr?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                        ?: locMgr?.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)
                    if (lastKnown != null) {
                        userLatitude = lastKnown.latitude
                        userLongitude = lastKnown.longitude
                        isLocationDetected = true
                        resolveCityName(lastKnown.latitude, lastKnown.longitude)
                    }
                }
            }
        } catch (e: SecurityException) {
            // Permission not granted
        }
    }

    private fun resolveCityName(lat: Double, lon: Double) {
        val ctx = context ?: return
        lifecycleScope.launch(Dispatchers.IO) {
            try {
                val geocoder = Geocoder(ctx, Locale.getDefault())
                @Suppress("DEPRECATION")
                val addresses = geocoder.getFromLocation(lat, lon, 1)
                if (!addresses.isNullOrEmpty()) {
                    val addr = addresses[0]
                    val detected = addr.locality ?: addr.subAdminArea ?: addr.adminArea
                    if (!detected.isNullOrBlank()) {
                        userCityName = detected
                    }
                }
            } catch (e: Exception) {
                // Keep default
            }
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
        view.findViewById<Chip>(R.id.chipMicroExperience).setOnClickListener {
            sendMessage("Find local micro-experiences within 2 hours near my location")
        }
        view.findViewById<Chip>(R.id.chipListExperience).setOnClickListener {
            showAddExperienceDialog()
        }
        view.findViewById<Chip>(R.id.chipSuggestTripLonavala).setOnClickListener {
            sendMessage("Plan a trip to Kedarnath")
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

    private fun showAddExperienceDialog() {
        val ctx = context ?: return
        val dialogView = LayoutInflater.from(ctx).inflate(R.layout.dialog_add_experience, null)
        val dialog = MaterialAlertDialogBuilder(ctx)
            .setView(dialogView)
            .create()

        val etName = dialogView.findViewById<EditText>(R.id.etExpName)
        val etCategory = dialogView.findViewById<EditText>(R.id.etExpCategory)
        val etLocation = dialogView.findViewById<EditText>(R.id.etExpLocation)
        val etDuration = dialogView.findViewById<EditText>(R.id.etExpDuration)
        val etPrice = dialogView.findViewById<EditText>(R.id.etExpPrice)
        val etSustainability = dialogView.findViewById<EditText>(R.id.etExpSustainability)
        val switchStepFree = dialogView.findViewById<MaterialSwitch>(R.id.switchStepFree)
        val switchAudioGuide = dialogView.findViewById<MaterialSwitch>(R.id.switchAudioGuide)
        val btnCancel = dialogView.findViewById<MaterialButton>(R.id.btnCancelExp)
        val btnPublish = dialogView.findViewById<MaterialButton>(R.id.btnPublishExp)

        btnCancel.setOnClickListener { dialog.dismiss() }

        btnPublish.setOnClickListener {
            val name = etName.text.toString().trim()
            val category = etCategory.text.toString().trim().ifEmpty { "Cultural Workshop" }
            val location = etLocation.text.toString().trim().ifEmpty { "Mumbai" }
            val duration = etDuration.text.toString().toDoubleOrNull() ?: 2.0
            val price = etPrice.text.toString().toIntOrNull() ?: 350
            val sustainability = etSustainability.text.toString().trim().ifEmpty { "Local artisan cooperative" }

            if (name.isEmpty()) {
                etName.error = "Please enter an experience name"
                return@setOnClickListener
            }

            val tags = mutableListOf<String>()
            if (switchStepFree.isChecked) tags += "Step-Free Ramp Access"
            if (switchAudioGuide.isChecked) tags += "Audio & Tactile Guide"
            if (tags.isEmpty()) tags += "Standard Access"

            lifecycleScope.launch {
                val success = ExperienceRepository(ctx).addExperience(
                    name = name,
                    category = category,
                    location = location,
                    sustainabilityPractice = sustainability,
                    accessibilityTags = tags,
                    accessibilityRating = if (switchStepFree.isChecked) 96 else 75,
                    ecoScore = 5,
                    carbonKg = 0.4,
                    priceRupees = price,
                    durationHours = duration
                )

                dialog.dismiss()

                if (success) {
                    Toast.makeText(ctx, "Experience published successfully!", Toast.LENGTH_SHORT).show()
                    addAiMessage(
                        "🎉 **Experience Published to UrbanPulse!**\n\n" +
                        "• **Name**: $name\n" +
                        "• **Category**: $category • $location\n" +
                        "• **Duration**: ${duration}h • ₹$price / person\n" +
                        "• **Accessibility**: ${tags.joinToString(", ")}\n" +
                        "• **Sustainability**: $sustainability\n\n" +
                        "Your experience is now live in the local registry and automatically recommended to travelers with matching time & interest profiles!"
                    )
                } else {
                    Toast.makeText(ctx, "Failed to publish experience", Toast.LENGTH_SHORT).show()
                }
            }
        }

        dialog.show()
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

    private fun extractDestination(prompt: String): String? {
        val lower = prompt.lowercase().trim()

        // Known famous pilgrimage and tourist spots
        if (lower.contains("kedar nath") || lower.contains("kedarnath")) return "Kedarnath"
        if (lower.contains("badrinath") || lower.contains("badri nath")) return "Badrinath"
        if (lower.contains("rishikesh")) return "Rishikesh"
        if (lower.contains("haridwar")) return "Haridwar"
        if (lower.contains("manali")) return "Manali"
        if (lower.contains("shimla")) return "Shimla"
        if (lower.contains("leh") || lower.contains("ladakh")) return "Leh Ladakh"
        if (lower.contains("alibaug") || lower.contains("alibag")) return "Alibaug"
        if (lower.contains("mahabaleshwar")) return "Mahabaleshwar"
        if (lower.contains("matheran")) return "Matheran"
        if (lower.contains("lonavala") || lower.contains("lonavla")) return "Lonavala"
        if (lower.contains("goa")) return "Goa"
        if (lower.contains("jaipur")) return "Jaipur"
        if (lower.contains("udaipur")) return "Udaipur"
        if (lower.contains("varanasi") || lower.contains("kashi") || lower.contains("banaras")) return "Varanasi"
        if (lower.contains("ayodhya")) return "Ayodhya"
        if (lower.contains("pune")) return "Pune"
        if (lower.contains("mumbai")) return "Mumbai"

        // Regex pattern: "plan trip to X", "planning a trip to X", "trip to X", "visit X", "itinerary for X"
        val regex = Regex("(?i)(?:plan(?:ning)?(?:\\s+a)?\\s+trip\\s+to|trip\\s+to|visit|travel\\s+to|going\\s+to|guide\\s+for|itinerary\\s+for)\\s+([a-zA-Z\\s]{2,30})")
        val match = regex.find(prompt)
        if (match != null) {
            val raw = match.groupValues[1].trim()
            val cleaned = raw.split(" with ", " for ", " in ", " using ", " by ")[0].trim()
            if (cleaned.isNotEmpty()) {
                return cleaned.split(" ").joinToString(" ") { it.replaceFirstChar { char -> char.uppercase() } }
            }
        }

        return null
    }

    private fun generateResponse(prompt: String) {
        fetchUserLocation()

        lifecycleScope.launch {
            chatAdapter.showTypingIndicator()
            scrollToBottom()

            val lowerPrompt = prompt.lowercase()

            // 1. Check if user is answering a pending Days MCQ question
            if (pendingTripDestination != null && (lowerPrompt.contains("day") || lowerPrompt.contains("express") || lowerPrompt.contains("weekend") || lowerPrompt.contains("leisure") || lowerPrompt.contains("yatra") || lowerPrompt.contains("pilgrimage") || lowerPrompt.matches(Regex(".*\\b[1-7]\\b.*")))) {
                chatAdapter.removeTypingIndicator()
                val days = when {
                    lowerPrompt.contains("1") || lowerPrompt.contains("express") -> 1
                    lowerPrompt.contains("3") -> 3
                    lowerPrompt.contains("4") || lowerPrompt.contains("5") || lowerPrompt.contains("pilgrimage") -> 4
                    lowerPrompt.contains("7") || lowerPrompt.contains("complete") -> 7
                    else -> 2
                }
                pendingTripDays = days
                val dest = pendingTripDestination ?: "Kedarnath"

                val isHimalayan = dest.contains("Kedar", true) || dest.contains("Badri", true) || dest.contains("Manali", true) || dest.contains("Leh", true)

                val options = if (isHimalayan) {
                    listOf(
                        "Palki & Accessible ♿",
                        "Eco Pilgrim Trek 🌿",
                        "Budget Devotee 🎒",
                        "Heli-Yatra & Luxury 🚁"
                    )
                } else {
                    listOf(
                        "Wheelchair Step-Free ♿",
                        "Eco Nature & Farm 🌿",
                        "Budget Explorer 🎒",
                        "Luxury Heritage 🏰"
                    )
                }

                addAiMessage(
                    text = "Got it! A **$days-Day trip to $dest** is selected.\n\nNow, what is your preferred travel style and accessibility requirement for $dest?",
                    mcq = QuickMcqQuestion(
                        questionId = "style_mcq",
                        questionText = "Select travel style",
                        options = options
                    )
                )
                return@launch
            }

            // 2. Check if user is answering the Style MCQ question
            if (pendingTripDestination != null && (lowerPrompt.contains("wheelchair") || lowerPrompt.contains("palki") || lowerPrompt.contains("heli") || lowerPrompt.contains("step-free") || lowerPrompt.contains("eco") || lowerPrompt.contains("nature") || lowerPrompt.contains("pilgrim") || lowerPrompt.contains("devotee") || lowerPrompt.contains("budget") || lowerPrompt.contains("luxury") || lowerPrompt.contains("heritage"))) {
                chatAdapter.removeTypingIndicator()
                val dest = pendingTripDestination ?: "Kedarnath"
                val days = pendingTripDays
                val isAccessible = lowerPrompt.contains("wheelchair") || lowerPrompt.contains("palki") || lowerPrompt.contains("step-free")
                val style = if (isAccessible) "Wheelchair / Step-Free Accessible" else "Eco Nature Explorer"
                val generatedTrip = withContext(Dispatchers.IO) {
                    GroqAgenticEngine.generateAutonomousTripPlan(
                        destination = dest,
                        originCity = userCityName,
                        days = days,
                        isAccessible = isAccessible,
                        travelStyle = style
                    )
                }

                addAiMessage(
                    text = "🌿 **Your $days-Day Sustainable & Accessible Itinerary for $dest is Ready!**\n\n" +
                            "• 🚆 **Transit Option**: ${generatedTrip.travelMode} (Cost: ₹${generatedTrip.transitCostInr})\n" +
                            "• 🏨 **Verified Stay**: ${generatedTrip.hotelName} (Rating: ★ ${generatedTrip.hotelRating})\n" +
                            "• ♿ **Accessibility**: ${if (generatedTrip.isStepFreeAccessible) "100% Level Boarding & Assisted Palki / Concourse" else "Standard Concourse"}\n" +
                            "• 💨 **Air Quality**: ${generatedTrip.aqiStatus}\n" +
                            "• 💰 **Estimated Budget**: ₹${generatedTrip.totalBudgetInr}\n" +
                            "• 🌱 **Carbon Avoided**: -${generatedTrip.co2SavedKg} kg CO2e vs private petrol SUV!\n\n" +
                            "You can save this trip to your **Trips tab** or open the full timeline below:",
                    trip = generatedTrip
                )
                pendingTripDestination = null
                return@launch
            }

            // 3. Dynamic Destination Extraction (Kedarnath, Manali, Lonavala, etc.)
            val extractedDest = extractDestination(prompt)
            if (extractedDest != null || lowerPrompt.contains("plan") || lowerPrompt.contains("trip") || lowerPrompt.contains("itinerary")) {
                chatAdapter.removeTypingIndicator()
                val dest = extractedDest ?: "Kedarnath"
                pendingTripDestination = dest

                val isHimalayan = dest.contains("Kedar", true) || dest.contains("Badri", true) || dest.contains("Manali", true) || dest.contains("Leh", true)

                val options = if (isHimalayan) {
                    listOf(
                        "3 Days Express Yatra",
                        "4 Days Pilgrim Trek",
                        "7 Days Complete Circuit",
                        "Custom Duration"
                    )
                } else {
                    listOf(
                        "1 Day Express (Same Day)",
                        "2 Days Weekend",
                        "3 Days Leisure",
                        "Custom Duration"
                    )
                }

                addAiMessage(
                    text = "I would be happy to design a smart, low-carbon, and accessible itinerary to **$dest**! 🏔️\n\nHow many days are you planning for your $dest trip?",
                    mcq = QuickMcqQuestion(
                        questionId = "days_mcq",
                        questionText = "Select trip duration",
                        options = options
                    )
                )
                return@launch
            }

            // 2. Micro-Experience Time Crunch Filter ("2 hours", "micro experience", "short on time")
            if (lowerPrompt.contains("2 hour") || lowerPrompt.contains("2 hr") || lowerPrompt.contains("micro-experience") || lowerPrompt.contains("micro experience") || lowerPrompt.contains("time crunch") || lowerPrompt.contains("short time")) {
                chatAdapter.removeTypingIndicator()
                val ctx = context
                if (ctx != null) {
                    val allExp = withContext(Dispatchers.IO) {
                        try {
                            ExperienceRepository(ctx).getAllExperiences()
                        } catch (e: Exception) { emptyList() }
                    }
                    val isWheelchair = AccessibilityManager.getInstance(ctx).isWheelchairModeEnabled
                    val filtered = allExp.filter { it.durationHours <= 2.5 && (!isWheelchair || it.accessibilityRating >= 80) }
                    val ranked = ExperienceOptimizer.rank(filtered)

                    val builder = StringBuilder("⏱️ **Found ${ranked.size} Pareto-Optimized Micro-Experiences (Under 2 Hours)**\n\n")
                    builder.append("Curated for your available time window near your coordinates with verified accessibility:\n\n")

                    ranked.take(4).forEachIndexed { index, r ->
                        val exp = r.experience
                        val badgeText = if (r.badges.isNotEmpty()) " [${r.badges.first().label}]" else ""
                        builder.append("${index + 1}. **${exp.name}**$badgeText\n")
                        builder.append("   • **Category**: ${exp.category} (${exp.location})\n")
                        builder.append("   • **Duration**: ${exp.durationHours}h • **Price**: ${exp.pricePerPerson}\n")
                        builder.append("   • **Accessibility**: ${exp.accessibilityRating}% (${exp.accessibilityTags.joinToString()})\n")
                        builder.append("   • **Eco Impact**: ${exp.carbonFootprintPerVisit}\n\n")
                    }

                    builder.append("Would you like transit directions or to book a spot for one of these?")
                    addAiMessage(
                        builder.toString(),
                        mcq = QuickMcqQuestion(
                            questionId = "micro_exp_mcq",
                            questionText = "Select experience to route",
                            options = ranked.take(3).map { it.experience.name } + listOf("Explore More Stays")
                        )
                    )
                    return@launch
                }
            }

            // 4. Groq Ultra-Fast AI with Grounded Local Experiences
            val isWheelchair = context?.let { AccessibilityManager.getInstance(it) }?.isWheelchairModeEnabled == true
            val expContext = try {
                context?.let { ExperienceRepository(it).getAllExperiences() }
                    ?.take(6)
                    ?.joinToString("; ") { "${it.name} (${it.category} in ${it.location}, ${it.durationHours}h, ${it.pricePerPerson}, Eco: ${it.ecoScore}/5, Access: ${it.accessibilityRating}%)" }
            } catch (e: Exception) { null }

            val groqSystemPrompt = "You are Yatri AI, an expert sustainable travel & smart mobility companion for UrbanPulse. You can answer ANY question naturally, including math, logic, science, and travel. User location: ($userLatitude, $userLongitude). " +
                (if (!expContext.isNullOrEmpty()) "Verified Local Experiences in SQLite: [$expContext]. When asked for local recommendations, workshops, cultural activities, or short experiences, prioritize recommending these verified gems! " else "") +
                "Keep answers concise, direct, and actionable."
            
            var aiResponse = GroqApiClient.queryGroq(prompt, groqSystemPrompt)

            if (aiResponse.isNullOrBlank()) {
                aiResponse = withContext(Dispatchers.IO) {
                    LiveCityIntelligenceService.queryGroundedIntelligence(
                        userPrompt = prompt,
                        userLat = userLatitude,
                        userLon = userLongitude,
                        isWheelchair = isWheelchair
                    )
                }
            }

            chatAdapter.removeTypingIndicator()
            addAiMessage(aiResponse)
        }
    }

    private fun buildDynamicTrip(destination: String, days: Int, isAccessible: Boolean, style: String): TripPlan {
        return when {
            destination.contains("Kedar", true) -> {
                TripPlan(
                    id = "trip_dyn_kedarnath_${System.currentTimeMillis()}",
                    destination = "Kedarnath",
                    title = "Kedarnath Dham Holy Eco-Yatra",
                    durationDays = days,
                    travelDates = "Upcoming Spiritual Journey ($days Days)",
                    travelMode = "Mumbai-Haridwar Superfast Rail + Electric Pilgrim Shuttle",
                    co2SavedKg = (14.2 * days),
                    pulsePointsEarned = (160 * days),
                    isCompleted = false,
                    hotelName = "GMVN Mandakini Eco Tourist Rest House (Solar Heated)",
                    hotelRating = 4.8,
                    isStepFreeAccessible = isAccessible,
                    totalBudgetInr = (2800 * days),
                    aqiStatus = "Pristine Himalayan Alpine Air (AQI 18)",
                    transitCostInr = 1450,
                    dailyItinerary = listOf(
                        TripDaySchedule(
                            dayNumber = 1,
                            dayTitle = "Mumbai (CSMT/Bandra) Departure to Haridwar Hub",
                            activities = listOf(
                                TripActivity("08:30 AM", "Haridwar AC Superfast Express", "Mumbai CSMT/Bandra to Haridwar Jn (100% Electric Rail • Level Boarding)", "Train", true, 280, 1450),
                                TripActivity("03:00 PM", "Solar Eco Guest House Check-in", "Haridwar GMVN Alaknanda Rest House (Step-Free Concourse)", "Hotel", true, 0, 0),
                                TripActivity("06:30 PM", "Har Ki Pauri Ganga Aarti", "Paved accessible riverside walkway & bio-toilets", "Walk", true, 0, 0)
                            )
                        ),
                        TripDaySchedule(
                            dayNumber = 2,
                            dayTitle = "Haridwar to Sonprayag & Gaurikund Base",
                            activities = listOf(
                                TripActivity("06:00 AM", "AC Electric Pilgrim Coach", "Haridwar to Sonprayag Hub (Low-Carbon Scenic Valley)", "E-Bus", true, 45, 650),
                                TripActivity("02:30 PM", "Govt Electric Local Shuttle", "Sonprayag to Gaurikund Base (Zero Emission E-Shuttle)", "E-Bus", true, 10, 50),
                                TripActivity("04:30 PM", "Eco Rest House Check-in", "GMVN Mandakini Solar Guest House (Heated Step-Free)", "Hotel", true, 0, 0)
                            )
                        ),
                        TripDaySchedule(
                            dayNumber = 3,
                            dayTitle = "Gaurikund to Shri Kedarnath Dham",
                            activities = listOf(
                                TripActivity("05:30 AM", "Eco Pilgrim Ascent", if (isAccessible) "Assisted Step-free Palki / Wheelchair Hoist route" else "Paved Himalayan Walking Trail", "Walk", true, 0, 0),
                                TripActivity("01:00 PM", "Shri Kedarnath Temple Darshan", "12th Jyotirlinga Darshan & Zero-Plastic Eco Zone", "Walk", true, 0, 0),
                                TripActivity("06:30 PM", "Evening Mandakini Aarti", "Solar lit temple complex with bio-toilets", "Walk", true, 0, 0)
                            )
                        ),
                        TripDaySchedule(
                            dayNumber = 4,
                            dayTitle = "Bhairavnath Ridge & Return Journey to Mumbai",
                            activities = listOf(
                                TripActivity("07:00 AM", "Bhairavnath Panoramic Shrine", "Morning alpine view overlooking Kedarnath temple", "Walk", true, 0, 0),
                                TripActivity("11:30 AM", "Descent to Gaurikund Base", "Govt E-Shuttle back to Sonprayag", "E-Bus", true, 10, 50),
                                TripActivity("06:00 PM", "Return Superfast Express", "Haridwar Junction to Mumbai CSMT", "Train", true, 280, 1450)
                            )
                        )
                    )
                )
            }
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
            destination.contains("Manali", true) -> {
                TripPlan(
                    id = "trip_dyn_manali_${System.currentTimeMillis()}",
                    destination = "Manali",
                    title = "Manali Alpine Pine & Solar Retreat",
                    durationDays = days,
                    travelDates = "Upcoming Getaway ($days Days)",
                    travelMode = "HRTC AC Electric Coach (Chandigarh to Manali)",
                    co2SavedKg = (18.0 * days),
                    pulsePointsEarned = (140 * days),
                    isCompleted = false,
                    hotelName = "The Himalayan Organic Eco-Lodge (Solar Powered)",
                    hotelRating = 4.8,
                    isStepFreeAccessible = true,
                    totalBudgetInr = (3100 * days),
                    aqiStatus = "Clean Himalayan Pine Air (AQI 20)",
                    transitCostInr = 550,
                    dailyItinerary = listOf(
                        TripDaySchedule(
                            dayNumber = 1,
                            dayTitle = "Old Manali & Hadimba Forest Sanctuary",
                            activities = listOf(
                                TripActivity("08:00 AM", "HRTC Electric Coach Arrival", "Manali Bus Stand to Old Manali", "E-Bus", true, 20, 550),
                                TripActivity("11:30 AM", "Hadimba Temple Cedar Trail", "Step-free paved cedar forest walking corridor", "Walk", true, 0, 0),
                                TripActivity("04:00 PM", "Vashisht Natural Thermal Baths", "Solar-heated natural hot springs with accessible ramp", "Walk", true, 0, 0)
                            )
                        )
                    )
                )
            }
            destination.contains("Lonavala", true) -> {
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
            else -> {
                // Any other destination dynamically planned
                TripPlan(
                    id = "trip_dyn_custom_${System.currentTimeMillis()}",
                    destination = destination,
                    title = "$destination $days-Day Low-Carbon Journey",
                    durationDays = days,
                    travelDates = "Upcoming Journey ($days Days)",
                    travelMode = "Electric Vande Bharat / AC Electric Coach",
                    co2SavedKg = (11.5 * days),
                    pulsePointsEarned = (130 * days),
                    isCompleted = false,
                    hotelName = "Green Key Certified Eco-Stay $destination",
                    hotelRating = 4.8,
                    isStepFreeAccessible = isAccessible,
                    totalBudgetInr = (2500 * days),
                    aqiStatus = "Clean Regional Air (AQI 32)",
                    transitCostInr = 400,
                    dailyItinerary = listOf(
                        TripDaySchedule(
                            dayNumber = 1,
                            dayTitle = "$destination City & Nature Discovery",
                            activities = listOf(
                                TripActivity("08:00 AM", "Electric Transit Arrival", "Arrive via high-speed electric rail or e-bus", "Train", true, 35, 400),
                                TripActivity("11:00 AM", "Step-Free Eco Check-in", "Solar powered certified hotel accommodation", "Hotel", true, 0, 0),
                                TripActivity("03:30 PM", "$destination Heritage & Walking Trail", "Pedestrianized zero-emission cultural corridor", "Walk", true, 0, 0)
                            )
                        )
                    )
                )
            }
        }
    }
}
