package com.urbanpulse.app

import android.os.Bundle

class MapActivity : BaseActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_map)

        if (savedInstanceState == null) {
            supportFragmentManager.beginTransaction()
                .replace(R.id.live_map_fragment_container, LiveMapFragment())
                .commit()
        }
    }
}
