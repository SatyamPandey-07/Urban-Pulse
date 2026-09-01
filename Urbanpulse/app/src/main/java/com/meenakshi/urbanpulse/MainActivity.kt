package com.meenakshi.urbanpulse

import android.content.Intent
import android.os.Bundle
import android.widget.ImageButton
import android.widget.TextView
import androidx.viewpager2.widget.ViewPager2
import com.google.android.material.bottomnavigation.BottomNavigationView

class MainActivity : BaseActivity() {

    private lateinit var viewPager: ViewPager2
    private lateinit var bottomNavigation: BottomNavigationView
    private lateinit var tvLocationTitle: TextView
    private lateinit var tvLocationSubtitle: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        viewPager = findViewById(R.id.view_pager)
        bottomNavigation = findViewById(R.id.bottom_navigation)
        tvLocationTitle = findViewById(R.id.tvLocationTitle)
        tvLocationSubtitle = findViewById(R.id.tvLocationSubtitle)

        tvLocationTitle.text = "Mumbai"
        tvLocationSubtitle.text = "Maharashtra, India"

        val adapter = MainPagerAdapter(this)
        viewPager.adapter = adapter
        viewPager.isUserInputEnabled = false // Prevent accidental swiping across tabs

        bottomNavigation.setOnItemSelectedListener { item ->
            when (item.itemId) {
                R.id.navigation_dashboard -> {
                    viewPager.setCurrentItem(0, false)
                    true
                }
                R.id.navigation_map -> {
                    viewPager.setCurrentItem(1, false)
                    true
                }
                R.id.navigation_digital_twin -> {
                    viewPager.setCurrentItem(2, false)
                    true
                }
                R.id.navigation_yatri_ai -> {
                    viewPager.setCurrentItem(3, false)
                    true
                }
                R.id.navigation_settings -> {
                    viewPager.setCurrentItem(4, false)
                    true
                }
                else -> false
            }
        }

        viewPager.registerOnPageChangeCallback(object : ViewPager2.OnPageChangeCallback() {
            override fun onPageSelected(position: Int) {
                super.onPageSelected(position)
                bottomNavigation.menu.getItem(position).isChecked = true
            }
        })

        findViewById<ImageButton>(R.id.btnAchievements).setOnClickListener {
            startActivity(Intent(this, AchievementsActivity::class.java))
        }

        findViewById<ImageButton>(R.id.btnSos).setOnClickListener {
            startActivity(Intent(this, SosActivity::class.java))
        }
    }

    fun switchToTab(position: Int) {
        if (position in 0 until (viewPager.adapter?.itemCount ?: 0)) {
            viewPager.setCurrentItem(position, true)
            bottomNavigation.menu.getItem(position).isChecked = true
        }
    }
}
