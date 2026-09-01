package com.urbanpulse.app

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.chip.ChipGroup
import com.urbanpulse.app.data.ExperienceRepository
import com.urbanpulse.app.evidence.ExperienceOptimizer
import com.urbanpulse.app.evidence.ParetoOptimizer
import com.urbanpulse.app.evidence.RankedExperience
import com.urbanpulse.app.intent.TripIntent
import com.urbanpulse.app.intent.TripIntentParser
import com.urbanpulse.app.trip.SelectedExperiences
import com.urbanpulse.app.trip.TripPlanManager
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.roundToInt

class ItineraryActivity : AppCompatActivity() {

    private var allRanked: List<RankedExperience> = emptyList()
    private var lastGenerated: List<RankedExperience> = emptyList()
    private var keywordFilter: String = ""

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_itinerary)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        val chipGroupDuration = findViewById<ChipGroup>(R.id.chipGroupDuration)
        val chipGroupPersona = findViewById<ChipGroup>(R.id.chipGroupPersona)
        val btnGenerate = findViewById<MaterialButton>(R.id.btnGeneratePlan)
        val btnSave = findViewById<MaterialButton>(R.id.btnSaveItinerary)
        val tvCarbon = findViewById<TextView>(R.id.tvItineraryCarbon)
        val tvRewardBadge = findViewById<TextView>(R.id.tvRewardBadge)
        val timelineContainer = findViewById<LinearLayout>(R.id.timelineContainer)
        val tvEmptyTimeline = findViewById<TextView>(R.id.tvEmptyTimeline)

        lifecycleScope.launch {
            val experiences = ExperienceRepository(this@ItineraryActivity).getAllExperiences()
            allRanked = ExperienceOptimizer.rank(experiences)
        }

        val etIntent = findViewById<EditText>(R.id.etItineraryIntent)
        val tvIntentSummary = findViewById<TextView>(R.id.tvItineraryIntentSummary)
        findViewById<MaterialButton>(R.id.btnApplyItineraryIntent).setOnClickListener {
            val text = etIntent.text.toString()
            if (text.isBlank()) return@setOnClickListener
            lifecycleScope.launch {
                val parsed = TripIntentParser.parse(text, BuildConfig.GEMINI_API_KEY)
                applyTripIntent(parsed, chipGroupPersona, tvIntentSummary)
            }
        }

        btnGenerate.setOnClickListener {
            generateItinerary(chipGroupDuration, chipGroupPersona, tvCarbon, tvRewardBadge, timelineContainer, tvEmptyTimeline)
        }

        btnSave.setOnClickListener {
            if (lastGenerated.isEmpty()) {
                Toast.makeText(this, "Generate an itinerary first.", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            saveItinerary()
        }
    }

    private fun applyTripIntent(intent: TripIntent, chipGroupPersona: ChipGroup, summaryView: TextView) {
        if (intent.requireWheelchairAccess) {
            AccessibilityManager.getInstance(this).isWheelchairModeEnabled = true
        }

        val chipId = when {
            intent.requireWheelchairAccess || intent.prioritizeAccessibility -> R.id.chipPersonaWheelchair
            intent.requireZeroWaste -> R.id.chipPersonaFarmToFork
            else -> R.id.chipPersonaHeritage
        }
        chipGroupPersona.check(chipId)
        keywordFilter = intent.searchKeywords

        val appliedBits = mutableListOf<String>()
        if (intent.requireWheelchairAccess) appliedBits += "wheelchair access required"
        if (intent.requireZeroWaste) appliedBits += "zero-waste / organic preferred"
        if (intent.maxPriceRupees != null) appliedBits += "budget under ₹${intent.maxPriceRupees}"

        summaryView.visibility = View.VISIBLE
        summaryView.text = "Parsed via ${if (intent.parsedBy == "gemini") "Gemini" else "keyword rules"}" +
            if (appliedBits.isNotEmpty()) " — ${appliedBits.joinToString(", ")}" else ""
    }

    private fun generateItinerary(
        chipGroupDuration: ChipGroup,
        chipGroupPersona: ChipGroup,
        tvCarbon: TextView,
        tvRewardBadge: TextView,
        timelineContainer: LinearLayout,
        tvEmptyTimeline: TextView
    ) {
        if (allRanked.isEmpty()) {
            Toast.makeText(this, "Still loading the experience catalog…", Toast.LENGTH_SHORT).show()
            return
        }

        val slotCount = when (chipGroupDuration.checkedChipId) {
            R.id.chipHalfDay -> 1
            R.id.chipWeekend -> 3
            else -> 2 // Full-Day
        }

        val wheelchairMode = AccessibilityManager.getInstance(this).isWheelchairModeEnabled
        var candidatePool = allRanked

        if (keywordFilter.isNotBlank()) {
            val kw = keywordFilter.lowercase()
            val keywordMatches = candidatePool.filter {
                it.experience.name.lowercase().contains(kw) || it.experience.category.lowercase().contains(kw)
            }
            if (keywordMatches.isNotEmpty()) candidatePool = keywordMatches
        }

        candidatePool = when (chipGroupPersona.checkedChipId) {
            R.id.chipPersonaFarmToFork -> candidatePool.filter {
                it.experience.category.contains("Culinary", true) || it.experience.sustainabilityPractice.contains("farm", true) || it.experience.sustainabilityPractice.contains("organic", true)
            }.ifEmpty { candidatePool }
            R.id.chipPersonaHeritage -> candidatePool.filter {
                it.experience.category.contains("Heritage", true) || it.experience.category.contains("Cultural", true)
            }.ifEmpty { candidatePool }
            else -> candidatePool // wheelchair persona keeps the full pool, filtered by accessibility below
        }

        if (chipGroupPersona.checkedChipId == R.id.chipPersonaWheelchair || wheelchairMode) {
            candidatePool = candidatePool.filter { it.experience.accessibilityRating >= 90 }.ifEmpty { candidatePool }
        }

        val selected = candidatePool.take(slotCount)
        lastGenerated = selected

        renderTimeline(selected, timelineContainer, tvEmptyTimeline)
        renderImpactSummary(selected, tvCarbon, tvRewardBadge)

        Toast.makeText(this, "Optimized green & inclusive itinerary generated from ${allRanked.size} real listings!", Toast.LENGTH_SHORT).show()
    }

    private fun renderTimeline(selected: List<RankedExperience>, container: LinearLayout, emptyView: TextView) {
        container.removeAllViews()
        emptyView.visibility = if (selected.isEmpty()) View.VISIBLE else View.GONE

        val startHour = 9
        val hoursPerSlot = 24 / (selected.size.coerceAtLeast(1) * 2).coerceAtMost(8)

        val density = resources.displayMetrics.density
        val surfaceColor = resolveThemeColor(com.google.android.material.R.attr.colorSurfaceContainerLow)
        val primaryColor = resolveThemeColor(com.google.android.material.R.attr.colorPrimary)
        val onSurfaceColor = resolveThemeColor(android.R.attr.textColorPrimary)

        selected.forEachIndexed { index, ranked ->
            val exp = ranked.experience
            val hour = (startHour + index * (hoursPerSlot.coerceAtLeast(2))) % 24
            val amPm = if (hour < 12) "AM" else "PM"
            val displayHour = if (hour % 12 == 0) 12 else hour % 12

            val card = MaterialCardView(this).apply {
                layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                    bottomMargin = (10 * density).toInt()
                }
                radius = 20 * density
                setCardBackgroundColor(surfaceColor)
                cardElevation = 0f
                strokeWidth = 0
            }
            val inner = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                val pad = (16 * density).toInt()
                setPadding(pad, pad, pad, pad)
            }

            val title = TextView(this).apply {
                text = String.format(Locale.US, "%02d:00 %s • %s", displayHour, amPm, exp.name)
                setTextColor(primaryColor)
                textSize = 14f
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            }
            val badgeLine = if (ranked.badges.isNotEmpty()) " 🏆 " + ranked.badges.joinToString(" • ") { it.label } else ""
            val detail = TextView(this).apply {
                text = "${exp.location} — ${exp.sustainabilityPractice}.$badgeLine\n" +
                    String.format(Locale.US, "%s • %.1fh • %s", exp.carbonFootprintPerVisit, exp.durationHours, exp.pricePerPerson)
                textSize = 12f
                setTextColor(onSurfaceColor)
                setPadding(0, (4 * density).toInt(), 0, 0)
            }

            inner.addView(title)
            inner.addView(detail)
            card.addView(inner)
            container.addView(card)
        }
    }

    private fun resolveThemeColor(attr: Int): Int {
        val typedValue = android.util.TypedValue()
        theme.resolveAttribute(attr, typedValue, true)
        return typedValue.data
    }

    private fun renderImpactSummary(selected: List<RankedExperience>, tvCarbon: TextView, tvRewardBadge: TextView) {
        if (selected.isEmpty()) {
            tvCarbon.text = "No experiences match these filters yet."
            tvRewardBadge.text = "+0 PTS"
            return
        }

        val totalCarbonKg = selected.sumOf { ParetoOptimizer.parseCarbon(it.experience.carbonFootprintPerVisit) }
        val categoryAverage = 1.4 // matches ExperienceRepository's category-average reference point
        val baselineCarbonKg = categoryAverage * selected.size
        val avoidedKg = (baselineCarbonKg - totalCarbonKg).coerceAtLeast(0.0)
        val cleanerPct = if (baselineCarbonKg > 0) ((avoidedKg / baselineCarbonKg) * 100).roundToInt() else 0
        val credits = (avoidedKg * 20).roundToInt().coerceAtLeast(0)

        tvCarbon.text = String.format(
            Locale.US, "%.1f kg CO2e Avoided (%d%% cleaner than the category average for %d stop(s))", avoidedKg, cleanerPct, selected.size
        )
        tvRewardBadge.text = "+$credits PTS"
    }

    private fun saveItinerary() {
        val totalCarbonKg = lastGenerated.sumOf { ParetoOptimizer.parseCarbon(it.experience.carbonFootprintPerVisit) }
        val totalPrice = lastGenerated.sumOf { ParetoOptimizer.parsePrice(it.experience.pricePerPerson).toInt() }
        val categoryAverage = 1.4
        val avoidedKg = (categoryAverage * lastGenerated.size - totalCarbonKg).coerceAtLeast(0.0)
        val credits = (avoidedKg * 20).roundToInt().coerceAtLeast(0)

        TripPlanManager.setSelectedExperiences(
            SelectedExperiences(
                names = lastGenerated.map { it.experience.name },
                totalCarbonKg = totalCarbonKg,
                totalPriceRupees = totalPrice
            )
        )

        GamificationManager.addPulse(credits)
        GamificationManager.addCo2Saved(avoidedKg * 1000.0)
        GamificationManager.addXp(credits * 2)

        Toast.makeText(this, "Itinerary saved to your Green Travel Passport! +$credits Pts credited.", Toast.LENGTH_LONG).show()
        startActivity(Intent(this, CarbonWalletActivity::class.java))
    }
}
