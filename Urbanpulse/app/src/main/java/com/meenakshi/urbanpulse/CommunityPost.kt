package com.meenakshi.urbanpulse

import com.google.firebase.firestore.ServerTimestamp
import java.util.Date

data class CommunityPost(
    val id: String = "",
    val text: String = "",
    val imageUrl: String? = null,
    val userId: String = "",
    val userName: String = "",
    val userAvatarUrl: String? = null,
    @ServerTimestamp val timestamp: Date? = null,
    val likes: Int = 0
)
