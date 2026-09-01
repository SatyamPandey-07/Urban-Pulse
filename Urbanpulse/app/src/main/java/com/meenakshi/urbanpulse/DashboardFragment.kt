package com.meenakshi.urbanpulse

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.fragment.app.Fragment
import com.github.mikephil.charting.charts.LineChart
import com.github.mikephil.charting.data.Entry
import com.github.mikephil.charting.data.LineData
import com.github.mikephil.charting.data.LineDataSet
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

        setupAirQualityChart(view)
    }

    private fun setupAirQualityChart(view: View) {
        val chart = view.findViewById<LineChart>(R.id.airQualityChart) ?: return

        val entries = listOf(
            Entry(1f, 85f),
            Entry(2f, 110f),
            Entry(3f, 95f),
            Entry(4f, 140f),
            Entry(5f, 120f),
            Entry(6f, 136f),
            Entry(7f, 128f)
        )

        val dataSet = LineDataSet(entries, "AQI Trend").apply {
            color = Color.parseColor("#4CAF50")
            valueTextColor = Color.GRAY
            lineWidth = 2.5f
            circleRadius = 4f
            setCircleColor(Color.parseColor("#388E3C"))
            mode = LineDataSet.Mode.CUBIC_BEZIER
            setDrawFilled(true)
            fillColor = Color.parseColor("#81C784")
            fillAlpha = 60
        }

        chart.data = LineData(dataSet)
        chart.description.isEnabled = false
        chart.legend.isEnabled = false
        chart.axisRight.isEnabled = false
        chart.xAxis.setDrawGridLines(false)
        chart.animateX(800)
        chart.invalidate()
    }
}
