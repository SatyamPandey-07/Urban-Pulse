package com.meenakshi.urbanpulse

import android.content.Context
import android.content.SharedPreferences
import java.util.Calendar
import kotlin.math.pow

object GamificationManager {
    private const val PREF_NAME = "urbanpulse_game_prefs"
    private const val KEY_XP = "user_xp"
    private const val KEY_PULSE = "user_pulse"
    private const val KEY_LAST_LOGIN = "last_login_day"
    private const val KEY_STREAK = "current_streak"
    private const val KEY_CO2 = "co2_saved"

    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        checkDailyLogin()
    }

    // --- Progression ---
    fun getXp(): Long = prefs.getLong(KEY_XP, 0)
    
    fun getPulse(): Long = prefs.getLong(KEY_PULSE, 0)
    
    fun getLevel(): Int {
        val xp = getXp()
        // Exponential curve: Level = (XP / 1000) ^ 0.5 + 1 roughly, or simplistic steps
        // Using provided example: Level 2 needs 1000 XP.
        // Let's use: XP = 1000 * (Level - 1)^1.5
        // Level = (XP / 1000)^(1/1.5) + 1
        if (xp < 1000) return 1
        return (Math.pow(xp / 1000.0, 1.0/1.5) + 1).toInt()
    }
    
    fun getNextLevelXp(): Long {
        val nextLevel = getLevel() + 1
        // XP needed = 1000 * (nextLevel - 1)^1.5
        return (1000 * (nextLevel - 1).toDouble().pow(1.5)).toLong()
    }

    fun addXp(amount: Int) {
        val current = getXp()
        prefs.edit().putLong(KEY_XP, current + amount).apply()
        // Check for level up logic here if needed (toast, etc)
    }

    fun addPulse(amount: Int) {
        val current = getPulse()
        prefs.edit().putLong(KEY_PULSE, current + amount).apply()
    }
    
    fun spendPulse(amount: Int): Boolean {
        val current = getPulse()
        if (current >= amount) {
            prefs.edit().putLong(KEY_PULSE, current - amount).apply()
            return true
        }
        return false
    }

    // --- Streak ---
    fun getStreak(): Int = prefs.getInt(KEY_STREAK, 0)

    private fun checkDailyLogin() {
        val lastLoginDay = prefs.getInt(KEY_LAST_LOGIN, -1)
        val currentDay = Calendar.getInstance().get(Calendar.DAY_OF_YEAR)
        
        if (lastLoginDay == -1) {
            // First login
            prefs.edit().putInt(KEY_LAST_LOGIN, currentDay).putInt(KEY_STREAK, 1).apply()
        } else if (currentDay == lastLoginDay + 1) {
            // Streak continued
            val streak = getStreak() + 1
            prefs.edit().putInt(KEY_LAST_LOGIN, currentDay).putInt(KEY_STREAK, streak).apply()
            addXp(50) // Daily bonus
        } else if (currentDay > lastLoginDay + 1) {
            // Streak broken
             prefs.edit().putInt(KEY_LAST_LOGIN, currentDay).putInt(KEY_STREAK, 1).apply()
        }
    }
    
    // --- CO2 ---
    fun addCo2Saved(grams: Double) {
        val current = getCo2Saved()
        prefs.edit().putFloat(KEY_CO2, (current + grams).toFloat()).apply()
    }
    
    fun getCo2Saved(): Float = prefs.getFloat(KEY_CO2, 0f)

    // --- Challenges ---
    fun getActiveChallenges(): List<Challenge> {
        // Mock logic for now. In real app, fetch from Firestore or generate based on week
        return listOf(
            Challenge("ch1", "Walk 2,000 steps", "Daily", 2000, 0, 100, 10), // 100 XP, 10 Pulse
            Challenge("ch2", "Report 3 hazards", "Weekly", 3, 0, 500, 50)
        )
    }
}

data class Challenge(
    val id: String,
    val title: String,
    val type: String, // Daily, Weekly
    val target: Int,
    var progress: Int,
    val xpReward: Int,
    val pulseReward: Int
)
