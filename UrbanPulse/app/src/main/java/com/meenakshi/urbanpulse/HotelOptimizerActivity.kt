package com.meenakshi.urbanpulse

import android.os.Bundle
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import com.google.android.material.button.MaterialButton

class HotelOptimizerActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_hotel_optimizer)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        val btnDispatch = findViewById<MaterialButton>(R.id.btnDispatchShelter)
        val btnHvac = findViewById<MaterialButton>(R.id.btnApplyHvacEco)
        val btnEsgReport = findViewById<MaterialButton>(R.id.btnGenerateEsgReport)
        val tvSurplusAlert = findViewById<TextView>(R.id.tvSurplusAlert)

        btnDispatch.setOnClickListener {
            tvSurplusAlert.text = "Dispatched: 16.5 kg surplus food claimed by Roti Bank & Feeding India Mumbai. Driver en route."
            btnDispatch.isEnabled = false
            btnDispatch.text = "Shelter Dispatch Active"
            Toast.makeText(this, "Shelter alert sent! +200 XP toward Green Star Hotel Certification.", Toast.LENGTH_LONG).show()
        }

        btnHvac.setOnClickListener {
            btnHvac.isEnabled = false
            btnHvac.text = "Eco Setpoint Active (26°C)"
            Toast.makeText(this, "HVAC schedule updated for 42 vacant rooms in East Wing. Saving 180 kWh/day.", Toast.LENGTH_LONG).show()
        }

        btnEsgReport.setOnClickListener {
            val reportMessage = """
                HOTEL SUSTAINABILITY & ESG AUDIT SUMMARY
                Property: The Orchid Eco-Heritage Resort
                Period: Current Month (Trailing 30 Days)
                
                • Carbon Avoided: 4.8 tons CO2e
                • Renewable Energy Mix: 64.2% (Solar Grid + Biogas)
                • Greywater Recycling Rate: 88.4% (100% of landscape use)
                • Food Surplus Diverted: 252 kg (630 shelter meals served)
                • Single-Use Plastic: 0% (Plastic Free Certified)
                • Bureau of Energy Efficiency (BEE) Score: 4.8 / 5.0
                • LEED Status: Platinum Certified
                
                Audit sheet generated & signed for compliance submission.
            """.trimIndent()

            AlertDialog.Builder(this)
                .setTitle("Verified ESG Compliance Report")
                .setMessage(reportMessage)
                .setPositiveButton("Export CSV / PDF") { _, _ ->
                    Toast.makeText(this, "ESG Audit summary exported to device storage.", Toast.LENGTH_LONG).show()
                }
                .setNegativeButton("Close", null)
                .show()
        }
    }
}
