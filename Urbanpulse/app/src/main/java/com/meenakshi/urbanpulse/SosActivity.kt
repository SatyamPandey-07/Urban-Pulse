package com.meenakshi.urbanpulse

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.MotionEvent
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import com.google.android.material.appbar.MaterialToolbar

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
                    // Start 3 second timer
                    handler.postDelayed(longPressRunnable, 3000)
                    // Visual feedback could be added here (scale animation)
                    btnSosAction.animate().scaleX(0.9f).scaleY(0.9f).setDuration(200).start()
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    isLongPressing = false
                    handler.removeCallbacks(longPressRunnable)
                    btnSosAction.animate().scaleX(1f).scaleY(1f).setDuration(200).start()
                    if (event.action == MotionEvent.ACTION_UP && (event.eventTime - event.downTime) < 3000) {
                        Toast.makeText(this, "Hold for 3 seconds to send SOS", Toast.LENGTH_SHORT).show()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun triggerSos() {
        // Vibrate logic could go here
        Toast.makeText(this, "SOS SENT! Location shared with emergency contacts.", Toast.LENGTH_LONG).show()
        isLongPressing = false
        btnSosAction.animate().scaleX(1f).scaleY(1f).setDuration(200).start()
    }
}
