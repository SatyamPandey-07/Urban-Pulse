package com.urbanpulse.app

import android.content.Intent
import android.os.Bundle
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.slider.Slider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class HotelOptimizerActivity : AppCompatActivity() {

    private val totalRooms = 120
    private var currentOccupancyPercent = 75f
    private var isEcoHvacActive = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_hotel_optimizer)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        val slider = findViewById<Slider>(R.id.sliderOccupancy)
        val tvRoomLabel = findViewById<TextView>(R.id.tvRoomLabel)
        val tvCoversLabel = findViewById<TextView>(R.id.tvCoversLabel)
        val tvEnergyTotal = findViewById<TextView>(R.id.tvEnergyTotal)
        val tvEnergySaved = findViewById<TextView>(R.id.tvEnergySaved)
        val tvWaterTotal = findViewById<TextView>(R.id.tvWaterTotal)
        val tvFoodSurplus = findViewById<TextView>(R.id.tvFoodSurplus)
        val tvSurplusAlert = findViewById<TextView>(R.id.tvSurplusAlert)
        val tvHvacSummary = findViewById<TextView>(R.id.tvHvacSummary)

        val btnDispatch = findViewById<MaterialButton>(R.id.btnDispatchShelter)
        val btnHvac = findViewById<MaterialButton>(R.id.btnApplyHvacEco)
        val btnEsgReport = findViewById<MaterialButton>(R.id.btnGenerateEsgReport)

        fun recalculateMetrics(occPercent: Float) {
            currentOccupancyPercent = occPercent
            val occupiedRooms = (totalRooms * (occPercent / 100f)).toInt()
            val vacantRooms = totalRooms - occupiedRooms
            val covers = (occupiedRooms * 2.5).toInt()

            tvRoomLabel.text = "Occupied Rooms: $occupiedRooms / $totalRooms (${occPercent.toInt()}%)"
            tvCoversLabel.text = "Dining Covers: $covers"

            val baseEnergy = occupiedRooms * 14.2
            val hvacSavings = if (isEcoHvacActive) vacantRooms * 4.8 else vacantRooms * 1.5
            val totalEnergy = (baseEnergy + (vacantRooms * 3.0)).toInt()

            tvEnergyTotal.text = String.format("%,d", totalEnergy)
            tvEnergySaved.text = "▼ ${hvacSavings.toInt()} kWh saved"

            val waterTotal = (occupiedRooms * 185)
            tvWaterTotal.text = String.format("%,d", waterTotal)

            val surplusKg = String.format(Locale.US, "%.1f", covers * 0.076)
            tvFoodSurplus.text = surplusKg

            tvSurplusAlert.text = "Dinner Buffet Forecast: ~$surplusKg kg surplus meals ready for shelter pickup."
            tvHvacSummary.text = "Occupancy sensor: $vacantRooms vacant rooms detected. ${if (isEcoHvacActive) "26°C Eco setpoint active." else "Shift cooling to 26°C to save energy."}"
        }

        slider.addOnChangeListener { _, value, _ ->
            recalculateMetrics(value)
        }

        btnDispatch.setOnClickListener {
            val surplusKg = tvFoodSurplus.text.toString()
            tvSurplusAlert.text = "Dispatched: $surplusKg kg surplus food claimed by Roti Bank & Feeding India Mumbai. Driver en route."
            btnDispatch.isEnabled = false
            btnDispatch.text = "Shelter Dispatch Active"
            Toast.makeText(this, "Shelter alert sent! +200 XP toward Green Star Hotel Certification.", Toast.LENGTH_LONG).show()
        }

        btnHvac.setOnClickListener {
            isEcoHvacActive = true
            btnHvac.isEnabled = false
            btnHvac.text = "Eco Setpoint Active (26°C)"
            recalculateMetrics(currentOccupancyPercent)
            Toast.makeText(this, "Automated 26°C Eco Setpoint applied across all vacant wings!", Toast.LENGTH_LONG).show()
        }

        btnEsgReport.setOnClickListener {
            val occupiedRooms = (totalRooms * (currentOccupancyPercent / 100f)).toInt()
            val covers = (occupiedRooms * 2.5).toInt()
            val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date())

            val csvContent = """
                URBANPULSE ESG SUSTAINABILITY AUDIT SHEET
                Generated: $timestamp
                Property: The Orchid Eco-Heritage Resort & Conference Center
                
                --- METRIC BREAKDOWN ---
                Total Room Inventory: $totalRooms
                Active Occupancy: ${currentOccupancyPercent.toInt()}% ($occupiedRooms rooms occupied)
                Daily Dining Covers: $covers meals
                
                1. ENERGY INTELLIGENCE:
                   - Daily Energy Consumption: ${tvEnergyTotal.text} kWh
                   - Daily HVAC Power Avoided: ${tvEnergySaved.text}
                   - Renewable Solar Grid Share: 64.2%
                   
                2. WATER RECYCLING:
                   - Daily Potable Water: ${tvWaterTotal.text} Liters
                   - Greywater Recycling Rate: 88.4% (100% of landscape & flush)
                   
                3. FOOD WASTE DIVERSION:
                   - Surplus Food Diverted: ${tvFoodSurplus.text} kg
                   - Shelter Meals Provided: ${(covers * 0.076 * 2.5).toInt()} meals
                   - Landfill Diversion Rate: 100% (Zero Organic Waste to Landfill)
                   
                4. COMPLIANCE & ACCREDITATION:
                   - BEE (Bureau of Energy Efficiency) Rating: 4.8 / 5.0 Star
                   - LEED Status: Platinum Certified
                   - Single-Use Plastic Elimination: 100%
            """.trimIndent()

            AlertDialog.Builder(this)
                .setTitle("Verified ESG Compliance Sheet")
                .setMessage(csvContent)
                .setPositiveButton("Share / Save Document") { _, _ ->
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_SUBJECT, "UrbanPulse ESG Audit Sheet - $timestamp")
                        putExtra(Intent.EXTRA_TEXT, csvContent)
                    }
                    startActivity(Intent.createChooser(shareIntent, "Export ESG Audit Document"))
                }
                .setNegativeButton("Close", null)
                .show()
        }

        recalculateMetrics(75f)
    }
}
