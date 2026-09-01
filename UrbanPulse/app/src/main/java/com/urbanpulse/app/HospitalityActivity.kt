package com.urbanpulse.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.widget.EditText
import android.widget.ImageButton
import androidx.appcompat.app.AlertDialog
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.chip.ChipGroup
import com.urbanpulse.app.evidence.RankedHospitalityStay
import com.urbanpulse.app.viewmodel.HospitalityViewModel
import kotlinx.coroutines.launch

class HospitalityActivity : BaseActivity() {

    private lateinit var rvStays: RecyclerView
    private lateinit var adapter: HospitalityAdapter
    private lateinit var etSearch: EditText
    private lateinit var chipGroup: ChipGroup

    private val viewModel: HospitalityViewModel by lazy {
        ViewModelProvider(this)[HospitalityViewModel::class.java]
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_hospitality)

        findViewById<ImageButton>(R.id.btnBack).setOnClickListener { finish() }

        rvStays = findViewById(R.id.rvHospitalityStays)
        etSearch = findViewById(R.id.etSearchHospitality)
        chipGroup = findViewById(R.id.chipGroupHospitality)

        rvStays.layoutManager = LinearLayoutManager(this)
        adapter = HospitalityAdapter(emptyList()) { showStayAuditDialog(it) }
        rvStays.adapter = adapter

        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.rankedStays.collect { ranked ->
                    adapter.updateList(ranked)
                }
            }
        }

        setupFilterListeners()
    }

    private fun setupFilterListeners() {
        chipGroup.setOnCheckedStateChangeListener { _, _ ->
            val filter = when (chipGroup.checkedChipId) {
                R.id.chipFilterWheelchair -> HospitalityViewModel.ChipFilter.WHEELCHAIR
                R.id.chipFilterSolar -> HospitalityViewModel.ChipFilter.SOLAR
                R.id.chipFilterZeroWaste -> HospitalityViewModel.ChipFilter.ZERO_WASTE
                R.id.chipFilterBraille -> HospitalityViewModel.ChipFilter.BRAILLE
                else -> HospitalityViewModel.ChipFilter.ALL
            }
            viewModel.updateChipFilter(filter)
        }

        etSearch.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                viewModel.updateQuery(s.toString())
            }
            override fun afterTextChanged(s: Editable?) {}
        })
    }

    private fun showStayAuditDialog(ranked: RankedHospitalityStay) {
        val stay = ranked.stay

        val badgeLine = if (ranked.badges.isNotEmpty()) {
            "🏆 " + ranked.badges.joinToString(" • ") { it.label } + "\n\n"
        } else ""

        val evidenceSection = ranked.evidence.joinToString("\n\n") { claim ->
            var text = "${claim.confidence.icon} [${claim.confidence.label}] ${claim.claim}\n" +
                "Sources: ${claim.sources.joinToString(", ")}"
            if (claim.contradiction != null) {
                text += "\n⚠️ ${claim.contradiction}"
            }
            text
        }

        AlertDialog.Builder(this)
            .setTitle(stay.name)
            .setMessage(
                badgeLine +
                "Classification: ${stay.category}\nLocation: ${stay.location}\nTariff: ${stay.pricePerNight}\n\n" +
                "Evidence Graph — Why this?\n\n" + evidenceSection
            )
            .setPositiveButton("Call Venue") { _, _ ->
                val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:${stay.contactPhone}"))
                startActivity(intent)
            }
            .setNegativeButton("Close", null)
            .show()
    }
}
