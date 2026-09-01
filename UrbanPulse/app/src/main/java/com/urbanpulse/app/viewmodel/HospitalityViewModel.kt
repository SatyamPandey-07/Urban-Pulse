package com.urbanpulse.app.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.urbanpulse.app.data.HospitalityRepository
import com.urbanpulse.app.evidence.ParetoOptimizer
import com.urbanpulse.app.evidence.RankedHospitalityStay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class HospitalityViewModel(application: Application) : AndroidViewModel(application) {

    enum class ChipFilter { ALL, WHEELCHAIR, SOLAR, ZERO_WASTE, BRAILLE }

    private val repository = HospitalityRepository(application)

    private var allRanked: List<RankedHospitalityStay> = emptyList()

    private var query: String = ""
    private var chipFilter: ChipFilter = ChipFilter.ALL

    private val _isLoading = MutableStateFlow(true)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _rankedStays = MutableStateFlow<List<RankedHospitalityStay>>(emptyList())
    val rankedStays: StateFlow<List<RankedHospitalityStay>> = _rankedStays.asStateFlow()

    init {
        viewModelScope.launch {
            val stays = repository.getAllStays()
            allRanked = ParetoOptimizer.rank(stays)
            _isLoading.value = false
            applyFilters()
        }
    }

    fun updateQuery(newQuery: String) {
        query = newQuery
        applyFilters()
    }

    fun updateChipFilter(filter: ChipFilter) {
        chipFilter = filter
        applyFilters()
    }

    private fun applyFilters() {
        val q = query.trim().lowercase()
        _rankedStays.value = allRanked.filter { ranked ->
            val stay = ranked.stay
            val matchesQuery = q.isEmpty() ||
                stay.name.lowercase().contains(q) ||
                stay.location.lowercase().contains(q) ||
                stay.category.lowercase().contains(q)

            val matchesChip = when (chipFilter) {
                ChipFilter.ALL -> true
                ChipFilter.WHEELCHAIR -> stay.accessibilityTags.any { it.contains("Wheelchair", true) || it.contains("Step-Free", true) }
                ChipFilter.SOLAR -> stay.energySource.contains("Solar", true)
                ChipFilter.ZERO_WASTE -> stay.wastePolicy.contains("Zero", true)
                ChipFilter.BRAILLE -> stay.accessibilityTags.any { it.contains("Braille", true) || it.contains("Tactile", true) }
            }

            matchesQuery && matchesChip
        }
    }
}
