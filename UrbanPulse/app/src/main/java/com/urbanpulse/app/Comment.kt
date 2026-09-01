package com.urbanpulse.app

import com.google.firebase.firestore.ServerTimestamp
import java.util.Date

data class Comment(
    val id: String = "",
    val postId: String = "",
    val userId: String = "",
    val userName: String = "",
    val userAvatarUrl: String? = null,
    val text: String = "",
    @ServerTimestamp val timestamp: Date? = null
)
