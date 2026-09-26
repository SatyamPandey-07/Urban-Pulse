package com.urbanpulse.app

import android.content.Context
import android.content.SharedPreferences
import java.util.Calendar
import kotlin.math.pow
import kotlin.math.roundToInt

object GamificationManager {
    private const val PREF_NAME = "urbanpulse_game_prefs"
    private const val KEY_XP = "user_xp"
    private const val KEY_PULSE = "user_pulse"
    private const val KEY_LAST_LOGIN = "last_login_day"
    private const val KEY_STREAK = "current_streak"
    private const val KEY_CO2 = "co2_saved"
    private const val KEY_STEPS = "steps_count"
    private const val KEY_INCIDENTS = "incidents_reported_count"
    private const val KEY_TRANSIT = "transit_rides_count"
    private const val KEY_AI_QUESTIONS = "ai_questions_count"
    private const val KEY_WALLET = "web3_wallet_address"

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
        if (xp < 1000) return 1
        return (Math.pow(xp / 1000.0, 1.0/1.5) + 1).toInt()
    }
    
    fun getNextLevelXp(): Long {
        val nextLevel = getLevel() + 1
        return (1000 * (nextLevel - 1).toDouble().pow(1.5)).toLong()
    }

    fun addXp(amount: Int) {
        val current = getXp()
        prefs.edit().putLong(KEY_XP, current + amount).apply()
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
            prefs.edit().putInt(KEY_LAST_LOGIN, currentDay).putInt(KEY_STREAK, 1).apply()
        } else if (currentDay == lastLoginDay + 1) {
            val streak = getStreak() + 1
            prefs.edit().putInt(KEY_LAST_LOGIN, currentDay).putInt(KEY_STREAK, streak).apply()
            addXp(50)
            addPulse(10)
        } else if (currentDay > lastLoginDay + 1) {
            prefs.edit().putInt(KEY_LAST_LOGIN, currentDay).putInt(KEY_STREAK, 1).apply()
        }
    }
    
    // --- CO2 ---
    fun addCo2Saved(grams: Double) {
        val current = getCo2Saved()
        prefs.edit().putFloat(KEY_CO2, (current + grams).toFloat()).apply()
    }
    
    fun getCo2Saved(): Float = prefs.getFloat(KEY_CO2, 0f)

    // --- Activity Metrics ---
    fun addSteps(count: Int) {
        val current = getSteps()
        prefs.edit().putInt(KEY_STEPS, current + count).apply()
    }

    fun getSteps(): Int = prefs.getInt(KEY_STEPS, 0)

    fun incrementIncidentsReported() {
        val current = getIncidentsReported()
        prefs.edit().putInt(KEY_INCIDENTS, current + 1).apply()
        addXp(100)
        addPulse(25)
    }

    fun getIncidentsReported(): Int = prefs.getInt(KEY_INCIDENTS, 0)

    fun incrementTransitRides() {
        val current = getTransitRides()
        prefs.edit().putInt(KEY_TRANSIT, current + 1).apply()
        addXp(75)
        addPulse(15)
    }

    fun getTransitRides(): Int = prefs.getInt(KEY_TRANSIT, 0)

    fun incrementAiQuestions() {
        val current = getAiQuestions()
        prefs.edit().putInt(KEY_AI_QUESTIONS, current + 1).apply()
        addXp(10)
    }

    fun getAiQuestions(): Int = prefs.getInt(KEY_AI_QUESTIONS, 0)

    // --- Web3 Wallet ---
    fun getWalletAddress(): String? = prefs.getString(KEY_WALLET, null)

    fun setWalletAddress(address: String?) {
        prefs.edit().putString(KEY_WALLET, address).apply()
        if (!address.isNullOrBlank()) {
            addXp(200)
            addPulse(50)
        }
    }

    // --- Real Dynamic Challenges ---
    fun getActiveChallenges(): List<Challenge> {
        val steps = getSteps()
        val incidents = getIncidentsReported()
        val transit = getTransitRides()

        return listOf(
            Challenge(
                id = "ch1",
                title = "Walk 2,000 steps",
                type = "Daily",
                target = 2000,
                progress = steps.coerceAtMost(2000),
                xpReward = 100,
                pulseReward = 20
            ),
            Challenge(
                id = "ch2",
                title = "Report a road hazard or transit obstacle",
                type = "Weekly",
                target = 1,
                progress = incidents.coerceAtMost(1),
                xpReward = 250,
                pulseReward = 50
            ),
            Challenge(
                id = "ch3",
                title = "Take 3 public or electric transit rides",
                type = "Weekly",
                target = 3,
                progress = transit.coerceAtMost(3),
                xpReward = 300,
                pulseReward = 60
            )
        )
    }

    fun getAvailableChallenges(): List<Challenge> = getActiveChallenges()

    // --- Real Dynamic Badges ---
    fun getAllBadges(): List<Badge> {
        val co2Kg = (getCo2Saved() / 1000.0).roundToInt()
        val incidents = getIncidentsReported()
        val steps = getSteps()
        val aiQuestions = getAiQuestions()
        val isWalletLinked = !getWalletAddress().isNullOrBlank()

        return listOf(
            Badge(
                id = "b1",
                title = "Eco Pioneer",
                description = "Save 10kg of CO2 on public transit",
                iconRes = R.drawable.ic_fire,
                progress = co2Kg.coerceAtMost(10),
                target = 10
            ),
            Badge(
                id = "b2",
                title = "Urban Scout",
                description = "Report verified community incidents",
                iconRes = R.drawable.ic_location_pin,
                progress = incidents.coerceAtMost(3),
                target = 3
            ),
            Badge(
                id = "b3",
                title = "Active Commuter",
                description = "Walk 10,000 steps in low-emission zones",
                iconRes = R.drawable.ic_dashboard,
                progress = steps.coerceAtMost(10000),
                target = 10000
            ),
            Badge(
                id = "b4",
                title = "AI Navigator",
                description = "Plan journeys with Yatri AI",
                iconRes = R.drawable.ic_yatri_ai,
                progress = aiQuestions.coerceAtMost(5),
                target = 5
            ),
            Badge(
                id = "b5",
                title = "Web3 Pulse Pioneer",
                description = "Link Carbon Pulse Wallet",
                iconRes = R.drawable.ic_settings,
                progress = if (isWalletLinked) 1 else 0,
                target = 1
            )
        )
    }
}

data class Challenge(
    val id: String,
    val title: String,
    val type: String,
    val target: Int,
    var progress: Int,
    val xpReward: Int,
    val pulseReward: Int
)

data class Badge(
    val id: String,
    val title: String,
    val description: String,
    val iconRes: Int,
    val progress: Int,
    val target: Int
)
