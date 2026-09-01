package com.urbanpulse.app

import android.content.Intent
import android.os.Bundle
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.chip.ChipGroup

class ItineraryActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_itinerary)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        val chipGroupDuration = findViewById<ChipGroup>(R.id.chipGroupDuration)
        val btnGenerate = findViewById<MaterialButton>(R.id.btnGeneratePlan)
        val btnSave = findViewById<MaterialButton>(R.id.btnSaveItinerary)
        val tvCarbon = findViewById<TextView>(R.id.tvItineraryCarbon)
        val tvRewardBadge = findViewById<TextView>(R.id.tvRewardBadge)

        btnGenerate.setOnClickListener {
            val isWeekend = chipGroupDuration.checkedChipId == R.id.chipWeekend
            val isHalfDay = chipGroupDuration.checkedChipId == R.id.chipHalfDay

            if (isWeekend) {
                tvCarbon.text = "28.6 kg CO2e Avoided (92% cleaner than 2-day standard trip)"
                tvRewardBadge.text = "+250 PTS"
                btnSave.text = "Save Weekend Itinerary (+250 Pts)"
            } else if (isHalfDay) {
                tvCarbon.text = "8.2 kg CO2e Avoided (80% cleaner than 4h taxi tour)"
                tvRewardBadge.text = "+80 PTS"
                btnSave.text = "Save Half-Day Itinerary (+80 Pts)"
            } else {
                tvCarbon.text = "14.8 kg CO2e Avoided (86% cleaner than standard tour)"
                tvRewardBadge.text = "+120 PTS"
                btnSave.text = "Save Itinerary to Green Passport (+120 Pts)"
            }

            Toast.makeText(this, "Optimized green & inclusive itinerary generated!", Toast.LENGTH_SHORT).show()
        }

        btnSave.setOnClickListener {
            Toast.makeText(this, "Itinerary saved to your Green Travel Passport! +Points credited.", Toast.LENGTH_LONG).show()
            startActivity(Intent(this, CarbonWalletActivity::class.java))
        }
    }
}
