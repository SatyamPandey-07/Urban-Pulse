package com.meenakshi.urbanpulse

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.widget.EditText
import android.widget.ImageButton
import androidx.appcompat.app.AlertDialog
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.chip.ChipGroup

class HospitalityActivity : BaseActivity() {

    private lateinit var rvStays: RecyclerView
    private lateinit var adapter: HospitalityAdapter
    private lateinit var etSearch: EditText
    private lateinit var chipGroup: ChipGroup

    private val allStays = listOf(
        HospitalityStay(
            id = "stay_1",
            name = "The Orchid Eco-Heritage Resort",
            category = "Certified Eco-Resort",
            location = "Vile Parle, Mumbai",
            ecoScore = 5,
            accessibilityRating = 98,
            energySource = "100% Solar & Biogas Grid",
            wastePolicy = "Zero Single-Use Plastic • In-house Composting",
            accessibilityTags = listOf("Wheelchair Ramp", "Roll-in Shower", "Braille Elevators", "Hearing Loop"),
            carbonFootprintPerNight = "4.2 kg CO2e / night (68% below city avg)",
            pricePerNight = "₹4,200 / night",
            contactPhone = "+91 22 2616 4040"
        ),
        HospitalityStay(
            id = "stay_2",
            name = "ITC Grand Central Green Hotel",
            category = "LEED Platinum Luxury Stay",
            location = "Parel, Mumbai",
            ecoScore = 5,
            accessibilityRating = 95,
            energySource = "Wind Farm Powered • 100% LED Sensor Lighting",
            wastePolicy = "Zero Food Waste to Landfill • Treated Greywater",
            accessibilityTags = listOf("Step-Free Entrance", "Tactile Pathways", "Accessible Parking", "Visual Smoke Alarms"),
            carbonFootprintPerNight = "5.1 kg CO2e / night (60% below city avg)",
            pricePerNight = "₹7,800 / night",
            contactPhone = "+91 22 2410 1010"
        ),
        HospitalityStay(
            id = "stay_3",
            name = "Bandra Farm-to-Table Eco Bistro & Suites",
            category = "Sustainable Boutique Stay",
            location = "Bandra West, Mumbai",
            ecoScore = 4,
            accessibilityRating = 92,
            energySource = "Rooftop Solar Array • EV Fast Chargers",
            wastePolicy = "Local Organic Sourcing • Rainwater Harvesting",
            accessibilityTags = listOf("Wheelchair Accessible Dining", "Wide Doorways", "Accessible Restrooms"),
            carbonFootprintPerNight = "3.8 kg CO2e / night (72% below city avg)",
            pricePerNight = "₹3,500 / night",
            contactPhone = "+91 22 2640 5500"
        ),
        HospitalityStay(
            id = "stay_4",
            name = "Sanjay Gandhi Nature Lodge & Eco-Cabins",
            category = "Bio-Reserve Retreat",
            location = "Borivali, Mumbai",
            ecoScore = 5,
            accessibilityRating = 88,
            energySource = "Off-grid Solar • Passive Natural Cooling",
            wastePolicy = "100% Biodegradable • Dry Toilet Systems",
            accessibilityTags = listOf("Gentle Slope Boardwalks", "Audio Trail Guides", "Guide Dog Friendly"),
            carbonFootprintPerNight = "1.9 kg CO2e / night (88% below city avg)",
            pricePerNight = "₹2,400 / night",
            contactPhone = "+91 22 2886 0389"
        )
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_hospitality)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        rvStays = findViewById(R.id.rvHospitalityStays)
        etSearch = findViewById(R.id.etSearchHospitality)
        chipGroup = findViewById(R.id.chipGroupHospitality)

        rvStays.layoutManager = LinearLayoutManager(this)
        adapter = HospitalityAdapter(allStays) { showStayAuditDialog(it) }
        rvStays.adapter = adapter

        setupFilterListeners()
    }

    private fun setupFilterListeners() {
        chipGroup.setOnCheckedStateChangeListener { _, checkedIds ->
            filterStays()
        }

        etSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                filterStays()
            }
            override fun afterTextChanged(s: Editable?) {}
        })
    }

    private fun filterStays() {
        val query = etSearch.text.toString().trim().lowercase()
        val checkedId = chipGroup.checkedChipId

        val filtered = allStays.filter { stay ->
            val matchesQuery = query.isEmpty() ||
                    stay.name.lowercase().contains(query) ||
                    stay.location.lowercase().contains(query) ||
                    stay.category.lowercase().contains(query)

            val matchesChip = when (checkedId) {
                R.id.chipFilterWheelchair -> stay.accessibilityTags.any { it.contains("Wheelchair", true) || it.contains("Step-Free", true) }
                R.id.chipFilterSolar -> stay.energySource.contains("Solar", true)
                R.id.chipFilterZeroWaste -> stay.wastePolicy.contains("Zero", true)
                R.id.chipFilterBraille -> stay.accessibilityTags.any { it.contains("Braille", true) || it.contains("Tactile", true) }
                else -> true
            }

            matchesQuery && matchesChip
        }

        adapter.updateList(filtered)
    }

    private fun showStayAuditDialog(stay: HospitalityStay) {
        AlertDialog.Builder(this)
            .setTitle(stay.name)
            .setMessage(
                "Classification: ${stay.category}\nLocation: ${stay.location}\n\n" +
                "🌿 Environmental Audit:\n" +
                "• Energy: ${stay.energySource}\n" +
                "• Waste Policy: ${stay.wastePolicy}\n" +
                "• Carbon Impact: ${stay.carbonFootprintPerNight}\n\n" +
                "♿ Accessibility Verification:\n" +
                "• Match Rating: ${stay.accessibilityRating}%\n" +
                "• Verified Features: ${stay.accessibilityTags.joinToString(", ")}\n\n" +
                "Tariff: ${stay.pricePerNight}"
            )
            .setPositiveButton("Call Venue") { _, _ ->
                val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:${stay.contactPhone}"))
                startActivity(intent)
            }
            .setNegativeButton("Close", null)
            .show()
    }
}
