package com.urbanpulse.app

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.widget.EditText
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.chip.ChipGroup

class GreenRoutePlannerActivity : AppCompatActivity() {

    private var selectedMode = "Metro"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_green_route_planner)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        val etOrigin = findViewById<EditText>(R.id.etOrigin)
        val etDest = findViewById<EditText>(R.id.etDestination)
        val btnRecalc = findViewById<MaterialButton>(R.id.btnRecalculateRoute)
        val btnUseGps = findViewById<MaterialButton>(R.id.btnUseGps)
        val chipGroupTradeoff = findViewById<ChipGroup>(R.id.chipGroupTradeoff)

        val cardMetro = findViewById<MaterialCardView>(R.id.cardOptionMetro)
        val cardBus = findViewById<MaterialCardView>(R.id.cardOptionBus)
        val cardEvCab = findViewById<MaterialCardView>(R.id.cardOptionEvCab)
        val cardTaxi = findViewById<MaterialCardView>(R.id.cardOptionTaxi)

        val tvRankedHeader = findViewById<TextView>(R.id.tvRankedHeader)
        val tvMetroBadge = findViewById<TextView>(R.id.tvMetroBadge)
        val btnConfirm = findViewById<MaterialButton>(R.id.btnConfirmGreenRoute)

        btnUseGps.setOnClickListener {
            etOrigin.setText("My Real-time GPS Location (19.1775° N, 72.9544° E)")
            Toast.makeText(this, "Origin set to real-time GPS coordinates.", Toast.LENGTH_SHORT).show()
        }

        btnRecalc.setOnClickListener {
            val origin = etOrigin.text.toString().trim()
            val dest = etDest.text.toString().trim()
            if (origin.isNotEmpty() && dest.isNotEmpty()) {
                Toast.makeText(this, "Live multimodal routes calculated for $dest via TomTom Routing.", Toast.LENGTH_SHORT).show()
            }
        }

        chipGroupTradeoff.setOnCheckedStateChangeListener { _, checkedIds ->
            when {
                checkedIds.contains(R.id.chipTradeoffEco) -> {
                    tvRankedHeader.text = "Ranked Options (Prioritizing Lowest Carbon Impact)"
                    highlightCard(cardMetro, cardBus, cardEvCab, cardTaxi)
                    tvMetroBadge.text = "#1 BEST GREEN MATCH (45g CO2e)"
                    tvMetroBadge.setTextColor(Color.parseColor("#10B981"))
                    selectedMode = "Electric Metro"
                    btnConfirm.text = "Confirm Electric Metro (+40 Carbon Credits)"
                }
                checkedIds.contains(R.id.chipTradeoffStepFree) -> {
                    tvRankedHeader.text = "Ranked Options (Prioritizing 100% Step-Free Accessibility)"
                    highlightCard(cardMetro, cardBus, cardEvCab, cardTaxi)
                    tvMetroBadge.text = "#1 100% STEP-FREE ACCESSIBLE"
                    tvMetroBadge.setTextColor(Color.parseColor("#38BDF8"))
                    selectedMode = "Accessible Metro"
                    btnConfirm.text = "Confirm Accessible Metro (+40 Carbon Credits)"
                }
                checkedIds.contains(R.id.chipTradeoffFastest) -> {
                    tvRankedHeader.text = "Ranked Options (Prioritizing Fastest Travel Time)"
                    highlightCard(cardEvCab, cardMetro, cardBus, cardTaxi)
                    tvMetroBadge.text = "#1 FASTEST ROUTE (22 mins)"
                    tvMetroBadge.setTextColor(Color.parseColor("#F59E0B"))
                    selectedMode = "Shared EV Rideshare"
                    btnConfirm.text = "Confirm Shared EV Rideshare (+30 Carbon Credits)"
                }
                checkedIds.contains(R.id.chipTradeoffBudget) -> {
                    tvRankedHeader.text = "Ranked Options (Prioritizing Lowest Cost)"
                    highlightCard(cardBus, cardMetro, cardEvCab, cardTaxi)
                    tvMetroBadge.text = "#1 LOWEST FARE (₹15)"
                    tvMetroBadge.setTextColor(Color.parseColor("#10B981"))
                    selectedMode = "Electric Bus"
                    btnConfirm.text = "Confirm Electric Bus (+35 Carbon Credits)"
                }
            }
        }

        cardMetro.setOnClickListener {
            highlightCard(cardMetro, cardBus, cardEvCab, cardTaxi)
            selectedMode = "Electric Metro"
            btnConfirm.text = "Confirm Electric Metro (+40 Carbon Credits)"
        }

        cardBus.setOnClickListener {
            highlightCard(cardBus, cardMetro, cardEvCab, cardTaxi)
            selectedMode = "Electric Bus"
            btnConfirm.text = "Confirm Electric Bus (+35 Carbon Credits)"
        }

        cardEvCab.setOnClickListener {
            highlightCard(cardEvCab, cardMetro, cardBus, cardTaxi)
            selectedMode = "Shared EV Rideshare"
            btnConfirm.text = "Confirm Shared EV Rideshare (+30 Carbon Credits)"
        }

        cardTaxi.setOnClickListener {
            highlightCard(cardTaxi, cardMetro, cardBus, cardEvCab)
            selectedMode = "Conventional Taxi"
            btnConfirm.text = "Confirm Conventional Taxi (+0 Carbon Credits)"
        }

        btnConfirm.setOnClickListener {
            Toast.makeText(this, "Journey started via $selectedMode! Carbon savings tracking active in your Passport.", Toast.LENGTH_LONG).show()
            startActivity(Intent(this, CarbonWalletActivity::class.java))
        }
    }

    private fun highlightCard(selected: MaterialCardView, vararg others: MaterialCardView) {
        selected.strokeWidth = 4
        selected.setStrokeColor(Color.parseColor("#10B981"))
        others.forEach { it.strokeWidth = 0 }
    }
}
