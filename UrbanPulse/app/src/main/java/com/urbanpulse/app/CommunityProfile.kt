package com.urbanpulse.app

data class CommunityProfile(
    val userId: String = "",
    val profileName: String = "",
    val profileTag: String = "",
    val bio: String = "",
    val bannerUrl: String? = null,
    val avatarUrl: String? = null
)
