package com.urbanpulse.app

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log

/**
 * Watches for three quick presses of the power button and raises an SOS.
 *
 * Android does not let apps read the power key itself; every press turns the
 * screen off or on, which Android announces with SCREEN_OFF / SCREEN_ON to
 * receivers registered at run time. So this foreground service (it has to stay
 * running for the receiver to exist) counts those: three within [WINDOW_MS],
 * no gap longer than [GAP_MS], is an SOS. Presses during a call are ignored
 * (the proximity sensor toggles the screen), and after an SOS there is a
 * [COOLDOWN_MS] pause so one burst of presses raises one SOS.
 */
class SosTriggerService : Service() {

    companion object {
        private const val TAG = "UrbanPulseSOS"
        private const val PREFS = "urbanpulse_sos"
        private const val KEY_ENABLED = "enabled"

        const val WINDOW_MS = 3000L
        const val GAP_MS = 1500L
        const val COOLDOWN_MS = 15000L

        @Volatile
        var running = false
            private set

        fun start(context: Context): Boolean {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, true).apply()
            return try {
                context.startForegroundService(Intent(context, SosTriggerService::class.java))
                true
            } catch (e: Exception) {
                Log.w(TAG, "could not start the power-button watch", e)
                false
            }
        }

        fun stop(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ENABLED, false).apply()
            context.stopService(Intent(context, SosTriggerService::class.java))
        }

        fun isEnabled(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENABLED, false)

        /** True when [times] (oldest first, milliseconds) is an intentional triple press. */
        fun isTriplePress(times: List<Long>): Boolean {
            if (times.size < 3) return false
            val last3 = times.takeLast(3)
            if (last3.last() - last3.first() > WINDOW_MS) return false
            return last3.zipWithNext().all { (a, b) -> b - a in 0..GAP_MS }
        }
    }

    private val presses = ArrayDeque<Long>()
    private var lastTrigger = 0L

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = onScreenToggle()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        SosNotifications.createChannels(this)
        goForeground()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(screenReceiver, filter)
        }
        running = true
        Log.i(TAG, "power-button SOS watch started")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        try {
            unregisterReceiver(screenReceiver)
        } catch (_: Exception) {
        }
        running = false
        super.onDestroy()
    }

    /** Location type when the app may use location (so the SOS gets a fix); special use otherwise. */
    private fun goForeground() {
        val n = SosNotifications.watching(this)
        if (Build.VERSION.SDK_INT < 29) {
            startForeground(SosNotifications.ID_WATCH, n)
            return
        }
        val location = SosBridge.hasLocationPermission(this)
        try {
            val type = if (location) ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION else specialUse()
            startForeground(SosNotifications.ID_WATCH, n, type)
        } catch (e: Exception) {
            Log.w(TAG, "location foreground service refused; watching without it", e)
            startForeground(SosNotifications.ID_WATCH, n, specialUse())
        }
    }

    private fun specialUse(): Int =
        if (Build.VERSION.SDK_INT >= 34) ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE else 0

    private fun onScreenToggle() {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (audio.mode == AudioManager.MODE_IN_CALL || audio.mode == AudioManager.MODE_IN_COMMUNICATION) {
            presses.clear()
            return
        }
        val now = SystemClock.elapsedRealtime()
        presses.addLast(now)
        while (presses.size > 3) presses.removeFirst()
        if (!isTriplePress(presses.toList())) return
        presses.clear()
        if (now - lastTrigger < COOLDOWN_MS) return
        lastTrigger = now
        fire()
    }

    private fun fire() {
        Log.i(TAG, "triple power press: raising SOS")
        vibrate()
        SosNotifications.showActive(this, "Sending your SOS…")
        // The Dart side may not be running (app closed): start it, then hand over.
        SosEngine.ensure(applicationContext)
        SosBridge.trigger("power_button")
    }

    private fun vibrate() {
        val v: Vibrator? = if (Build.VERSION.SDK_INT >= 31) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        v?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 400, 150, 400, 150, 700), -1))
    }
}
