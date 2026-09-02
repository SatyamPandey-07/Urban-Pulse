package com.urbanpulse.app.network

import com.urbanpulse.app.BuildConfig
import com.urbanpulse.app.TripActivity
import com.urbanpulse.app.TripDaySchedule
import com.urbanpulse.app.TripPlan
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

data class GroqAgentResponse(
    val replyText: String,
    val mcqOptions: List<String>? = null,
    val structuredTrip: TripPlan? = null
)

object GroqAgenticEngine {

    private const val GROQ_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"
    private val candidateModels = listOf(
        "openai/gpt-oss-120b",
        "groq/compound",
        "openai/gpt-oss-20b",
        "groq/compound-mini"
    )

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .build()

    suspend fun generateAutonomousTripPlan(
        destination: String,
        originCity: String,
        days: Int,
        isAccessible: Boolean,
        travelStyle: String
    ): TripPlan = withContext(Dispatchers.IO) {
        val apiKey = BuildConfig.GROQ_API_KEY
        if (apiKey.isNotBlank() && apiKey != "DEMO_GROQ_KEY") {
            val systemPrompt = """
                You are Yatri AI, the autonomous green mobility & accessible travel planner for UrbanPulse.
                Generate a complete, highly realistic multi-day travel itinerary starting explicitly from the user's origin city ($originCity) to the destination ($destination).
                
                Guidelines:
                1. Day 1 MUST start from $originCity with real electric transit (e.g. electric rail, local suburban, Vande Bharat, AC e-bus, or ferry).
                2. Include real verified eco-stays, real landmarks, accurate timing, and step-free accessibility details (Wheelchair: $isAccessible).
                3. Return ONLY valid, unescaped JSON matching this schema:
                {
                    "title": "...",
                    "travelMode": "...",
                    "hotelName": "...",
                    "hotelRating": 4.8,
                    "aqiStatus": "...",
                    "totalBudgetInr": 5200,
                    "transitCostInr": 280,
                    "co2SavedKg": 18.5,
                    "transitOpt1Name": "🚆 Green Transit (e.g. Electric Rail / Local)",
                    "transitOpt1Metrics": "₹75 • 2h 05m • 28g CO2",
                    "transitOpt2Name": "⚡ AC E-Bus / Shared Shuttle",
                    "transitOpt2Metrics": "₹210 • 2h 20m • 54g CO2",
                    "transitOpt3Name": "🚗 Standard Petrol Taxi",
                    "transitOpt3Metrics": "₹3,200 • 2h 45m • 2,400g CO2",
                    "dailyItinerary": [
                        {
                            "dayNumber": 1,
                            "dayTitle": "...",
                            "activities": [
                                {
                                    "time": "08:00 AM",
                                    "title": "...",
                                    "description": "...",
                                    "transportType": "Train",
                                    "isAccessible": true,
                                    "co2Grams": 30,
                                    "costInr": 60
                                }
                            ]
                        }
                    ]
                }
            """.trimIndent()

            for (model in candidateModels) {
                try {
                    val messages = JSONArray().apply {
                        put(JSONObject().apply {
                            put("role", "system")
                            put("content", systemPrompt)
                        })
                        put(JSONObject().apply {
                            put("role", "user")
                            put("content", "Generate a $days-day $travelStyle itinerary from $originCity to $destination. Wheelchair accessible: $isAccessible.")
                        })
                    }

                    val requestJson = JSONObject().apply {
                        put("model", model)
                        put("messages", messages)
                        put("temperature", 0.2)
                        put("max_tokens", 1500)
                    }

                    val requestBody = requestJson.toString().toRequestBody("application/json".toMediaType())
                    val request = Request.Builder()
                        .url(GROQ_ENDPOINT)
                        .addHeader("Authorization", "Bearer $apiKey")
                        .addHeader("Content-Type", "application/json")
                        .post(requestBody)
                        .build()

                    val response = httpClient.newCall(request).execute()
                    val body = response.body?.string()

                    if (response.isSuccessful && body != null) {
                        val responseObj = JSONObject(body)
                        val content = responseObj.optJSONArray("choices")?.getJSONObject(0)?.optJSONObject("message")?.optString("content")
                        if (!content.isNullOrBlank()) {
                            val cleanJson = extractJsonSubstring(content)
                            val parsedTrip = parseTripPlanJson(cleanJson, destination, originCity, days, isAccessible)
                            if (parsedTrip != null) {
                                return@withContext parsedTrip
                            }
                        }
                    }
                } catch (e: Exception) {
                    // Try next model
                }
            }
        }

        // Realistic fallback tailored from origin to destination
        buildRealisticFallbackTrip(destination, originCity, days, isAccessible, travelStyle)
    }

