package com.urbanpulse.app

import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import java.lang.ref.WeakReference

/**
 * Uses the shared engine (SosEngine), which outlives this screen so the SOS
 * service can keep using it when the app is closed.
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        SosEngine.ensure(this)
        super.onCreate(savedInstanceState)
        SosBridge.activity = WeakReference(this)
        handleSos(intent)
    }

    override fun getCachedEngineId(): String = SosEngine.ID

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onResume() {
        super.onResume()
        SosBridge.activity = WeakReference(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleSos(intent)
    }

    override fun onDestroy() {
        if (SosBridge.activity?.get() === this) SosBridge.activity = null
        super.onDestroy()
    }

    /** Opened from an SOS notification: show the SOS screen, over the lock screen. */
    private fun handleSos(intent: Intent?) {
        if (intent?.getBooleanExtra(SosNotifications.EXTRA_OPEN_SOS, false) != true) return
        intent.removeExtra(SosNotifications.EXTRA_OPEN_SOS)
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        SosBridge.send("openSos")
    }
}
