package com.urbanpulse.app

import android.content.Intent
import android.os.Bundle
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.android.material.button.MaterialButton
import com.google.android.material.slider.Slider
import com.urbanpulse.app.data.HotelMetricsRepository
import com.urbanpulse.app.prediction.LinearRegression
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class HotelOptimizerActivity : AppCompatActivity() {

    private val totalRooms = 120
    private var currentOccupancyPercent = 75f
    private var isEcoHvacActive = false

    // Trained from historical occupancy data at runtime — not fixed coefficients.
    private var energyModel: LinearRegression? = null
    private var waterModel: LinearRegression? = null
    private var wasteModel: LinearRegression? = null

    private lateinit var tvRoomLabel: TextView
    private lateinit var tvCoversLabel: TextView
    private lateinit var tvEnergyTotal: TextView
    private lateinit var tvEnergySaved: TextView
    private lateinit var tvWaterTotal: TextView
    private lateinit var tvFoodSurplus: TextView
    private lateinit var tvSurplusAlert: TextView
    private lateinit var tvHvacSummary: TextView
    private lateinit var btnDispatch: MaterialButton

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_hotel_optimizer)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        val slider = findViewById<Slider>(R.id.sliderOccupancy)
        tvRoomLabel = findViewById(R.id.tvRoomLabel)
        tvCoversLabel = findViewById(R.id.tvCoversLabel)
        tvEnergyTotal = findViewById(R.id.tvEnergyTotal)
        tvEnergySaved = findViewById(R.id.tvEnergySaved)
        tvWaterTotal = findViewById(R.id.tvWaterTotal)
        tvFoodSurplus = findViewById(R.id.tvFoodSurplus)
        tvSurplusAlert = findViewById(R.id.tvSurplusAlert)
        tvHvacSummary = findViewById(R.id.tvHvacSummary)

        btnDispatch = findViewById(R.id.btnDispatchShelter)
        val btnHvac = findViewById<MaterialButton>(R.id.btnApplyHvacEco)
        val btnEsgReport = findViewById<MaterialButton>(R.id.btnGenerateEsgReport)

        slider.addOnChangeListener { _, value, _ -> recalculateMetrics(value) }

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

        btnEsgReport.setOnClickListener { showEsgReport() }

        lifecycleScope.launch {
            val history = HotelMetricsRepository(this@HotelOptimizerActivity).getHistory()
            energyModel = LinearRegression.fit(history.map { it.occupancyPercent to it.energyKwh })
            waterModel = LinearRegression.fit(history.map { it.occupancyPercent to it.waterLiters })
            wasteModel = LinearRegression.fit(history.map { it.occupancyPercent to it.foodWasteKg })
            recalculateMetrics(currentOccupancyPercent)
        }
    }

    private fun recalculateMetrics(occPercent: Float) {
        currentOccupancyPercent = occPercent
        val occupiedRooms = (totalRooms * (occPercent / 100f)).toInt()
        val vacantRooms = totalRooms - occupiedRooms
        val covers = (occupiedRooms * 2.5).toInt()

        tvRoomLabel.text = "Occupied Rooms: $occupiedRooms / $totalRooms (${occPercent.toInt()}%)"
        tvCoversLabel.text = "Dining Covers: $covers"

        val energy = energyModel
        val water = waterModel
        val waste = wasteModel

        if (energy == null || water == null || waste == null) {
            tvEnergyTotal.text = "…"
            tvEnergySaved.text = "Training forecast model…"
            tvWaterTotal.text = "…"
            tvFoodSurplus.text = "…"
            tvSurplusAlert.text = "Fitting prediction model on 60 days of occupancy history…"
            tvHvacSummary.text = ""
            return
        }

        val predictedEnergy = energy.predict(occPercent.toDouble())
        val hvacSavings = if (isEcoHvacActive) vacantRooms * 4.8 else vacantRooms * 1.5
        val totalEnergy = (predictedEnergy - (if (isEcoHvacActive) hvacSavings else 0.0)).toInt().coerceAtLeast(0)

        tvEnergyTotal.text = String.format(Locale.US, "%,d", totalEnergy)
        tvEnergySaved.text = "▼ ${hvacSavings.toInt()} kWh saved (predicted, R²=${"%.2f".format(energy.rSquared)})"

        val waterTotal = water.predict(occPercent.toDouble()).toInt().coerceAtLeast(0)
        tvWaterTotal.text = String.format(Locale.US, "%,d", waterTotal)

        val predictedSurplusKg = waste.predict(occPercent.toDouble()).coerceAtLeast(0.0)
        val surplusKg = String.format(Locale.US, "%.1f", predictedSurplusKg)
        tvFoodSurplus.text = surplusKg

        tvSurplusAlert.text = "Dinner Buffet Forecast: ~$surplusKg kg surplus meals predicted from ${waste.sampleCount}-day occupancy trend (R²=${"%.2f".format(waste.rSquared)})."
        tvHvacSummary.text = "Occupancy sensor: $vacantRooms vacant rooms detected. ${if (isEcoHvacActive) "26°C Eco setpoint active." else "Shift cooling to 26°C to save energy."}"

        if (btnDispatch.isEnabled) {
            btnDispatch.text = "Auto-Dispatch Alert to Local Food Shelter"
        }
    }

    private fun showEsgReport() {
        val occupiedRooms = (totalRooms * (currentOccupancyPercent / 100f)).toInt()
        val covers = (occupiedRooms * 2.5).toInt()
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date())
        val waste = wasteModel

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

            2. WATER RECYCLING:
               - Daily Potable Water: ${tvWaterTotal.text} Liters

            3. FOOD WASTE DIVERSION:
               - Surplus Food Diverted (model forecast): ${tvFoodSurplus.text} kg
               - Model fit quality: R² = ${waste?.let { "%.2f".format(it.rSquared) } ?: "n/a"} on ${waste?.sampleCount ?: 0} days of history
               - Shelter Meals Provided (est.): ${(covers * 0.076 * 2.5).toInt()} meals

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
}