    private fun extractJsonSubstring(text: String): String {
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        return if (start != -1 && end != -1 && end > start) {
            text.substring(start, end + 1)
        } else {
            text
        }
    }

    private fun parseTripPlanJson(
        jsonStr: String,
        destination: String,
        originCity: String,
        days: Int,
        isAccessible: Boolean
    ): TripPlan? {
        return try {
            val root = JSONObject(jsonStr)
            val title = root.optString("title", "$destination $days-Day Low-Carbon Journey")
            val travelMode = root.optString("travelMode", "Electric Rail / AC E-Bus from $originCity")
            val hotelName = root.optString("hotelName", "Green Key Certified Eco-Stay $destination")
            val hotelRating = root.optDouble("hotelRating", 4.8)
            val aqiStatus = root.optString("aqiStatus", "Clean Regional Air (AQI 28)")
            val totalBudget = root.optInt("totalBudgetInr", 2500 * days)
            val transitCost = root.optInt("transitCostInr", 350)
            val co2Saved = root.optDouble("co2SavedKg", 11.5 * days)

            val daysArray = root.optJSONArray("dailyItinerary")
            val itineraryList = mutableListOf<TripDaySchedule>()

            if (daysArray != null) {
                for (i in 0 until daysArray.length()) {
                    val dayObj = daysArray.getJSONObject(i)
                    val dayNum = dayObj.optInt("dayNumber", i + 1)
                    val dayTitle = dayObj.optString("dayTitle", "Day $dayNum: $destination Exploration")
                    val actsArray = dayObj.optJSONArray("activities")
                    val actList = mutableListOf<TripActivity>()

                    if (actsArray != null) {
                        for (j in 0 until actsArray.length()) {
                            val actObj = actsArray.getJSONObject(j)
                            actList.add(
                                TripActivity(
                                    time = actObj.optString("time", "09:00 AM"),
                                    title = actObj.optString("title", "Eco Activity"),
                                    description = actObj.optString("description", "Zero emission transit & visit"),
                                    transportType = actObj.optString("transportType", "Train"),
                                    isAccessible = actObj.optBoolean("isAccessible", true),
                                    co2Grams = actObj.optInt("co2Grams", 25),
                                    costInr = actObj.optInt("costInr", 50)
                                )
                            )
                        }
                    }
                    itineraryList.add(TripDaySchedule(dayNum, dayTitle, actList))
                }
            }

            if (itineraryList.isEmpty()) return null

            TripPlan(
                id = "trip_groq_${System.currentTimeMillis()}",
                destination = destination,
                title = title,
                durationDays = days,
                travelDates = "Upcoming Journey ($days Days)",
                travelMode = travelMode,
                co2SavedKg = co2Saved,
                pulsePointsEarned = (130 * days),
                isCompleted = false,
                hotelName = hotelName,
                hotelRating = hotelRating,
                isStepFreeAccessible = isAccessible,
                totalBudgetInr = totalBudget,
                aqiStatus = aqiStatus,
                transitCostInr = transitCost,
                dailyItinerary = itineraryList,
                transitOpt1Name = root.optString("transitOpt1Name", null),
                transitOpt1Metrics = root.optString("transitOpt1Metrics", null),
                transitOpt2Name = root.optString("transitOpt2Name", null),
                transitOpt2Metrics = root.optString("transitOpt2Metrics", null),
                transitOpt3Name = root.optString("transitOpt3Name", null),
                transitOpt3Metrics = root.optString("transitOpt3Metrics", null)
            )
        } catch (e: Exception) {
            null
        }
    }

