package com.urbanpulse.app

import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentActivity
import androidx.viewpager2.adapter.FragmentStateAdapter

class MainPagerAdapter(fragmentActivity: FragmentActivity) : FragmentStateAdapter(fragmentActivity) {

    override fun getItemCount(): Int = 5 // Dashboard, Live Map, Digital Twin, Yatri AI, Settings

    override fun createFragment(position: Int): Fragment {
        return when (position) {
            0 -> DashboardFragment()
            1 -> LiveMapFragment()
            2 -> DigitalTwinFragment()
            3 -> YatriAiFragment()
            4 -> SettingsFragment()
            else -> DashboardFragment()
        }
    }
}
