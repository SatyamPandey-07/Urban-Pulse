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
