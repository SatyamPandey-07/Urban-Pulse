package com.urbanpulse.app

import android.app.Activity
import android.content.Context

object ThemeUtils {
    private const val PREF_NAME = "app_prefs"
    private const val KEY_THEME_COLOR = "theme_color"

    fun saveThemeColor(context: Context, colorKey: String) {
        context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_THEME_COLOR, colorKey)
            .apply()
    }

    fun applyTheme(activity: Activity) {
        val prefs = activity.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val themeKey = prefs.getString(KEY_THEME_COLOR, "green") // Default green

        val themeId = when (themeKey) {
            "blue" -> R.style.Theme_Urbanpulse_Blue
            "purple" -> R.style.Theme_Urbanpulse_Purple
            "orange" -> R.style.Theme_Urbanpulse_Orange
            "pink" -> R.style.Theme_Urbanpulse_Pink
            "teal" -> R.style.Theme_Urbanpulse_Teal
            else -> R.style.Theme_Urbanpulse_Green
        }
        activity.setTheme(themeId)
    }
}
