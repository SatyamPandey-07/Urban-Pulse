package com.urbanpulse.app

import android.content.Context
import android.content.SharedPreferences
import com.urbanpulse.app.evidence.EvidenceClaim
import com.urbanpulse.app.evidence.EvidenceGraphService

/**
 * Owns the traveler's own step-free / visual / hearing / service-animal accessibility
 * preference flags, and is the entry point for evidence-tagged accessibility claims about
 * a listing (delegating to [EvidenceGraphService], which holds the actual Verified/Reported/
 * Inferred confidence-tagging logic) — this is the one place both halves of "accessibility"
 * in this app meet: what the traveler needs, and what's actually been confirmed about a place.
 */
class AccessibilityManager(context: Context) {

    private val prefs: SharedPreferences = context.getSharedPreferences("AccessibilityPrefs", Context.MODE_PRIVATE)

    var isWheelchairModeEnabled: Boolean
        get() = prefs.getBoolean("key_wheelchair_mode", false)
        set(value) = prefs.edit().putBoolean("key_wheelchair_mode", value).apply()

    var isVisualAssistanceEnabled: Boolean
        get() = prefs.getBoolean("key_visual_assist", false)
        set(value) = prefs.edit().putBoolean("key_visual_assist", value).apply()

    var isHearingAssistanceEnabled: Boolean
        get() = prefs.getBoolean("key_hearing_assist", false)
        set(value) = prefs.edit().putBoolean("key_hearing_assist", value).apply()

    var isServiceAnimalFriendlyOnly: Boolean
        get() = prefs.getBoolean("key_service_animal", false)
        set(value) = prefs.edit().putBoolean("key_service_animal", value).apply()

    /** Evidence-tagged accessibility/sustainability claims for an experience listing — real
     *  confidence tiers (Verified/Reported/Inferred), not a plain "Accessible: Yes/No". */
    fun evidenceFor(experience: ExperienceListing): List<EvidenceClaim> =
        EvidenceGraphService.buildEvidenceForExperience(experience)

    /** Same, for a hospitality stay. */
    fun evidenceFor(stay: HospitalityStay): List<EvidenceClaim> =
        EvidenceGraphService.buildEvidence(stay)

    companion object {
        @Volatile
        private var instance: AccessibilityManager? = null

        fun getInstance(context: Context): AccessibilityManager {
            return instance ?: synchronized(this) {
                instance ?: AccessibilityManager(context.applicationContext).also { instance = it }
            }
        }
    }
}
