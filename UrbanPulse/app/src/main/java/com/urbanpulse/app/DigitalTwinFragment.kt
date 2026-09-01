package com.urbanpulse.app

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.fragment.app.Fragment
import com.google.android.material.slider.Slider

class DigitalTwinFragment : Fragment() {

    private lateinit var tvTrafficVolumeValue: TextView
    private lateinit var tvEvAdoptionValue: TextView
    private lateinit var tvTransitValue: TextView

    private lateinit var tvMetricPm25: TextView
    private lateinit var tvMetricPm25Delta: TextView
    private lateinit var tvMetricNo2: TextView
    private lateinit var tvMetricNo2Delta: TextView
    private lateinit var tvMetricCo2: TextView
    private lateinit var tvMetricCo2Delta: TextView
    private lateinit var tvMetricNoise: TextView

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        return inflater.inflate(R.layout.fragment_digital_twin, container, false)
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)

        tvTrafficVolumeValue = view.findViewById(R.id.tvTrafficVolumeValue)
        tvEvAdoptionValue = view.findViewById(R.id.tvEvAdoptionValue)
        tvTransitValue = view.findViewById(R.id.tvTransitValue)

        tvMetricPm25 = view.findViewById(R.id.tvMetricPm25)
        tvMetricPm25Delta = view.findViewById(R.id.tvMetricPm25Delta)
        tvMetricNo2 = view.findViewById(R.id.tvMetricNo2)
        tvMetricNo2Delta = view.findViewById(R.id.tvMetricNo2Delta)
        tvMetricCo2 = view.findViewById(R.id.tvMetricCo2)
        tvMetricCo2Delta = view.findViewById(R.id.tvMetricCo2Delta)
        tvMetricNoise = view.findViewById(R.id.tvMetricNoise)

        val sliderTraffic = view.findViewById<Slider>(R.id.traffic_volume_slider)
        val sliderEv = view.findViewById<Slider>(R.id.ev_adoption_slider)
        val sliderTransit = view.findViewById<Slider>(R.id.public_transport_slider)

        val updateSimulation = {
            val traffic = sliderTraffic.value.toInt()
            val ev = sliderEv.value.toInt()
            val transit = sliderTransit.value.toInt()

            tvTrafficVolumeValue.text = "$traffic%"
            tvEvAdoptionValue.text = "$ev%"
            tvTransitValue.text = "$transit%"

            // Simulation formula
            val pm25Base = 140
            val pm25 = (pm25Base * (traffic / 100.0) * (1 - (ev * 0.4 / 100.0)) * (1 - (transit * 0.3 / 100.0))).toInt() + 45
            val pm25Delta = ((pm25 - pm25Base) * 100) / pm25Base

            val no2 = (45 * (traffic / 100.0) * (1 - (ev * 0.6 / 100.0))).toInt() + 12
            val co2Saved = ((ev * 4.2) + (transit * 3.5) - (traffic * 1.2)).toInt().coerceAtLeast(10)
            val noise = (50 + (traffic * 0.28) - (ev * 0.12)).toInt()

            tvMetricPm25.text = "$pm25 µg/m³"
            tvMetricPm25Delta.text = if (pm25Delta <= 0) "$pm25Delta% Improvement" else "+$pm25Delta% Warning"

            tvMetricNo2.text = "$no2 ppb"
            tvMetricNo2Delta.text = if (ev > 20) "-${ev + 5}% Reduction" else "Baseline Flow"

            tvMetricCo2.text = "$co2Saved Tons"
            tvMetricCo2Delta.text = "+${(co2Saved * 0.3).toInt()}% Daily Savings"

            tvMetricNoise.text = "$noise dB"
        }

        sliderTraffic.addOnChangeListener { _, _, _ -> updateSimulation() }
        sliderEv.addOnChangeListener { _, _, _ -> updateSimulation() }
        sliderTransit.addOnChangeListener { _, _, _ -> updateSimulation() }

        updateSimulation()
    }
}
