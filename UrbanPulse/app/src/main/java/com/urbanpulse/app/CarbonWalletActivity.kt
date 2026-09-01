package com.urbanpulse.app

import android.os.Bundle
import android.view.View
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import com.google.android.material.button.MaterialButton
import com.urbanpulse.app.data.HospitalityRepository
import com.urbanpulse.app.evidence.ParetoOptimizer
import com.urbanpulse.app.mobility.CarbonEstimator
import com.urbanpulse.app.trip.TripPlanManager
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.roundToInt

class CarbonWalletActivity : BaseActivity() {

    private lateinit var tvCredits: TextView
    private lateinit var tvCo2Saved: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_carbon_wallet)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        tvCredits = findViewById(R.id.tvPulseCredits)
        tvCo2Saved = findViewById(R.id.tvTotalCo2Saved)
        val btnRedeemOrchid = findViewById<MaterialButton>(R.id.btnRedeemOrchid)
        val btnRedeemEv = findViewById<MaterialButton>(R.id.btnRedeemEv)

        refreshBalance()
        renderTripSummary()

        btnRedeemOrchid.setOnClickListener {
            if (GamificationManager.spendPulse(400)) {
                refreshBalance()
                btnRedeemOrchid.isEnabled = false
                btnRedeemOrchid.text = "Voucher Code: ORCHID-ECO-15"
                Toast.makeText(this, "Orchid Eco-Resort voucher unlocked! Saved to your profile.", Toast.LENGTH_LONG).show()
            } else {
                Toast.makeText(this, "Not enough PULSE credits yet — keep taking green trips!", Toast.LENGTH_SHORT).show()
            }
        }

        btnRedeemEv.setOnClickListener {
            if (GamificationManager.spendPulse(250)) {
                refreshBalance()
                btnRedeemEv.isEnabled = false
                btnRedeemEv.text = "Voucher Code: TATA-EV-FREE"
                Toast.makeText(this, "Free EV Charging voucher unlocked!", Toast.LENGTH_LONG).show()
            } else {
                Toast.makeText(this, "Not enough PULSE credits yet — keep taking green trips!", Toast.LENGTH_SHORT).show()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        refreshBalance()
        renderTripSummary()
    }

    private fun refreshBalance() {
        tvCredits.text = String.format(Locale.US, "%,d pts", GamificationManager.getPulse())
        val co2Kg = GamificationManager.getCo2Saved() / 1000.0
        tvCo2Saved.text = String.format(Locale.US, "%.1f kg", co2Kg)
    }

    /**
     * Scores the traveler's actual chosen stay + transport together against every
     * other stay×mode combination reachable at the same distance, instead of
     * showing the hospitality and mobility picks as two disconnected numbers.
     */
    private fun renderTripSummary() {
        val stay = TripPlanManager.getSelectedStay()
        val mobility = TripPlanManager.getSelectedMobility()
        val card = findViewById<View>(R.id.cardTripSummary)

        if (stay == null && mobility == null) {
            card.visibility = View.GONE
            return
        }
        card.visibility = View.VISIBLE

        findViewById<TextView>(R.id.tvTripStayLine).text = stay?.let {
            "🏨 Stay: ${it.name} — %.1f kg CO2e/night • ₹%d/night".format(Locale.US, it.carbonKgPerNight, it.priceRupees)
        } ?: "🏨 Stay: not yet chosen — pick one in Sustainable Stays"

        findViewById<TextView>(R.id.tvTripMobilityLine).text = mobility?.let {
            "🚌 Transport: ${it.modeLabel} — %.0fg CO2e • ₹%d".format(Locale.US, it.carbonGrams, it.fareRupees)
        } ?: "🚌 Transport: not yet chosen — pick a route in Green Journey Planner"

        val combinedCarbonKg = (stay?.carbonKgPerNight ?: 0.0) + (mobility?.carbonGrams ?: 0.0) / 1000.0
        val combinedCost = (stay?.priceRupees ?: 0) + (mobility?.fareRupees ?: 0)

        findViewById<TextView>(R.id.tvTripCombinedLine).text = String.format(
            Locale.US, "Combined footprint: %.1f kg CO2e • ₹%d total", combinedCarbonKg, combinedCost
        )

        val percentileView = findViewById<TextView>(R.id.tvTripPercentile)
        if (stay != null && mobility != null) {
            percentileView.visibility = View.VISIBLE
            percentileView.text = "Comparing against every other stay+route combination…"
            lifecycleScope.launch {
                val allStays = HospitalityRepository(this@CarbonWalletActivity).getAllStays()
                val allModes = CarbonEstimator.estimateAllModes(mobility.distanceKm.coerceAtLeast(1.5))

                val allCombinedCarbon = allStays.flatMap { s ->
                    allModes.map { m ->
                        parseCarbonKg(s.carbonFootprintPerNight) + m.carbonGrams / 1000.0
                    }
                }
                val beatenCount = allCombinedCarbon.count { it >= combinedCarbonKg }
                val percentile = if (allCombinedCarbon.isNotEmpty()) {
                    ((beatenCount.toDouble() / allCombinedCarbon.size) * 100).roundToInt()
                } else 0

                percentileView.text = "Greener than $percentile% of the ${allCombinedCarbon.size} possible stay+route combinations for this trip"
            }
        } else {
            percentileView.visibility = View.GONE
        }
    }

    private fun parseCarbonKg(text: String): Double = ParetoOptimizer.parseCarbon(text)
}
