package com.meenakshi.urbanpulse

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.speech.RecognizerIntent
import android.text.Editable
import android.text.TextWatcher
import android.util.Log
import android.widget.EditText
import android.widget.LinearLayout
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.ai.client.generativeai.GenerativeModel
import com.google.ai.client.generativeai.type.content
import com.google.ai.client.generativeai.type.FunctionDeclaration
import com.google.ai.client.generativeai.type.Schema
import com.google.ai.client.generativeai.type.Tool
import com.google.ai.client.generativeai.type.FunctionType
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.meenakshi.urbanpulse.network.TomTomMcpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.Locale

class YatriAiActivity : AppCompatActivity() {

    private val TAG = "YatriAiActivity"
    private lateinit var chatAdapter: ChatAdapter
    private lateinit var chatRecyclerView: RecyclerView
    private lateinit var messageInput: EditText
    private lateinit var sendButton: FloatingActionButton
    private lateinit var inputLayout: LinearLayout
    private val messages = mutableListOf<ChatMessage>()

    private val speechLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val data = result.data
            val matches = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
            if (!matches.isNullOrEmpty()) {
                val spokenText = matches[0]
                messageInput.setText(spokenText)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContentView(R.layout.activity_yatri_ai)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        toolbar.setNavigationOnClickListener { finish() }

        chatRecyclerView = findViewById(R.id.chatRecyclerView)
        messageInput = findViewById(R.id.messageInput)
        sendButton = findViewById(R.id.sendButton)
        inputLayout = findViewById(R.id.inputLayout)

        setupRecyclerView()
        setupInputListeners()
        setupInsets()

        if (messages.isEmpty()) {
            addAiMessage("Hello! I am Yatri AI. I can help you find locations, plan routes, and check traffic using TomTom services.")
        }
    }

    private fun setupInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(inputLayout) { v, insets ->
            val type = WindowInsetsCompat.Type.ime() or WindowInsetsCompat.Type.systemBars()
            val bars = insets.getInsets(type)
            v.updatePadding(bottom = bars.bottom)
            insets
        }
        
