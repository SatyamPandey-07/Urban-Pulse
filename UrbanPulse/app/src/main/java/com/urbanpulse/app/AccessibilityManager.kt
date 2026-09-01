package com.urbanpulse.app

import android.content.Context
import android.content.SharedPreferences

class AccessibilityManager(context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences("AccessibilityPrefs", Context.MODE_PRIVATE)

    var isWheelchairModeEnabled: Boolean
        get() = prefs.getBoolean("key_wheelchair_mode", false)
        set(value) = prefs.edit().putBoolean("key_wheelchair_mode", value).apply()

    var isVisualAssistanceEnabled: Boolean
        get() = prefs.getBoolean("key_visual_assist", false)
        set(value) = prefs.edit().putBoolean("key_visual_assist", value).apply()

    var isHearingAssistanceEnabled: Boolean
        get() = prefs.getBoolean("key_hearing_assist", false)
        set(value) = prefs.edit().putBoolean("key_hearing_assist", value).apply()

    var isServiceAnimalFriendlyOnly: Boolean
        get() = prefs.getBoolean("key_service_animal", false)
        set(value) = prefs.edit().putBoolean("key_service_animal", value).apply()

    companion object {
        @Volatile
        private var instance: AccessibilityManager? = null

        fun getInstance(context: Context): AccessibilityManager {
            return instance ?: synchronized(this) {
                instance ?: AccessibilityManager(context.applicationContext).also { instance = it }
            }
        }
    }
}
