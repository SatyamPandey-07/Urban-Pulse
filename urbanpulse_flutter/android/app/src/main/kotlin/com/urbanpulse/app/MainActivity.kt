package com.urbanpulse.app

import com.urbanpulse.app.sms.SmsBridge
import com.urbanpulse.app.watch.GarminWatchBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Hosts the two native bridges the watch feature needs: the Connect IQ link and
 * the SMS sender used by the SOS controller.
 */
class MainActivity : FlutterActivity() {

    private var garmin: GarminWatchBridge? = null
    private var sms: SmsBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        garmin = GarminWatchBridge(applicationContext, messenger)

        val smsBridge = SmsBridge(messenger)
        smsBridge.attach(this)
        sms = smsBridge
        // The SEND_SMS prompt's answer comes back through the activity, so the
        // bridge has to be on the permission-result chain.
        flutterEngine.plugins.add(SmsPermissionPlugin(smsBridge))
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        garmin?.dispose()
        garmin = null
        sms?.detach()
        sms = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