        // Handle top inset for toolbar
        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.appBarLayout)) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.updatePadding(top = bars.top)
            insets
        }
    }

    private fun setupRecyclerView() {
        chatAdapter = ChatAdapter(this, messages)
        chatRecyclerView.layoutManager = LinearLayoutManager(this)
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
            val messageText = messageInput.text.toString().trim()
            if (messageText.isNotEmpty()) {
                sendMessage(messageText)
                messageInput.text.clear()
            } else {
                startSpeechRecognition()
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

    private fun startSpeechRecognition() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault())
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Speak now...")
        }
        try {
            speechLauncher.launch(intent)
        } catch (e: Exception) {
            Log.e(TAG, "STT Error: ${e.message}")
            addAiMessage("Error starting speech recognition: ${e.localizedMessage}")
        }
    }

    private fun sendMessage(messageText: String) {
        val userMessage = ChatMessage(messageText, isUser = true)
        chatAdapter.addMessage(userMessage)
        scrollToBottom()

        generateAiResponse(messageText)
    }

    private fun addAiMessage(messageText: String) {
        val aiMessage = ChatMessage(messageText, isUser = false)
        chatAdapter.addMessage(aiMessage)
        scrollToBottom()
    }

    private fun scrollToBottom() {
        chatRecyclerView.smoothScrollToPosition(chatAdapter.itemCount - 1)
    }

    private fun generateAiResponse(prompt: String) {
        val apiKey = BuildConfig.GEMINI_API_KEY
        if (apiKey.isEmpty() || apiKey == "null") {
            addAiMessage("Error: Gemini API Key not found.")
            return
        }

        // Define Tools (Copied from fragment logic)
        val pointSchema = Schema(
            name = "point", description = "A geographic point", type = FunctionType.OBJECT,
            properties = mapOf(
                "lat" to Schema(name = "lat", description = "Latitude", type = FunctionType.NUMBER, nullable = false),
                "lon" to Schema(name = "lon", description = "Longitude", type = FunctionType.NUMBER, nullable = false)
            ), required = listOf("lat", "lon")
        )

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

        val fuzzySearchTool = FunctionDeclaration(
            name = "tomtom-fuzzy-search", description = "Search addresses/POIs",
            parameters = listOf(Schema(name = "query", description = "Query", type = FunctionType.STRING, nullable = false)),
            requiredParameters = listOf("query")
        )

        val poiSearchTool = FunctionDeclaration(
            name = "tomtom-poi-search", description = "Find business categories",
            parameters = listOf(
                Schema(name = "query", description = "Category/Name", type = FunctionType.STRING, nullable = false),
                Schema(name = "latitude", description = "Lat bias", type = FunctionType.NUMBER, nullable = true),
                Schema(name = "longitude", description = "Lon bias", type = FunctionType.NUMBER, nullable = true)
            ), requiredParameters = listOf("query")
        )
        
        val nearbySearchTool = FunctionDeclaration(
            name = "tomtom-nearby", description = "Nearby services",
             parameters = listOf(
                Schema(name = "latitude", description = "Latitude", type = FunctionType.NUMBER, nullable = false),
                Schema(name = "longitude", description = "Longitude", type = FunctionType.NUMBER, nullable = false),
                Schema(name = "radius", description = "Radius meters", type = FunctionType.NUMBER, nullable = true),
                Schema(name = "category", description = "Category", type = FunctionType.STRING, nullable = true)
            ), requiredParameters = listOf("latitude", "longitude")
        )

        val routingTool = FunctionDeclaration(
            name = "tomtom-routing", description = "Calculate route",
             parameters = listOf(
                Schema(name = "origin_lat", description = "Origin latitude", type = FunctionType.NUMBER, nullable = false),
                Schema(name = "origin_lon", description = "Origin longitude", type = FunctionType.NUMBER, nullable = false),
                Schema(name = "dest_lat", description = "Dest latitude", type = FunctionType.NUMBER, nullable = false),
                Schema(name = "dest_lon", description = "Dest longitude", type = FunctionType.NUMBER, nullable = false)
            ), requiredParameters = listOf("origin_lat", "origin_lon", "dest_lat", "dest_lon")
        )
        
        val trafficTool = FunctionDeclaration(
            name = "tomtom-traffic", description = "Traffic incidents",
            parameters = listOf(
                Schema(name = "minLat", description = "Min Lat", type = FunctionType.NUMBER, nullable = false),
                Schema(name = "minLon", description = "Min Lon", type = FunctionType.NUMBER, nullable = false),
                Schema(name = "maxLat", description = "Max Lat", type = FunctionType.NUMBER, nullable = false),
                Schema(name = "maxLon", description = "Max Lon", type = FunctionType.NUMBER, nullable = false)
            ), requiredParameters = listOf("minLat", "minLon", "maxLat", "maxLon")
        )

        val mcpTool = Tool(
            functionDeclarations = listOf(geocodeTool, reverseGeocodeTool, fuzzySearchTool, poiSearchTool, nearbySearchTool, routingTool, trafficTool)
        )

        val generativeModel = GenerativeModel(
            modelName = "gemini-1.5-flash", apiKey = apiKey, tools = listOf(mcpTool)
        )

        val chatHistory = messages.filter { !it.isLoading }.map {
            content(if (it.isUser) "user" else "model") { text(it.message) }
        }.toMutableList()

        val chat = generativeModel.startChat(history = chatHistory)

        lifecycleScope.launch {
            // Show typing indicator
            chatAdapter.showTypingIndicator()
            scrollToBottom()

            try {
                var response = chat.sendMessage(prompt)
                
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
                    } else if (toolName == "tomtom-traffic") {
                        val minLat = args["minLat"]?.toString()?.toDoubleOrNull() ?: 0.0
                        val minLon = args["minLon"]?.toString()?.toDoubleOrNull() ?: 0.0
                        val maxLat = args["maxLat"]?.toString()?.toDoubleOrNull() ?: 0.0
                        val maxLon = args["maxLon"]?.toString()?.toDoubleOrNull() ?: 0.0
                        mcpArgs["bbox"] = listOf(minLat, minLon, maxLat, maxLon)
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

                chatAdapter.removeTypingIndicator()
                val responseText = response.text ?: "I gathered information but couldn't generate a response."
                addAiMessage(responseText)

            } catch (e: Exception) {
                chatAdapter.removeTypingIndicator()
                addAiMessage("Error: ${e.localizedMessage}")
            }
        }
    }
}
