package com.urbanpulse.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.MotionEvent
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import java.util.Locale

class SosActivity : AppCompatActivity() {

    private lateinit var btnSosAction: AppCompatButton
    private val handler = Handler(Looper.getMainLooper())
    private var isLongPressing = false

    private val longPressRunnable = Runnable {
        if (isLongPressing) {
            triggerSos()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_sos)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        toolbar.setNavigationOnClickListener { finish() }

        btnSosAction = findViewById(R.id.btnSosAction)

        setupSosButton()
    }

    private fun setupSosButton() {
        btnSosAction.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    isLongPressing = true
                    handler.postDelayed(longPressRunnable, 3000)
                    btnSosAction.animate().scaleX(0.9f).scaleY(0.9f).setDuration(200).start()
                    vibrateBriefly(80)
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    isLongPressing = false
                    handler.removeCallbacks(longPressRunnable)
                    btnSosAction.animate().scaleX(1f).scaleY(1f).setDuration(200).start()
                    if (event.action == MotionEvent.ACTION_UP && (event.eventTime - event.downTime) < 3000) {
                        Toast.makeText(this, "Hold for 3 seconds to trigger Emergency SOS", Toast.LENGTH_SHORT).show()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun vibrateBriefly(durationMs: Long) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vibratorManager?.defaultVibrator?.vibrate(
                    VibrationEffect.createOneShot(durationMs, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else {
                @Suppress("DEPRECATION")
                val v = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                v?.vibrate(durationMs)
            }
        } catch (e: Exception) {
            // Ignore if vibration unsupported
        }
    }

    private fun triggerSos() {
        isLongPressing = false
        btnSosAction.animate().scaleX(1f).scaleY(1f).setDuration(200).start()

        // Continuous SOS pattern vibration: ... --- ...
        vibrateBriefly(600)

        val locMgr = UserLocationManager.getInstance(this)
        val lat = locMgr.currentLatitude
        val lon = locMgr.currentLongitude
        val city = locMgr.currentCityName
        val mapsUrl = "https://maps.google.com/?q=$lat,$lon"
        val message = "🚨 EMERGENCY SOS! I need immediate help near $city.\nMy live GPS location: $mapsUrl"

        val contactsManager = EmergencyContactsManager(this)
        val contacts = contactsManager.getContacts()

        // If emergency contacts exist, trigger SMS intent
        if (contacts.isNotEmpty()) {
            val phoneNumbers = contacts.joinToString(";") { it.number }
            try {
                val smsIntent = Intent(Intent.ACTION_SENDTO).apply {
                    data = Uri.parse("smsto:$phoneNumbers")
                    putExtra("sms_body", message)
                }
                startActivity(smsIntent)
            } catch (e: Exception) {
                // Fallback
            }
        }

        // Show emergency dialog
        MaterialAlertDialogBuilder(this)
            .setTitle("🚨 SOS TRIGGERED")
            .setMessage("Live GPS location locked at ($lat, $lon) in $city.\n\n$message\n\nChoose an emergency response action:")
            .setPositiveButton("Call 112 (National Emergency)") { _, _ ->
                val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:112"))
                startActivity(intent)
            }
            .setNeutralButton("Call 108 (Ambulance)") { _, _ ->
                val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:108"))
                startActivity(intent)
            }
            .setNegativeButton("Share GPS Link") { _, _ ->
                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, message)
                }
                startActivity(Intent.createChooser(shareIntent, "Share SOS Coordinates"))
            }
            .show()
    }
}
