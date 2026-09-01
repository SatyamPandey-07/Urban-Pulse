package com.urbanpulse.app

import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.meenakshi.urbanpulse.*

enum class SettingType {
    ACCESSIBILITY_PROFILE,
    CARBON_WALLET,
    HOSPITALITY_EXPLORER,
    ROUTE_PLANNER,
    HOTEL_OPTIMIZER,
    ITINERARY_PLANNER,
    APPEARANCE,
    ACCENT_COLOR,
    LOCATION,
    UNITS,
    LANGUAGE,
    SIGN_OUT,
    CUSTOM
}

data class SettingItem(
    val title: String, 
    val subtitle: String = "", 
    val iconRes: Int = 0,
    val iconBgColorHex: String = "#CCCCCC",
    val type: SettingType = SettingType.CUSTOM,
    val extraValue: String = ""
)

class SettingsFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val view = inflater.inflate(R.layout.fragment_settings, container, false)
        val recyclerView = view.findViewById<RecyclerView>(R.id.settingsRecyclerView)
        
        recyclerView.layoutManager = LinearLayoutManager(context)
        recyclerView.adapter = SettingsAdapter(getSettingsList()) { item ->
            handleSettingClick(item)
        }
        
        return view
    }

    private fun getSettingsList(): List<SettingItem> {
        val accessMgr = context?.let { AccessibilityManager.getInstance(it) }
        val wheelchairStatus = if (accessMgr?.isWheelchairModeEnabled == true) "Active (Step-Free Rerouting)" else "Disabled"

        return listOf(
            SettingItem("Inclusive Accessibility Profile", "Wheelchair: $wheelchairStatus, Visual & Hearing alerts", R.drawable.ic_settings, "#D3E3FD", SettingType.ACCESSIBILITY_PROFILE),
            SettingItem("Green Travel Passport", "142.8 kg CO2 saved • Gold Explorer", R.drawable.ic_map, "#C3E7A1", SettingType.CARBON_WALLET),
            SettingItem("Sustainable & Inclusive Stays", "Verified solar hotels, zero-waste resorts & accessibility audits", R.drawable.ic_dashboard, "#A7F3D0", SettingType.HOSPITALITY_EXPLORER),
            SettingItem("Multimodal Green Route Planner", "Tradeoff optimizer for Metro, EV Cab, and bus emissions", R.drawable.ic_traffic, "#FDE293", SettingType.ROUTE_PLANNER),
            SettingItem("AI Eco & Inclusive Itinerary", "Personalized step-free & low-carbon day itineraries", R.drawable.ic_confetti, "#FED7AA", SettingType.ITINERARY_PLANNER),
            SettingItem("Hotel Resource & Waste Hub", "B2B Energy, Water, food surplus & ESG compliance", R.drawable.ic_digital_twin, "#FBCFE8", SettingType.HOTEL_OPTIMIZER),
            SettingItem("Appearance & Theme", "System Default Dark Surface", R.drawable.ic_light_mode, "#FDE293", SettingType.APPEARANCE),
            SettingItem("Default City Hub", "Mumbai, Maharashtra, India", R.drawable.ic_location_pin, "#D3E3FD", SettingType.LOCATION),
            SettingItem("Measurement Units", "Metric (°C, km/h, kg CO2e)", R.drawable.ic_dashboard, "#F8D7DA", SettingType.UNITS),
            SettingItem("Language", "English", R.drawable.ic_yatri_ai, "#E9D5FF", SettingType.LANGUAGE)
        )
    }

    private fun handleSettingClick(item: SettingItem) {
        val ctx = context ?: return
        val accessMgr = AccessibilityManager.getInstance(ctx)

        when (item.type) {
            SettingType.ACCESSIBILITY_PROFILE -> {
                val options = arrayOf(
                    "Wheelchair / Step-Free Preference",
                    "High-Contrast & Large Badges",
                    "Hearing & Visual Flash Alerts",
                    "Service Animal Friendly Only"
                )
                val checked = booleanArrayOf(
                    accessMgr.isWheelchairModeEnabled,
                    accessMgr.isVisualAssistanceEnabled,
                    accessMgr.isHearingAssistanceEnabled,
                    accessMgr.isServiceAnimalFriendlyOnly
                )

                AlertDialog.Builder(ctx)
                    .setTitle("Inclusive Accessibility Preferences")
                    .setMultiChoiceItems(options, checked) { _, which, isChecked ->
                        when (which) {
                            0 -> accessMgr.isWheelchairModeEnabled = isChecked
                            1 -> accessMgr.isVisualAssistanceEnabled = isChecked
                            2 -> accessMgr.isHearingAssistanceEnabled = isChecked
                            3 -> accessMgr.isServiceAnimalFriendlyOnly = isChecked
                        }
                    }
                    .setPositiveButton("Save Preferences") { _, _ ->
                        Toast.makeText(ctx, "Accessibility preferences updated & synced with Yatri AI.", Toast.LENGTH_SHORT).show()
                    }
                    .setNegativeButton("Cancel", null)
                    .show()
            }
            SettingType.CARBON_WALLET -> startActivity(Intent(ctx, CarbonWalletActivity::class.java))
            SettingType.HOSPITALITY_EXPLORER -> startActivity(Intent(ctx, HospitalityActivity::class.java))
            SettingType.ROUTE_PLANNER -> startActivity(Intent(ctx, GreenRoutePlannerActivity::class.java))
            SettingType.ITINERARY_PLANNER -> startActivity(Intent(ctx, ItineraryActivity::class.java))
            SettingType.HOTEL_OPTIMIZER -> startActivity(Intent(ctx, HotelOptimizerActivity::class.java))
            else -> Toast.makeText(ctx, "${item.title} configuration active", Toast.LENGTH_SHORT).show()
        }
    }
}

class SettingsAdapter(
    private val items: List<SettingItem>,
    private val onItemClick: ((SettingItem) -> Unit)? = null
) : RecyclerView.Adapter<SettingsAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val title: TextView = view.findViewById(R.id.settingTitle)
        val subtitle: TextView = view.findViewById(R.id.settingSubtitle)
        val icon: ImageView = view.findViewById(R.id.settingIcon)
        val iconContainer: FrameLayout = view.findViewById(R.id.iconContainer)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context).inflate(R.layout.item_setting_option, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val item = items[position]
        holder.title.text = item.title
        val displaySubtitle = if (item.subtitle.isNotEmpty()) item.subtitle else item.extraValue
        holder.subtitle.text = displaySubtitle
        
        if (displaySubtitle.isEmpty()) {
            holder.subtitle.visibility = View.GONE
        } else {
            holder.subtitle.visibility = View.VISIBLE
        }

        if (item.iconRes != 0) {
            holder.icon.setImageResource(item.iconRes)
        }
        
        val background = holder.iconContainer.background as? GradientDrawable
        try {
            background?.setColor(Color.parseColor(item.iconBgColorHex))
        } catch (e: Exception) {
            background?.setColor(Color.LTGRAY)
        }
        holder.icon.setColorFilter(Color.parseColor("#1C1B1F"))

        holder.itemView.setOnClickListener {
            onItemClick?.invoke(item)
        }
    }

    override fun getItemCount() = items.size
}