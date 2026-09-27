package com.urbanpulse.app

import com.urbanpulse.app.sms.SmsBridge
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Puts [SmsBridge] on the activity's permission-result chain.
 *
 * `FlutterActivity` only forwards `onRequestPermissionsResult` to registered
 * plugins, so without this the SEND_SMS prompt's answer would never come back and
 * the Dart call would hang. Wrapping it as a plugin is also what keeps the bridge
 * attached across a configuration change.
 */
class SmsPermissionPlugin(private val bridge: SmsBridge) : FlutterPlugin, ActivityAware {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) = Unit

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        bridge.attach(binding.activity)
        binding.addRequestPermissionsResultListener(bridge)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = Unit

    override fun onDetachedFromActivity() = Unit
}
