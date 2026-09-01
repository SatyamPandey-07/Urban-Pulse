package com.urbanpulse.app

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import com.github.mikephil.charting.charts.BarChart
import com.github.mikephil.charting.charts.LineChart
import com.github.mikephil.charting.components.XAxis
import com.github.mikephil.charting.data.BarData
import com.github.mikephil.charting.data.BarDataSet
import com.github.mikephil.charting.data.BarEntry
import com.github.mikephil.charting.data.Entry
import com.github.mikephil.charting.data.LineData
import com.github.mikephil.charting.data.LineDataSet
import com.github.mikephil.charting.formatter.IndexAxisValueFormatter
import com.google.android.material.button.MaterialButton

class DashboardFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_dashboard, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        view.findViewById<MaterialButton>(R.id.btnFollowLiveMap)?.setOnClickListener {
            (activity as? MainActivity)?.switchToTab(1)
        }

        view.findViewById<MaterialButton>(R.id.btnOpenHospitality)?.setOnClickListener {
            startActivity(Intent(activity, HospitalityActivity::class.java))
        }

        view.findViewById<MaterialButton>(R.id.btnOpenRoutePlanner)?.setOnClickListener {
            startActivity(Intent(activity, GreenRoutePlannerActivity::class.java))
        }

        view.findViewById<MaterialButton>(R.id.btnOpenHotelOptimizer)?.setOnClickListener {
            startActivity(Intent(activity, HotelOptimizerActivity::class.java))
        }

        view.findViewById<MaterialButton>(R.id.btnOpenCarbonWallet)?.setOnClickListener {
            startActivity(Intent(activity, CarbonWalletActivity::class.java))
        }

        view.findViewById<MaterialButton>(R.id.btnOpenItinerary)?.setOnClickListener {
            startActivity(Intent(activity, ItineraryActivity::class.java))
        }

        setupAirQualityChart(view)
        setupTrafficChart(view)
    }

    private fun setupAirQualityChart(view: View) {
        val chart = view.findViewById<LineChart>(R.id.airQualityChart) ?: return

        val entries = listOf(
            Entry(0f, 85f),
            Entry(1f, 110f),
            Entry(2f, 95f),
            Entry(3f, 140f),
            Entry(4f, 120f),
            Entry(5f, 136f),
            Entry(6f, 128f)
        )

        val dataSet = LineDataSet(entries, "AQI").apply {
            color = Color.parseColor("#38BDF8")
            valueTextColor = Color.parseColor("#94A3B8")
            valueTextSize = 9f
            lineWidth = 2.5f
            circleRadius = 4f
            setCircleColor(Color.parseColor("#38BDF8"))
            circleHoleColor = Color.parseColor("#0F172A")
            mode = LineDataSet.Mode.CUBIC_BEZIER
            setDrawFilled(false)
        }

        val days = arrayOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
        chart.xAxis.apply {
            valueFormatter = IndexAxisValueFormatter(days)
            position = XAxis.XAxisPosition.BOTTOM
            textColor = Color.parseColor("#94A3B8")
            setDrawGridLines(false)
            axisLineColor = Color.parseColor("#334155")
        }
        chart.axisLeft.apply {
            textColor = Color.parseColor("#94A3B8")
            setDrawGridLines(true)
            gridColor = Color.parseColor("#1E293B")
            axisLineColor = Color.parseColor("#334155")
        }

        chart.data = LineData(dataSet)
        chart.description.isEnabled = false
        chart.legend.isEnabled = false
        chart.axisRight.isEnabled = false
        chart.animateX(600)
        chart.invalidate()
    }

    private fun setupTrafficChart(view: View) {
        val chart = view.findViewById<BarChart>(R.id.trafficChart) ?: return

        val entries = listOf(
            BarEntry(0f, 25f),
            BarEntry(1f, 40f),
            BarEntry(2f, 75f),
            BarEntry(3f, 88f),
            BarEntry(4f, 60f),
            BarEntry(5f, 92f),
            BarEntry(6f, 50f)
        )

        val dataSet = BarDataSet(entries, "Traffic Index").apply {
            color = Color.parseColor("#10B981")
            valueTextColor = Color.parseColor("#94A3B8")
            valueTextSize = 9f
        }

        val hours = arrayOf("6 AM", "8 AM", "10 AM", "12 PM", "3 PM", "6 PM", "9 PM")
        chart.xAxis.apply {
            valueFormatter = IndexAxisValueFormatter(hours)
            position = XAxis.XAxisPosition.BOTTOM
            textColor = Color.parseColor("#94A3B8")
            setDrawGridLines(false)
            axisLineColor = Color.parseColor("#334155")
        }
        chart.axisLeft.apply {
            textColor = Color.parseColor("#94A3B8")
            setDrawGridLines(true)
            gridColor = Color.parseColor("#1E293B")
            axisLineColor = Color.parseColor("#334155")
        }

        chart.data = BarData(dataSet).apply {
            barWidth = 0.5f
        }
        chart.description.isEnabled = false
        chart.legend.isEnabled = false
        chart.axisRight.isEnabled = false
        chart.animateY(600)
        chart.invalidate()
    }
}
