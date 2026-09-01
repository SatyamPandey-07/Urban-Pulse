package com.urbanpulse.app

import android.os.Bundle
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import com.google.android.material.button.MaterialButton

class HotelOptimizerActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_hotel_optimizer)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        val btnDispatch = findViewById<MaterialButton>(R.id.btnDispatchShelter)
        val tvSurplus = findViewById<TextView>(R.id.tvSurplusAlert)
        val btnHvac = findViewById<MaterialButton>(R.id.btnApplyHvacEco)

        btnDispatch.setOnClickListener {
            tvSurplus.text = "Surplus Dispatched: Feeding India & Roti Bank alerted (16.5 kg diverted)."
            btnDispatch.isEnabled = false
            btnDispatch.text = "Alert Dispatched (Zero Waste Verified)"
            Toast.makeText(this, "Food shelter pickup requested. 16.5 kg saved from landfill.", Toast.LENGTH_LONG).show()
        }

        btnHvac.setOnClickListener {
            btnHvac.isEnabled = false
            btnHvac.text = "Eco Setpoint Active (26°C)"
            Toast.makeText(this, "Automated energy savings applied to East Wing.", Toast.LENGTH_SHORT).show()
        }
    }
}
