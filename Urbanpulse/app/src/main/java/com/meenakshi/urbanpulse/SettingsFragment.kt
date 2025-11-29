package com.meenakshi.urbanpulse

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.fragment.app.Fragment
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import androidx.core.content.ContextCompat

class SettingsFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        val view = inflater.inflate(R.layout.fragment_settings, container, false)
        val recyclerView = view.findViewById<RecyclerView>(R.id.settingsRecyclerView)
        
        recyclerView.layoutManager = LinearLayoutManager(context)
        recyclerView.adapter = SettingsAdapter(getSettingsList())
        
        return view
    }

    private fun getSettingsList(): List<SettingItem> {
        return listOf(
            SettingItem("Appearance", "Themes, animations, and app layout", R.drawable.ic_light_mode, "#FDE293"), // Yellowish
            SettingItem("Home location", "Beijing, Beijing, China", R.drawable.ic_location_pin, "#C3E7A1"), // Greenish
            SettingItem("App units", "Temperature, wind, pressure, visibility, precipitation", R.drawable.ic_dashboard, "#D3E3FD"), // Blueish
            SettingItem("Background updates", "Widget updates, update interval", R.drawable.ic_digital_twin, "#F8D7DA"), // Reddish/Pink
            SettingItem("Weather Models", "Open-Meteo Weather models", R.drawable.ic_dashboard, "#A7F3D0"), // Cyan/Teal
            SettingItem("App language", "English (US)", R.drawable.ic_yatri_ai, "#FBCFE8"), // Pink
            SettingItem("Export data", "", R.drawable.ic_send_24, "#F7D8BA"), // Orange/Peach
            SettingItem("Import data", "", R.drawable.ic_send_24, "#F7D8BA")  // Orange/Peach
        )
    }
}

data class SettingItem(
    val title: String, 
    val subtitle: String, 
    val iconRes: Int,
    val iconBgColorHex: String
)

class SettingsAdapter(private val items: List<SettingItem>) : RecyclerView.Adapter<SettingsAdapter.ViewHolder>() {

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
        holder.subtitle.text = item.subtitle
        
        if (item.subtitle.isEmpty()) {
            holder.subtitle.visibility = View.GONE
        } else {
            holder.subtitle.visibility = View.VISIBLE
        }

        holder.icon.setImageResource(item.iconRes)
        
        val background = holder.iconContainer.background as GradientDrawable
        try {
            background.setColor(Color.parseColor(item.iconBgColorHex))
        } catch (e: Exception) {
            background.setColor(Color.LTGRAY)
        }
        // Tint icon to dark grey/black for contrast on pastel backgrounds
        holder.icon.setColorFilter(Color.parseColor("#1C1B1F")) 
    }

    override fun getItemCount() = items.size
}