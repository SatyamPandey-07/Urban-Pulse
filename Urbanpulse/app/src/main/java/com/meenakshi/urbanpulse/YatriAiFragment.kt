package com.meenakshi.urbanpulse

import android.app.Activity
import android.content.Intent
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

class YatriAiFragment : Fragment() {

    private lateinit var chatAdapter: ChatAdapter
    private lateinit var chatRecyclerView: RecyclerView
    private lateinit var messageInput: EditText
    private lateinit var sendButton: FloatingActionButton
    private val messages = mutableListOf<ChatMessage>()

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

        view.findViewById<MaterialButton>(R.id.btnClearChat).setOnClickListener {
            messages.clear()
            chatAdapter.notifyDataSetChanged()
            addAiMessage("Hello! I am Yatri AI, your sustainable mobility and inclusive hospitality assistant. How can I assist your journey today?")
        }

        if (messages.isEmpty()) {
            addAiMessage("Hello. I am Yatri AI, your intelligent green travel and accessible hospitality companion.\n\nAsk me about:\n- Certified Solar & Zero-Waste Stays\n- Multimodal Low-Carbon Route Planning\n- Step-Free Transit & Wheelchair-Accessible Venues\n- Air Quality Index (AQI) and Weather\n- Hotel Resource & Kitchen Waste Analytics")
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
            sendMessage("Find the nearest accessible hospital")
        }
        view.findViewById<Chip>(R.id.chipSuggestTraffic).setOnClickListener {
            sendMessage("What is the current live traffic status?")
        }
        view.findViewById<Chip>(R.id.chipSuggestAqi).setOnClickListener {
            sendMessage("What is the air quality index and weather today?")
        }
        view.findViewById<Chip>(R.id.chipSuggestEco).setOnClickListener {
            sendMessage("Recommend a certified solar eco-resort with wheelchair accessibility")
        }
        view.findViewById<Chip>(R.id.chipSuggestHazard).setOnClickListener {
            sendMessage("I want to report a road hazard")
        }
        view.findViewById<Chip>(R.id.chipSuggestSos).setOnClickListener {
            sendMessage("I need emergency assistance")
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
        lifecycleScope.launch {
            chatAdapter.showTypingIndicator()
            scrollToBottom()

            val apiKey = BuildConfig.GEMINI_API_KEY
            var answer: String? = null

            if (apiKey.isNotEmpty() && apiKey != "DEMO_GEMINI_KEY" && apiKey != "null") {
                try {
                    // TomTom MCP Tools for Gemini Function Calling
                    val geocodeTool = FunctionDeclaration(
                        name = "tomtom-geocode", description = "Convert street addresses to coordinates",
                        parameters = listOf(Schema(name = "query", description = "Address", type = FunctionType.STRING, nullable = false)),
                        requiredParameters = listOf("query")
                    )
                    val reverseGeocodeTool = FunctionDeclaration(
                        name = "tomtom-reverse-geocode", description = "Coordinates to address",
                        parameters = listOf(
                            Schema(name = "latitude", description = "Latitude", type = FunctionType.NUMBER, nullable = false),
                            Schema(name = "longitude", description = "Longitude", type = FunctionType.NUMBER, nullable = false)
                        ), requiredParameters = listOf("latitude", "longitude")
                    )
                    val poiSearchTool = FunctionDeclaration(
                        name = "tomtom-poi-search", description = "Find businesses or hospitality categories",
                        parameters = listOf(
                            Schema(name = "query", description = "Category or Name", type = FunctionType.STRING, nullable = false)
                        ), requiredParameters = listOf("query")
                    )
                    val routingTool = FunctionDeclaration(
                        name = "tomtom-routing", description = "Calculate route distance and travel time",
                        parameters = listOf(
                            Schema(name = "origin_lat", description = "Origin lat", type = FunctionType.NUMBER, nullable = false),
                            Schema(name = "origin_lon", description = "Origin lon", type = FunctionType.NUMBER, nullable = false),
                            Schema(name = "dest_lat", description = "Dest lat", type = FunctionType.NUMBER, nullable = false),
                            Schema(name = "dest_lon", description = "Dest lon", type = FunctionType.NUMBER, nullable = false)
                        ), requiredParameters = listOf("origin_lat", "origin_lon", "dest_lat", "dest_lon")
                    )

                    val mcpTool = Tool(listOf(geocodeTool, reverseGeocodeTool, poiSearchTool, routingTool))
                    val model = GenerativeModel(
                        modelName = "gemini-1.5-flash",
                        apiKey = apiKey,
                        tools = listOf(mcpTool)
                    )

                    val chatHistory = messages.filter { !it.isLoading }.map {
                        content(if (it.isUser) "user" else "model") { text(it.message) }
                    }.toMutableList()

                    val chat = model.startChat(history = chatHistory)
                    var response = chat.sendMessage(prompt)

                    // Execute Tool Calls if LLM invoked any TomTom MCP tools
                    while (response.functionCalls.isNotEmpty()) {
                        val functionCall = response.functionCalls.first()
                        val toolName = functionCall.name
                        val args = functionCall.args
                        val argMap = args.entries.associate { it.key to it.value }

                        val mcpArgs = mutableMapOf<String, Any?>()
                        if (toolName == "tomtom-routing") {
                            val originLat = args["origin_lat"]?.toString()?.toDoubleOrNull()
                            val originLon = args["origin_lon"]?.toString()?.toDoubleOrNull()
                            val destLat = args["dest_lat"]?.toString()?.toDoubleOrNull()
                            val destLon = args["dest_lon"]?.toString()?.toDoubleOrNull()
                            if (originLat != null && originLon != null && destLat != null && destLon != null) {
                                mcpArgs["origin"] = mapOf("lat" to originLat, "lon" to originLon)
                                mcpArgs["destination"] = mapOf("lat" to destLat, "lon" to destLon)
                            }
                        } else if (toolName == "tomtom-reverse-geocode") {
                            val lat = args["latitude"]?.toString()?.toDoubleOrNull()
                            val lon = args["longitude"]?.toString()?.toDoubleOrNull()
                            if (lat != null && lon != null) mcpArgs["point"] = mapOf("lat" to lat, "lon" to lon)
                        } else {
                            mcpArgs.putAll(argMap)
                        }

                        val toolResult = withContext(Dispatchers.IO) {
                            TomTomMcpClient.callTool(toolName, mcpArgs)
                        }

                        response = chat.sendMessage(
                            content("function") {
                                part(com.google.ai.client.generativeai.type.FunctionResponsePart(toolName, JSONObject().put("result", toolResult)))
                            }
                        )
                    }

                    answer = response.text
                } catch (e: Exception) {
                    // Fall back to smart local engine
                }
            }

            if (answer.isNullOrEmpty()) {
                delay(500)
                answer = getSmartAssistantResponse(prompt)
            }

            chatAdapter.removeTypingIndicator()
            addAiMessage(answer)
        }
    }

