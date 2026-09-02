package com.urbanpulse.app

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

object TripRepository {

    private const val PREF_NAME = "urbanpulse_trips"
    private const val KEY_TRIPS = "saved_trips_json"
    private val gson = Gson()

    private val defaultTrips = mutableListOf(
        TripPlan(
            id = "trip_lonavala_01",
            destination = "Lonavala",
            title = "Lonavala Monsoon Eco-Retreat",
            durationDays = 2,
            travelDates = "Sep 12 - Sep 14, 2026",
            travelMode = "Electric Express Train (Indrayani Exp)",
            co2SavedKg = 18.4,
            pulsePointsEarned = 250,
            isCompleted = false,
            hotelName = "The Machan Eco Resort (100% Solar)",
            hotelRating = 4.8,
            isStepFreeAccessible = true,
            totalBudgetInr = 4200,
            aqiStatus = "Clean Mountain Air (AQI 28)",
            transitCostInr = 150,
            dailyItinerary = listOf(
                TripDaySchedule(
                    dayNumber = 1,
                    dayTitle = "Scenic Ridge & Heritage Caves",
                    activities = listOf(
                        TripActivity("07:10 AM", "Indrayani Express Train", "Dadar to Lonavala (Electric Traction • Low Carbon)", "Train", true, 28, 75),
                        TripActivity("09:45 AM", "Step-Free Check-in", "The Machan Solar Treehouse Resort", "Hotel", true, 0, 0),
                        TripActivity("11:30 AM", "Karla Caves & E-Shuttle", "Ancient Buddhist caves with wheelchair accessible lower plaza", "E-Bus", true, 40, 50),
                        TripActivity("03:30 PM", "Bhushi Dam Eco Trail", "Zero-plastic walking corridor with rain harvest viewing", "Walk", true, 0, 0),
                        TripActivity("07:00 PM", "Farm-to-Fork Organic Dinner", "Locally sourced Maharashtrian millet cuisine", "Hotel", true, 10, 350)
                    )
                ),
                TripDaySchedule(
                    dayNumber = 2,
                    dayTitle = "Tiger Point & Sunset Valley",
                    activities = listOf(
                        TripActivity("08:30 AM", "Guided Nature Walk", "Ryewood Botanical Garden (Accessible Paved Trails)", "Walk", true, 0, 0),
                        TripActivity("12:00 PM", "Tiger's Leap Scenic Valley", "Electric shuttle to viewpoint with tactile edge safety", "E-Bus", true, 35, 60),
                        TripActivity("04:30 PM", "Lonavala Chikki Heritage Stop", "Traditional organic jaggery fudge workshop", "Walk", true, 0, 100),
                        TripActivity("06:15 PM", "Deccan Express Return", "Lonavala to Mumbai CSMT (Electric Rail)", "Train", true, 28, 75)
                    )
                )
            )
        ),
        TripPlan(
            id = "trip_alibaug_02",
            destination = "Alibaug",
            title = "Alibaug Coastal Low-Carbon Trail",
            durationDays = 1,
            travelDates = "Upcoming: Sep 20, 2026",
            travelMode = "Ro-Pax Electric Hybrid Ferry (Bhaucha Dhakka)",
            co2SavedKg = 12.2,
            pulsePointsEarned = 180,
            isCompleted = false,
            hotelName = "Radisson Blu Resort (LEED Gold)",
            hotelRating = 4.6,
            isStepFreeAccessible = true,
            totalBudgetInr = 2800,
            aqiStatus = "Pristine Coastal Breeze (AQI 34)",
            transitCostInr = 380,
            dailyItinerary = listOf(
                TripDaySchedule(
                    dayNumber = 1,
                    dayTitle = "Mandwa to Varsoli Coastal Loop",
                    activities = listOf(
                        TripActivity("08:00 AM", "M2M Ro-Pax Hybrid Ferry", "Ferry Wharf Mumbai to Mandwa Port (Level Boarding)", "Train", true, 45, 380),
                        TripActivity("10:00 AM", "Electric AC Feeder Bus", "Mandwa to Alibaug City Center", "E-Bus", true, 20, 35),
                        TripActivity("12:30 PM", "Kolaba Fort Low-Tide Walk", "Step-free viewing ramp & solar information kiosk", "Walk", true, 0, 50),
                        TripActivity("05:30 PM", "Varsoli Sunset & Organic Coconut Grove", "Locally preserved coastal mangrove walk", "Walk", true, 0, 0)
                    )
                )
            )
        ),
        TripPlan(
            id = "trip_mumbai_done_01",
            destination = "Mumbai Heritage",
            title = "South Mumbai Green & Art Deco Corridor",
            durationDays = 1,
            travelDates = "Completed: Aug 28, 2026",
            travelMode = "Metro Line 3 (Aqua Line Electric)",
            co2SavedKg = 6.8,
            pulsePointsEarned = 140,
            isCompleted = true,
            hotelName = "The Taj Mahal Palace (Green Key Certified)",
            hotelRating = 4.9,
            isStepFreeAccessible = true,
            totalBudgetInr = 650,
            aqiStatus = "Moderate Sea Breeze (AQI 58)",
            transitCostInr = 40,
            dailyItinerary = listOf(
                TripDaySchedule(
                    dayNumber = 1,
                    dayTitle = "Art Deco & Step-Free Promenade",
                    activities = listOf(
                        TripActivity("09:30 AM", "Metro Line 3 Underground", "BKC to Churchgate (100% Elevator & Tactile Paving)", "Metro", true, 12, 40),
                        TripActivity("11:00 AM", "CSMT Heritage Museum", "Audio-guided & ramp accessible gothic architecture", "Walk", true, 0, 50),
                        TripActivity("03:00 PM", "Marine Drive Low-Emission Walk", "Clean energy pedestrian zone", "Walk", true, 0, 0)
                    )
                )
            )
        )
    )

    fun getTrips(context: Context): List<TripPlan> {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val json = prefs.getString(KEY_TRIPS, null)
        return if (json != null) {
            try {
                val type = object : TypeToken<List<TripPlan>>() {}.type
                gson.fromJson(json, type)
            } catch (e: Exception) {
                defaultTrips
            }
        } else {
            saveTrips(context, defaultTrips)
            defaultTrips
        }
    }

    fun addTrip(context: Context, trip: TripPlan) {
        val list = getTrips(context).toMutableList()
        list.add(0, trip)
        saveTrips(context, list)
    }

    private fun saveTrips(context: Context, trips: List<TripPlan>) {
        val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val json = gson.toJson(trips)
        prefs.edit().putString(KEY_TRIPS, json).apply()
    }
}
