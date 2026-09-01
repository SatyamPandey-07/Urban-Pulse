package com.urbanpulse.app

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.widget.EditText
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.chip.ChipGroup
import com.urbanpulse.app.mobility.CarbonEstimator
import com.urbanpulse.app.mobility.MobilityOptimizer
import com.urbanpulse.app.mobility.MobilityOption
import com.urbanpulse.app.mobility.TradeoffPriority
import com.urbanpulse.app.mobility.TravelMode
import java.util.Locale
import kotlin.math.roundToInt

class GreenRoutePlannerActivity : AppCompatActivity() {

    private var selectedMode: TravelMode = TravelMode.METRO
    private var lastRanked: List<MobilityOption> = emptyList()
    private var lastPriority: TradeoffPriority = TradeoffPriority.ECO

    private lateinit var etOrigin: EditText
    private lateinit var etDest: EditText
    private lateinit var tvRankedHeader: TextView
    private lateinit var btnConfirm: MaterialButton

    private lateinit var cardByMode: Map<TravelMode, MaterialCardView>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_green_route_planner)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        etOrigin = findViewById(R.id.etOrigin)
        etDest = findViewById(R.id.etDestination)
        val btnRecalc = findViewById<MaterialButton>(R.id.btnRecalculateRoute)
        val btnUseGps = findViewById<MaterialButton>(R.id.btnUseGps)
        val chipGroupTradeoff = findViewById<ChipGroup>(R.id.chipGroupTradeoff)

        cardByMode = mapOf(
            TravelMode.WALK to findViewById(R.id.cardOptionWalk),
            TravelMode.CYCLE to findViewById(R.id.cardOptionCycle),
            TravelMode.METRO to findViewById(R.id.cardOptionMetro),
            TravelMode.BUS to findViewById(R.id.cardOptionBus),
            TravelMode.EV_CAB to findViewById(R.id.cardOptionEvCab),
            TravelMode.TAXI to findViewById(R.id.cardOptionTaxi)
        )

        tvRankedHeader = findViewById(R.id.tvRankedHeader)
        btnConfirm = findViewById(R.id.btnConfirmGreenRoute)

        btnUseGps.setOnClickListener {
            etOrigin.setText("My Real-time GPS Location (19.1775° N, 72.9544° E)")
            recalcAndRender()
            Toast.makeText(this, "Origin set to real-time GPS coordinates.", Toast.LENGTH_SHORT).show()
        }

        btnRecalc.setOnClickListener {
            recalcAndRender()
            val distanceKm = CarbonEstimator.estimateDistanceKm(etOrigin.text.toString(), etDest.text.toString())
            Toast.makeText(this, String.format(Locale.US, "Routes recalculated for a %.1f km trip.", distanceKm), Toast.LENGTH_SHORT).show()
        }

        val debounce = object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) { recalcAndRender() }
        }
        etOrigin.addTextChangedListener(debounce)
        etDest.addTextChangedListener(debounce)

        chipGroupTradeoff.setOnCheckedStateChangeListener { _, checkedIds ->
            lastPriority = when {
                checkedIds.contains(R.id.chipTradeoffStepFree) -> TradeoffPriority.STEP_FREE
                checkedIds.contains(R.id.chipTradeoffFastest) -> TradeoffPriority.FASTEST
                checkedIds.contains(R.id.chipTradeoffBudget) -> TradeoffPriority.BUDGET
                else -> TradeoffPriority.ECO
            }
            recalcAndRender()
        }

        cardByMode.forEach { (mode, card) -> card.setOnClickListener { selectMode(mode) } }

        btnConfirm.setOnClickListener { confirmJourney() }

        recalcAndRender()
    }

    /** Recomputes real distance/cost/carbon for every mode (including walk/cycle feasibility) and re-renders every card. */
    private fun recalcAndRender() {
        val accessMgr = AccessibilityManager.getInstance(this)
        val requireStepFree = accessMgr.isWheelchairModeEnabled || lastPriority == TradeoffPriority.STEP_FREE

        val distanceKm = CarbonEstimator.estimateDistanceKm(etOrigin.text.toString(), etDest.text.toString())
        val allOptions = CarbonEstimator.estimateAllModes(distanceKm)
        val ranked = MobilityOptimizer.rank(allOptions, lastPriority, requireStepFree)
        lastRanked = ranked

        val baselineCarbon = allOptions.first { it.mode == TravelMode.TAXI }.carbonGrams

        val priorityLabel = when (lastPriority) {
            TradeoffPriority.ECO -> "Lowest Carbon Impact"
            TradeoffPriority.STEP_FREE -> "100% Step-Free Accessibility"
            TradeoffPriority.FASTEST -> "Fastest Travel Time"
            TradeoffPriority.BUDGET -> "Lowest Cost"
            TradeoffPriority.BALANCED -> "Best Overall Balance"
        }
        tvRankedHeader.text = String.format(
            Locale.US, "Ranked Options (%s) • %.1f km trip", priorityLabel, distanceKm
        )

        allOptions.forEach { option -> renderOption(option, ranked) }

        val selectedIsUsable = allOptions.first { it.mode == selectedMode }.let {
            it.practical && (!requireStepFree || it.stepFreeAccessible)
        }
        if (!selectedIsUsable) {
            selectedMode = ranked.first().mode
        }
        highlightSelected()
        updateConfirmButton(baselineCarbon)
    }

    private data class OptionViewIds(val metrics: Int, val access: Int, val savings: Int, val badge: Int)

    private fun renderOption(option: MobilityOption, ranked: List<MobilityOption>) {
        val ids = when (option.mode) {
            TravelMode.WALK -> OptionViewIds(R.id.tvWalkMetrics, R.id.tvWalkAccessibility, R.id.tvWalkSavings, R.id.tvWalkBadge)
            TravelMode.CYCLE -> OptionViewIds(R.id.tvCycleMetrics, R.id.tvCycleAccessibility, R.id.tvCycleSavings, R.id.tvCycleBadge)
            TravelMode.METRO -> OptionViewIds(R.id.tvMetroMetrics, R.id.tvMetroAccessibility, R.id.tvMetroSavings, R.id.tvMetroBadge)
            TravelMode.BUS -> OptionViewIds(R.id.tvBusMetrics, R.id.tvBusAccessibility, R.id.tvBusSavings, R.id.tvBusBadge)
            TravelMode.EV_CAB -> OptionViewIds(R.id.tvEvCabMetrics, R.id.tvEvCabAccessibility, R.id.tvEvCabSavings, R.id.tvEvCabBadge)
            TravelMode.TAXI -> OptionViewIds(R.id.tvTaxiMetrics, R.id.tvTaxiAccessibility, R.id.tvTaxiSavings, R.id.tvTaxiBadge)
        }

        val metricsView = findViewById<TextView>(ids.metrics)
        val accessView = findViewById<TextView>(ids.access)
        val savingsView = findViewById<TextView>(ids.savings)
        val badgeView = findViewById<TextView>(ids.badge)

        if (!option.practical) {
            metricsView.text = String.format(Locale.US, "%.1f km • %s", option.distanceKm, option.impracticalReason ?: "Not practical for this distance")
            accessView.text = "Accessibility: ${option.accessibilityNote}"
            savingsView.text = "Choose a motorized option for this distance"
        } else {
            metricsView.text = if (option.carbonGrams > 0.0) {
                String.format(Locale.US, "%d mins • ₹%d • %.0fg CO2e per passenger", option.durationMin, option.fareRupees, option.carbonGrams)
            } else {
                String.format(Locale.US, "%d mins • ₹%d • 0g CO2e (zero-emission)", option.durationMin, option.fareRupees)
            }
            accessView.text = "Accessibility: ${option.accessibilityNote}"

            if (option.mode == TravelMode.TAXI) {
                savingsView.text = "Baseline high-emission reference"
            } else {
                val baseline = ranked.firstOrNull { it.mode == TravelMode.TAXI }?.carbonGrams
                    ?: CarbonEstimator.estimateOption(TravelMode.TAXI, option.distanceKm).carbonGrams
                val avoided = option.carbonAvoidedVsBaseline(baseline)
                val cleanerPct = if (baseline > 0) ((avoided / baseline) * 100).roundToInt() else 0
                savingsView.text = String.format(Locale.US, "CO2 Avoided vs Petrol Cab: -%.0fg (%d%% cleaner)", avoided, cleanerPct)
            }
        }

        val badgeText = MobilityOptimizer.badgeFor(option, ranked)
        badgeView.text = badgeText
        badgeView.setTextColor(
            Color.parseColor(
                when {
                    badgeText.contains("BEST MATCH") -> "#10B981"
                    badgeText.contains("GREENEST") -> "#10B981"
                    badgeText.contains("STEP-FREE") -> "#38BDF8"
                    badgeText.contains("FASTEST") -> "#F59E0B"
                    badgeText.contains("LOWEST FARE") -> "#10B981"
                    badgeText.contains("NOT PRACTICAL") -> "#94A3B8"
                    else -> "#64748B"
                }
            )
        )
    }

    private fun selectMode(mode: TravelMode) {
        val option = lastRanked.firstOrNull { it.mode == mode } ?: return
        if (!option.practical) {
            Toast.makeText(this, option.impracticalReason ?: "Not practical for this distance", Toast.LENGTH_SHORT).show()
            return
        }
        selectedMode = mode
        highlightSelected()
        val baseline = lastRanked.firstOrNull { it.mode == TravelMode.TAXI }?.carbonGrams ?: option.carbonGrams
        updateConfirmButton(baseline)
    }

    private fun highlightSelected() {
        cardByMode.forEach { (mode, card) ->
            if (mode == selectedMode) {
                card.strokeWidth = 4
                card.setStrokeColor(Color.parseColor("#10B981"))
            } else {
                card.strokeWidth = 0
            }
        }
    }

    private fun updateConfirmButton(baselineCarbon: Double) {
        val option = lastRanked.firstOrNull { it.mode == selectedMode } ?: return
        val avoided = option.carbonAvoidedVsBaseline(baselineCarbon)
        val credits = (avoided / 10.0).roundToInt().coerceAtLeast(0)
        btnConfirm.text = "Confirm ${option.mode.label} (+$credits Carbon Credits)"
    }

    private fun confirmJourney() {
        val allOptions = CarbonEstimator.estimateAllModes(
            CarbonEstimator.estimateDistanceKm(etOrigin.text.toString(), etDest.text.toString())
        )
        val option = allOptions.firstOrNull { it.mode == selectedMode } ?: return
        val baseline = allOptions.first { it.mode == TravelMode.TAXI }.carbonGrams
        val avoidedGrams = option.carbonAvoidedVsBaseline(baseline)
        val credits = (avoidedGrams / 10.0).roundToInt().coerceAtLeast(0)

        GamificationManager.addPulse(credits)
        GamificationManager.addCo2Saved(avoidedGrams)
        GamificationManager.addXp(credits * 2)

        Toast.makeText(
            this,
            String.format(Locale.US, "Journey started via %s! %.0fg CO2 avoided, +%d Carbon Credits earned.", option.mode.label, avoidedGrams, credits),
            Toast.LENGTH_LONG
        ).show()
        startActivity(Intent(this, CarbonWalletActivity::class.java))
    }
}