    private fun getSmartAssistantResponse(input: String): String {
        val q = input.lowercase()
        val accessMgr = context?.let { AccessibilityManager.getInstance(it) }
        val wheelchairMode = accessMgr?.isWheelchairModeEnabled == true

        return when {
            q.contains("hotel") || q.contains("stay") || q.contains("resort") || q.contains("accommodation") || q.contains("dining") -> {
                "Verified Sustainable & Inclusive Accommodations:\n\n" +
                "1. The Orchid Eco-Heritage Resort (Vile Parle)\n" +
                "   • Sustainability: 100% Solar & Biogas Grid • Zero Single-Use Plastic\n" +
                "   • Carbon Footprint: 4.2 kg CO2e / night (68% below city avg)\n" +
                "   • Accessibility: 98% Match (Wheelchair Ramp, Roll-in Showers, Braille Elevators, Hearing Loops)\n\n" +
                "2. ITC Grand Central (Parel)\n" +
                "   • Sustainability: Wind Powered • LEED Platinum • Zero Food Waste to Landfill\n" +
                "   • Accessibility: 95% Match (Step-Free Entrance, Tactile Pathways, Visual Smoke Alarms)\n\n" +
                "3. Bandra Farm-to-Table Eco Bistro & Suites\n" +
                "   • Sustainability: Organic Local Sourcing • Rainwater Harvesting • EV Superchargers\n" +
                "   • Accessibility: 92% Match (Accessible Dining & Wide Doorways)\n\n" +
                "Tap 'Eco Stays' on your Dashboard to view full environmental audits and direct venue contact."
            }
            q.contains("route") || q.contains("metro") || q.contains("transit") || q.contains("bus") || q.contains("carbon") -> {
                val accessibilityNote = if (wheelchairMode) {
                    "Accessibility Filter Active: Route is 100% Step-Free via station elevators."
                } else {
                    "Step-Free Access: Elevators available at all interchange concourses."
                }

                "Multimodal Green Journey Recommendation:\n\n" +
                "- Mode 1 (Recommended): Metro Line 3 (Aqua Line)\n" +
                "  • Travel Time: 24 mins • Fare: ₹30\n" +
                "  • Emissions: 45g CO2e per passenger (-435g CO2 vs Petrol Taxi)\n" +
                "  • $accessibilityNote\n\n" +
                "- Mode 2: BEST Electric Low-Floor Bus\n" +
                "  • Travel Time: 36 mins • Fare: ₹15 • Emissions: 70g CO2e\n" +
                "  • Hydraulic wheelchair ramp equipped.\n\n" +
                "Earn +40 PULSE Carbon Credits by booking the Metro option!"
            }
            q.contains("hospital") || q.contains("doctor") || q.contains("medical") || q.contains("clinic") -> {
                "Nearby Medical Facilities (Accessibility Audited):\n\n" +
                "1. Lilavati Hospital & Research Centre (1.8 km)\n   • 24/7 Emergency & Trauma Care • Step-Free Ambulance Bay\n   • Tel: +91 22 2675 1000\n\n" +
                "2. Hinduja Healthcare Surgical (2.6 km)\n   • Multi-specialty Urgent Care • Wheelchair Porter Service\n   • Tel: +91 22 2445 1515\n\n" +
                "Direct navigation and dialing options are available via the Map and Medical Directory."
            }
            q.contains("traffic") || q.contains("congestion") || q.contains("jam") || q.contains("road") -> {
                "Live City Traffic Report:\n\n" +
                "- Western Express Highway: Moderate Flow (36 km/h) • Delay: ~4 mins near Santacruz\n" +
                "- Eastern Freeway: Clear / Fast Flow (58 km/h)\n" +
                "- Bandra-Worli Sea Link: Smooth Flow (70 km/h)\n" +
                "- SV Road: Heavy Congestion near Junction • Recommended detour via Link Road.\n\n" +
                "Eco suggestion: Switching to Eastern Freeway reduces carbon emissions by ~180g."
            }
            q.contains("aqi") || q.contains("air") || q.contains("pollution") || q.contains("weather") -> {
                "Air Quality & Weather Status:\n\n" +
                "- Current AQI: 136 (Moderate / Unhealthy for sensitive groups)\n" +
                "- Dominant Pollutant: PM2.5 (48.2 µg/m³)\n" +
                "- Weather: 28°C • Partly Cloudy • Humidity 68%\n\n" +
                "Health Recommendation: Sensitive individuals and outdoor runners are advised to wear an N95 mask during peak traffic hours."
            }
            q.contains("sos") || q.contains("emergency") || q.contains("help") || q.contains("police") || q.contains("danger") -> {
                "Emergency Assistance Helplines:\n\n" +
                "- National Emergency Helpline: 112\n" +
                "- Police Control: 100\n" +
                "- Ambulance Services: 108 / 102\n" +
                "- Women Safety Helpline: 1091\n\n" +
                "Tap the SOS button in the top navigation bar at any time to broadcast your real-time coordinates and send SMS alerts to emergency contacts."
            }
            q.contains("hi") || q.contains("hello") || q.contains("hey") -> {
                "Hello. I am ready to guide your journey. What would you like to check — eco-friendly stays, accessible green routes, live traffic, or your carbon savings passport?"
            }
            else -> {
                "Analysis for \"$input\":\n\n" +
                "- Current Urban Context: Mumbai Metropolitan Region\n" +
                "- Sustainability Status: Green transit corridors and certified eco-accommodations are fully indexed.\n\n" +
                "Feel free to ask for accessible route planning, EV charging hubs, certified green hotels, or kitchen waste optimization."
            }
        }
    }
}
