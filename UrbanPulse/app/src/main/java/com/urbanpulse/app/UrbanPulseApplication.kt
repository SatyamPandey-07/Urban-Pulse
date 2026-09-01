package com.urbanpulse.app

import android.app.Application

class UrbanPulseApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Initialize managers that need application context
        GamificationManager.init(this)
    }
}
