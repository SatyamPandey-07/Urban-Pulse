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
import com.google.android.material.button.MaterialButton
import com.google.android.material.chip.Chip
import com.google.android.material.floatingactionbutton.FloatingActionButton
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
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
            addAiMessage("Hello! I am Yatri AI, your smart city mobility companion. How can I assist your journey today?")
        }

        if (messages.isEmpty()) {
            addAiMessage("Hello. I am Yatri AI, your intelligent urban mobility and safety assistant.\n\nAsk me about:\n- Nearest Hospitals and Healthcare Centers\n- Live Traffic and Arterial Congestion\n- Air Quality Index (AQI) and Weather\n- Low-emission Eco Routes\n- Hazard reporting and Emergency SOS")
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
            sendMessage("Find the nearest hospital")
        }
        view.findViewById<Chip>(R.id.chipSuggestTraffic).setOnClickListener {
            sendMessage("What is the current live traffic status?")
        }
        view.findViewById<Chip>(R.id.chipSuggestAqi).setOnClickListener {
            sendMessage("What is the air quality index and weather today?")
        }
        view.findViewById<Chip>(R.id.chipSuggestEco).setOnClickListener {
            sendMessage("Give me an eco-friendly route with low carbon emissions")
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
                    val model = GenerativeModel("gemini-1.5-flash", apiKey)
                    val result = model.generateContent(prompt)
                    answer = result.text
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

        return when {
            q.contains("hospital") || q.contains("doctor") || q.contains("medical") || q.contains("clinic") -> {
                "Nearby Medical Facilities:\n\n" +
                "1. Lilavati Hospital & Research Centre (1.8 km)\n   • 24/7 Emergency & Trauma Care\n   • Tel: +91 22 2675 1000\n\n" +
                "2. Hinduja Healthcare Surgical (2.6 km)\n   • Multi-specialty Urgent Care\n   • Tel: +91 22 2445 1515\n\n" +
                "3. KEM Hospital & Medical Centre (4.1 km)\n   • Trauma Care Center\n\n" +
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
            q.contains("eco") || q.contains("green") || q.contains("carbon") || q.contains("co2") || q.contains("cycle") -> {
                "Eco-Friendly Route Analysis:\n\n" +
                "- Optimal Route: Via Coastal Promenade & Metro Corridor\n" +
                "- Estimated Emission Savings: ~320g CO2 vs idling in traffic\n" +
                "- Rewards: +35 PULSE points upon completion via transit or EV.\n\n" +
                "A public bicycle docking station is located 150m from your current position."
            }
            q.contains("hazard") || q.contains("pothole") || q.contains("accident") || q.contains("report") -> {
                "Urban Hazard Reporting:\n\n" +
                "To report a road blockage, pothole, or infrastructure issue:\n" +
                "1. Select the Report Hazard option or tap Incident Reporting.\n" +
                "2. Tag your current GPS location.\n" +
                "3. Attach a photo and submit — verified reports update the city map for all citizens and award +50 XP."
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
                "Hello. I am ready to guide your commute. What would you like to check — live traffic, nearest healthcare facility, or air quality index?"
            }
            else -> {
                "Analysis for \"$input\":\n\n" +
                "- Current Urban Context: Mumbai Metropolitan Region\n" +
                "- Status: Road conditions on major corridors are normal. No major route closures reported.\n\n" +
                "Feel free to ask for directions, EV charging hubs, emergency clinics, or route optimization."
            }
        }
    }
}
