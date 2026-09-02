package com.urbanpulse.app

data class ChatMessage(
    val message: String,
    val isUser: Boolean,
    val timestamp: Long = System.currentTimeMillis(),
    val isLoading: Boolean = false,
    val mcqQuestion: QuickMcqQuestion? = null,
    val generatedTrip: TripPlan? = null
)
