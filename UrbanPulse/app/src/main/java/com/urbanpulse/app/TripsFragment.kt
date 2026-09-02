package com.urbanpulse.app

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.fragment.app.Fragment
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView

class TripsFragment : Fragment() {

    private lateinit var layoutUpcomingTripsContainer: LinearLayout
    private lateinit var layoutPastTripsContainer: LinearLayout
    private lateinit var tvTotalCo2Avoided: TextView
    private lateinit var tvActiveTripsCount: TextView

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_trips, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        layoutUpcomingTripsContainer = view.findViewById(R.id.layoutUpcomingTripsContainer)
        layoutPastTripsContainer = view.findViewById(R.id.layoutPastTripsContainer)
        tvTotalCo2Avoided = view.findViewById(R.id.tvTotalCo2Avoided)
        tvActiveTripsCount = view.findViewById(R.id.tvActiveTripsCount)

        loadTrips()

        view.findViewById<MaterialButton>(R.id.btnPlanWithAi).setOnClickListener {
            (activity as? MainActivity)?.switchToTab(3)
        }

        view.findViewById<MaterialButton>(R.id.btnQuickLonavala).setOnClickListener {
            val trip = TripRepository.getTrips(requireContext()).firstOrNull { it.destination.contains("Lonavala", true) }
            if (trip != null) {
                openTripDetail(trip)
            } else {
                (activity as? MainActivity)?.switchToTab(3)
            }
        }

        view.findViewById<MaterialButton>(R.id.btnQuickAlibaug).setOnClickListener {
            val trip = TripRepository.getTrips(requireContext()).firstOrNull { it.destination.contains("Alibaug", true) }
            if (trip != null) {
                openTripDetail(trip)
            } else {
                (activity as? MainActivity)?.switchToTab(3)
            }
        }

        view.findViewById<MaterialButton>(R.id.btnQuickMatheran).setOnClickListener {
            (activity as? MainActivity)?.switchToTab(3)
        }
    }

    override fun onResume() {
        super.onResume()
        loadTrips()
    }

    private fun loadTrips() {
        val ctx = context ?: return
        val allTrips = TripRepository.getTrips(ctx)
        val upcoming = allTrips.filter { !it.isCompleted }
        val past = allTrips.filter { it.isCompleted }

        val totalCo2 = allTrips.sumOf { it.co2SavedKg }
        tvTotalCo2Avoided.text = String.format(java.util.Locale.US, "%.1f kg CO2e", totalCo2)
        tvActiveTripsCount.text = "${upcoming.size} Upcoming"

        layoutUpcomingTripsContainer.removeAllViews()
        for (trip in upcoming) {
            val cardView = createTripCardView(trip)
            layoutUpcomingTripsContainer.addView(cardView)
        }

        layoutPastTripsContainer.removeAllViews()
        for (trip in past) {
            val cardView = createTripCardView(trip)
            layoutPastTripsContainer.addView(cardView)
        }
    }

    private fun createTripCardView(trip: TripPlan): View {
        val inflater = LayoutInflater.from(context)
        val view = inflater.inflate(R.layout.item_trip_card, layoutUpcomingTripsContainer, false)

        view.findViewById<TextView>(R.id.tvTripTitle).text = trip.title
        view.findViewById<TextView>(R.id.tvTripCo2Badge).text = "-${trip.co2SavedKg} kg CO2"
        view.findViewById<TextView>(R.id.tvTripDates).text = "${trip.travelDates} • ${trip.durationDays} Days"
        view.findViewById<TextView>(R.id.tvTripHotel).text = "🏨 ${trip.hotelName} (★ ${trip.hotelRating}) • ♿ ${if (trip.isStepFreeAccessible) "Step-Free" else "Standard"}"
        view.findViewById<TextView>(R.id.tvTripModeBudget).text = "🚆 ${trip.travelMode} • Budget: ₹${trip.totalBudgetInr}"

        view.findViewById<MaterialButton>(R.id.btnOpenTripDetail).setOnClickListener {
            openTripDetail(trip)
        }

        view.setOnClickListener {
            openTripDetail(trip)
        }

        return view
    }

    private fun openTripDetail(trip: TripPlan) {
        val intent = Intent(context, TripDetailActivity::class.java).apply {
            putExtra("EXTRA_TRIP_PLAN", trip)
        }
        startActivity(intent)
    }
}
