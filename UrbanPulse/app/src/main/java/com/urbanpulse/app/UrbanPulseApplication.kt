package com.urbanpulse.app

import android.app.Application
import com.urbanpulse.app.trip.TripPlanManager

class UrbanPulseApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Initialize managers that need application context
        GamificationManager.init(this)
        TripPlanManager.init(this)
    }
}
