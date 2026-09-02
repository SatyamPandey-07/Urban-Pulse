package com.urbanpulse.app

import android.os.Bundle
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.card.MaterialCardView

class TripDetailActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_trip_detail)

        val toolbar = findViewById<MaterialToolbar>(R.id.toolbarTripDetail)
        toolbar.setNavigationOnClickListener { finish() }

        val trip = intent.getSerializableExtra("EXTRA_TRIP_PLAN") as? TripPlan
            ?: TripRepository.getTrips(this).firstOrNull()
            ?: return

        findViewById<TextView>(R.id.tvDetailTitle).text = trip.title
        findViewById<TextView>(R.id.tvDetailCo2Badge).text = "-${trip.co2SavedKg} kg CO2"
        findViewById<TextView>(R.id.tvDetailDates).text = "${trip.travelDates} • ${trip.durationDays} Days Trip"
        findViewById<TextView>(R.id.tvDetailMode).text = "🚆 ${trip.travelMode} • ♿ ${if (trip.isStepFreeAccessible) "100% Step-Free Concourse" else "Standard Concourse"}"

        findViewById<TextView>(R.id.tvDetailBudget).text = "₹${trip.totalBudgetInr}"
        findViewById<TextView>(R.id.tvDetailAqi).text = trip.aqiStatus
        findViewById<TextView>(R.id.tvDetailPoints).text = "+${trip.pulsePointsEarned} PULSE"

        findViewById<TextView>(R.id.tvDetailHotelName).text = trip.hotelName
        findViewById<TextView>(R.id.tvDetailHotelRating).text = "★ ${trip.hotelRating} / 5.0"

        // Dynamic Transit Comparison
        val dest = trip.destination.lowercase()
        val tvOpt1Name = findViewById<TextView>(R.id.tvTransitOpt1Name)
        val tvOpt1Metrics = findViewById<TextView>(R.id.tvTransitOpt1Metrics)
        val tvOpt2Name = findViewById<TextView>(R.id.tvTransitOpt2Name)
        val tvOpt2Metrics = findViewById<TextView>(R.id.tvTransitOpt2Metrics)
        val tvOpt3Name = findViewById<TextView>(R.id.tvTransitOpt3Name)
        val tvOpt3Metrics = findViewById<TextView>(R.id.tvTransitOpt3Metrics)

        if (dest.contains("kedar")) {
            tvOpt1Name?.text = "🚆 Mumbai-Haridwar Superfast + E-Shuttle"
            tvOpt1Metrics?.text = "₹1,450 • Level Boarding • 280g CO2"
            tvOpt2Name?.text = "⚡ AC Pilgrim Express Coach"
            tvOpt2Metrics?.text = "₹2,200 • AC Seater • 350g CO2"
            tvOpt3Name?.text = "🚗 Private Highway Diesel SUV Taxi"
            tvOpt3Metrics?.text = "₹18,500 • High Emissions • 24,000g CO2"
        } else if (dest.contains("alibaug")) {
            tvOpt1Name?.text = "🚢 M2M Electric Hybrid Ro-Pax Ferry"
            tvOpt1Metrics?.text = "₹380 • 1h 15m • 45g CO2"
            tvOpt2Name?.text = "⚡ Mandwa Electric Feeder Bus"
            tvOpt2Metrics?.text = "₹40 • 20m • 10g CO2"
            tvOpt3Name?.text = "🚗 Standard Petrol Taxi (via Pen)"
            tvOpt3Metrics?.text = "₹2,800 • 3h 30m • 1,900g CO2"
        } else if (dest.contains("manali")) {
            tvOpt1Name?.text = "🚆 Vande Bharat + HRTC E-Coach"
            tvOpt1Metrics?.text = "₹1,850 • Electric Transit • 310g CO2"
            tvOpt2Name?.text = "⚡ AC Electric Sleeper Coach"
            tvOpt2Metrics?.text = "₹2,400 • Overnight • 380g CO2"
            tvOpt3Name?.text = "🚗 Private Mountain Petrol Cab"
            tvOpt3Metrics?.text = "₹16,000 • Mountain Ghats • 22,000g CO2"
        } else {
            tvOpt1Name?.text = "🚆 Indrayani Electric Express"
            tvOpt1Metrics?.text = "₹75 • 2h 05m • 28g CO2"
            tvOpt2Name?.text = "⚡ MSRTC AC Shivneri E-Bus"
            tvOpt2Metrics?.text = "₹210 • 2h 20m • 54g CO2"
            tvOpt3Name?.text = "🚗 Standard Petrol Taxi"
            tvOpt3Metrics?.text = "₹3,200 • 2h 45m • 2,400g CO2"
        }

        val timelineContainer = findViewById<LinearLayout>(R.id.layoutTimelineContainer)
        timelineContainer.removeAllViews()

        val primaryColor = ContextCompat.getColor(this, R.color.primary_green)
        val textPrimaryColor = ContextCompat.getColor(this, R.color.text_primary)
        val textSecondaryColor = ContextCompat.getColor(this, R.color.text_secondary)
        val surfaceCardColor = ContextCompat.getColor(this, R.color.surface_card)

        for (day in trip.dailyItinerary) {
            // Day Header Card
            val headerView = TextView(this).apply {
                text = "DAY ${day.dayNumber}: ${day.dayTitle}"
                setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_TitleSmall)
                setTextColor(primaryColor)
                setPadding(0, 24, 0, 8)
                paint.isFakeBoldText = true
            }
            timelineContainer.addView(headerView)

            for (activity in day.activities) {
                val card = MaterialCardView(this).apply {
                    radius = 32f
                    strokeWidth = 0
                    setCardBackgroundColor(surfaceCardColor)
                    val lp = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT
                    ).apply {
                        setMargins(0, 0, 0, 16)
                    }
                    layoutParams = lp
                }

                val cardContent = LinearLayout(this).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(32, 24, 32, 24)
                }

                val rowTimeTitle = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                }

                val tvTime = TextView(this).apply {
                    text = activity.time
                    setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_LabelMedium)
                    setTextColor(primaryColor)
                    paint.isFakeBoldText = true
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT
                    ).apply {
                        marginEnd = 24
                    }
                }

                val tvTitle = TextView(this).apply {
                    text = activity.title
                    setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodyMedium)
                    setTextColor(textPrimaryColor)
                    paint.isFakeBoldText = true
                    layoutParams = LinearLayout.LayoutParams(
                        0,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        1f
                    )
                }

                rowTimeTitle.addView(tvTime)
                rowTimeTitle.addView(tvTitle)
                cardContent.addView(rowTimeTitle)

                val tvDesc = TextView(this).apply {
                    text = activity.description
                    setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_BodySmall)
                    setTextColor(textSecondaryColor)
                    setPadding(0, 8, 0, 8)
                }
                cardContent.addView(tvDesc)

                val rowMeta = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                }

                val tvMeta = TextView(this).apply {
                    text = "Mode: ${activity.transportType} • ${if (activity.isAccessible) "♿ Step-Free" else "Standard"} • ${activity.co2Grams}g CO2"
                    setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_LabelSmall)
                    setTextColor(primaryColor)
                    layoutParams = LinearLayout.LayoutParams(
                        0,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        1f
                    )
                }

                val tvCost = TextView(this).apply {
                    text = if (activity.costInr > 0) "₹${activity.costInr}" else "Included"
                    setTextAppearance(com.google.android.material.R.style.TextAppearance_Material3_LabelSmall)
                    setTextColor(textPrimaryColor)
                    paint.isFakeBoldText = true
                }

                rowMeta.addView(tvMeta)
                rowMeta.addView(tvCost)
                cardContent.addView(rowMeta)

                card.addView(cardContent)
                timelineContainer.addView(card)
            }
        }
    }
}