    private fun buildRealisticFallbackTrip(
        dest: String,
        originCity: String,
        days: Int,
        isAccessible: Boolean,
        style: String
    ): TripPlan {
        val lower = dest.lowercase()
        return when {
            lower.contains("matheran") -> {
                TripPlan(
                    id = "trip_dyn_matheran_${System.currentTimeMillis()}",
                    destination = "Matheran",
                    title = "Matheran Vehicle-Free Eco-Hill Journey",
                    durationDays = days,
                    travelDates = "Upcoming Weekend ($days Days)",
                    travelMode = "$originCity Central Local to Neral + Matheran Toy Train",
                    co2SavedKg = (11.5 * days),
                    pulsePointsEarned = (130 * days),
                    isCompleted = false,
                    hotelName = "The Byke Heritage Eco-Resort (Pure Veg & Solar)",
                    hotelRating = 4.8,
                    isStepFreeAccessible = isAccessible,
                    totalBudgetInr = (2200 * days),
                    aqiStatus = "Pristine Forest Air (AQI 22 • 100% Automobile-Free)",
                    transitCostInr = 110,
                    dailyItinerary = listOf(
                        TripDaySchedule(
                            dayNumber = 1,
                            dayTitle = "$originCity to Neral & Matheran Toy Train Ascent",
                            activities = listOf(
                                TripActivity("07:30 AM", "Central Railway AC Local", "$originCity CSMT/Dadar/Thane to Neral Junction (Electric Rail • Level Boarding)", "Train", true, 35, 60),
                                TripActivity("09:45 AM", "Matheran Heritage Toy Train", "Neral to Matheran / Aman Lodge Shuttle (Zero Emission Eco-Zone)", "Train", true, 10, 50),
                                TripActivity("11:30 AM", "The Byke Heritage Check-in", "100% Solar Powered Heritage Villa (Step-Free Ramps)", "Hotel", true, 0, 0),
                                TripActivity("03:30 PM", "Charlotte Lake & Echo Point", "Vehicle-free forest pedestrian walking trail & bird watching", "Walk", true, 0, 0)
                            )
                        ),
                        TripDaySchedule(
                            dayNumber = 2,
                            dayTitle = "Louisa Point & Return to $originCity",
                            activities = listOf(
                                TripActivity("08:00 AM", "Louisa Point & Panorama Peak", "Morning valley sunrise view with bio-toilets along trail", "Walk", true, 0, 0),
                                TripActivity("01:00 PM", "Eco-E-Rickshaw to Aman Lodge", "Govt Authorized Electric Shuttle (Low Speed Zero Noise)", "E-Bus", true, 5, 35),
                                TripActivity("04:30 PM", "Central AC Local to $originCity", "Neral Junction return express train to $originCity", "Train", true, 35, 60)
                            )
                        )
                    ),
                    transitOpt1Name = "🚆 Central Local + Matheran Toy Train",
                    transitOpt1Metrics = "₹110 • 2h 15m • 35g CO2",
                    transitOpt2Name = "⚡ Neral E-Rickshaw + Shuttle",
                    transitOpt2Metrics = "₹90 • 1h 50m • 18g CO2",
                    transitOpt3Name = "🚗 Standard Petrol Taxi (to Dasturi Naka)",
                    transitOpt3Metrics = "₹2,100 • 2h 30m • 1,600g CO2"
                )
            }
            lower.contains("kedar") -> {
                TripPlan(
                    id = "trip_dyn_kedarnath_${System.currentTimeMillis()}",
                    destination = "Kedarnath",
                    title = "Kedarnath Dham Holy Eco-Yatra",
                    durationDays = days,
                    travelDates = "Upcoming Spiritual Journey ($days Days)",
                    travelMode = "$originCity-Haridwar Superfast Rail + Electric Pilgrim Shuttle",
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
                            dayTitle = "$originCity Departure to Haridwar Hub",
                            activities = listOf(
                                TripActivity("08:30 AM", "Haridwar AC Superfast Express", "$originCity CSMT/Bandra to Haridwar Jn (100% Electric Rail • Level Boarding)", "Train", true, 280, 1450),
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
                            dayTitle = "Bhairavnath Ridge & Return Journey to $originCity",
                            activities = listOf(
                                TripActivity("07:00 AM", "Bhairavnath Panoramic Shrine", "Morning alpine view overlooking Kedarnath temple", "Walk", true, 0, 0),
                                TripActivity("11:30 AM", "Descent to Gaurikund Base", "Govt E-Shuttle back to Sonprayag", "E-Bus", true, 10, 50),
                                TripActivity("06:00 PM", "Return Superfast Express", "Haridwar Junction to $originCity CSMT", "Train", true, 280, 1450)
                            )
                        )
                    ),
                    transitOpt1Name = "🚆 $originCity-Haridwar Superfast + E-Shuttle",
                    transitOpt1Metrics = "₹1,450 • Level Boarding • 280g CO2",
                    transitOpt2Name = "⚡ AC Pilgrim Express Coach",
                    transitOpt2Metrics = "₹2,200 • AC Seater • 350g CO2",
                    transitOpt3Name = "🚗 Private Highway Diesel SUV Taxi",
                    transitOpt3Metrics = "₹18,500 • High Emissions • 24,000g CO2"
                )
            }
            else -> {
                TripPlan(
                    id = "trip_dyn_gen_${System.currentTimeMillis()}",
                    destination = dest,
                    title = "$dest $days-Day Low-Carbon Journey",
                    durationDays = days,
                    travelDates = "Upcoming Journey ($days Days)",
                    travelMode = "Electric Express Train / AC E-Coach from $originCity",
                    co2SavedKg = (12.0 * days),
                    pulsePointsEarned = (130 * days),
                    isCompleted = false,
                    hotelName = "Green Key Certified Eco-Stay $dest",
                    hotelRating = 4.8,
                    isStepFreeAccessible = isAccessible,
                    totalBudgetInr = (2500 * days),
                    aqiStatus = "Clean Regional Air (AQI 28)",
                    transitCostInr = 250,
                    dailyItinerary = listOf(
                        TripDaySchedule(
                            dayNumber = 1,
                            dayTitle = "$originCity to $dest Transit & Eco-Check-in",
                            activities = listOf(
                                TripActivity("08:00 AM", "Electric Transit Departure", "Depart from $originCity via high-speed electric rail or e-bus (Level Boarding)", "Train", true, 35, 250),
                                TripActivity("11:00 AM", "Step-Free Eco Stay Check-in", "Solar powered certified hotel accommodation with greywater recycling", "Hotel", true, 0, 0),
                                TripActivity("03:30 PM", "$dest Heritage & Nature Trail", "Pedestrianized zero-emission sightseeing zone & cultural center", "Walk", true, 0, 0)
                            )
                        ),
                        TripDaySchedule(
                            dayNumber = 2,
                            dayTitle = "$dest Eco-Exploration & Return to $originCity",
                            activities = listOf(
                                TripActivity("09:00 AM", "Botanical & Scenic Viewpoint", "Accessible paved paths with solar audio guides", "Walk", true, 0, 50),
                                TripActivity("04:30 PM", "Electric Return Coach to $originCity", "Return to $originCity with zero tailpipe emissions", "Train", true, 35, 250)
                            )
                        )
                    ),
                    transitOpt1Name = "🚆 Electric Train / E-Coach from $originCity",
                    transitOpt1Metrics = "₹250 • Level Boarding • 35g CO2",
                    transitOpt2Name = "⚡ AC Electric Bus Corridor",
                    transitOpt2Metrics = "₹350 • Zero Emission • 48g CO2",
                    transitOpt3Name = "🚗 Private Petrol Taxi",
                    transitOpt3Metrics = "₹3,400 • High Emissions • 2,600g CO2"
                )
            }
        }
    }
}
