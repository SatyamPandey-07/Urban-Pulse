package com.meenakshi.urbanpulse

import com.google.firebase.firestore.GeoPoint
import com.google.firebase.firestore.ServerTimestamp
import java.util.Date

data class Incident(
    val id: String = "",
    val type: String = "",
    val description: String = "",
    val imageUrl: String = "",
    val location: GeoPoint? = null,
    val userId: String = "",
    @ServerTimestamp val timestamp: Date? = null
)
