package com.urbanpulse.app

import java.io.Serializable

data class TripPlan(
    val id: String,
    val destination: String,
    val title: String,
    val durationDays: Int,
    val travelDates: String,
    val travelMode: String, // "Electric Express Train", "MSRTC E-Bus", "Shared EV"
    val co2SavedKg: Double,
    val pulsePointsEarned: Int,
    val isCompleted: Boolean,
    val hotelName: String,
    val hotelRating: Double,
    val isStepFreeAccessible: Boolean,
    val totalBudgetInr: Int,
    val aqiStatus: String, // "Good (AQI 32)", "Moderate (AQI 65)"
    val transitCostInr: Int,
    val dailyItinerary: List<TripDaySchedule>,
    val transitOpt1Name: String? = null,
    val transitOpt1Metrics: String? = null,
    val transitOpt2Name: String? = null,
    val transitOpt2Metrics: String? = null,
    val transitOpt3Name: String? = null,
    val transitOpt3Metrics: String? = null
) : Serializable

data class TripDaySchedule(
    val dayNumber: Int,
    val dayTitle: String,
    val activities: List<TripActivity>
) : Serializable

data class TripActivity(
    val time: String,
    val title: String,
    val description: String,
    val transportType: String, // "Metro", "Train", "E-Bus", "Walk", "Hotel"
    val isAccessible: Boolean,
    val co2Grams: Int,
    val costInr: Int
) : Serializable

data class QuickMcqQuestion(
    val questionId: String,
    val questionText: String,
    val options: List<String>
) : Serializable
