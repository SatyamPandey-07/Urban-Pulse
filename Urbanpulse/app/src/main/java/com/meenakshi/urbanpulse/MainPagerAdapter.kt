package com.meenakshi.urbanpulse

import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentActivity
import androidx.viewpager2.adapter.FragmentStateAdapter
import com.tomtom.sdk.map.display.ui.MapFragment
import com.tomtom.sdk.map.display.MapOptions

class MainPagerAdapter(fragmentActivity: FragmentActivity) : FragmentStateAdapter(fragmentActivity) {

    override fun getItemCount(): Int = 5 // Dashboard, Map, Digital Twin, Yatri AI, Settings

    override fun createFragment(position: Int): Fragment {
        return when (position) {
            0 -> DashboardFragment()
            1 -> {
                val mapOptions = MapOptions(mapKey = BuildConfig.TOMTOM_API_KEY)
                MapFragment.newInstance(mapOptions)
            }
            2 -> DigitalTwinFragment()
            3 -> YatriAiFragment()
            4 -> SettingsFragment()
            else -> DashboardFragment()
        }
    }
}
