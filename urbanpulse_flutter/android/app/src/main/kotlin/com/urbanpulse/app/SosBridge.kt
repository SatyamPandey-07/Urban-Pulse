package com.urbanpulse.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * The "urbanpulse/sos" channel between Android and the Dart SosController.
 *
 * Android to Dart: "trigger" (power button), "cancel" (the notification's
 * "I'm safe" action), "openSos" (a notification was tapped). A trigger that
 * happens before Dart has started is kept and handed over when Dart calls
 * "ready", so a cold start never loses an SOS.
 */
object SosBridge {
    private const val CHANNEL = "urbanpulse/sos"
    private const val REQ_NOTIFICATIONS = 4101

    private var channel: MethodChannel? = null
    private var ready = false
    private var pendingTrigger: String? = null
    private val queued = mutableListOf<Pair<String, Map<String, Any?>>>()
    private val main = Handler(Looper.getMainLooper())

    /** The visible activity, for permission prompts. */
    var activity: WeakReference<Activity>? = null

    fun attach(engine: FlutterEngine, context: Context) {
        ready = false
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result -> handle(context.applicationContext, call, result) }
        }
    }

    /** The power button fired. */
    fun trigger(source: String) = main.post {
        if (ready) channel?.invokeMethod("trigger", mapOf("source" to source)) else pendingTrigger = source
    }

    fun send(method: String, args: Map<String, Any?> = emptyMap()) = main.post {
        if (ready) channel?.invokeMethod(method, args) else queued.add(method to args)
    }

    private fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ready" -> {
                ready = true
                val pending = pendingTrigger
                pendingTrigger = null
                result.success(mapOf("pending" to pending))
                val waiting = queued.toList()
                queued.clear()
                waiting.forEach { (m, a) -> channel?.invokeMethod(m, a) }
            }
            "startTrigger" -> result.success(SosTriggerService.start(context))
            "stopTrigger" -> {
                SosTriggerService.stop(context)
                result.success(null)
            }
            "status" -> {
                val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(
                    mapOf(
                        "running" to SosTriggerService.running,
                        "enabled" to SosTriggerService.isEnabled(context),
                        "notifications" to SosNotifications.allowed(context),
                        "batteryUnrestricted" to pm.isIgnoringBatteryOptimizations(context.packageName),
                    )
                )
            }
            "setActive" -> {
                val active = call.argument<Boolean>("active") == true
                val detail = call.argument<String>("detail")
                if (active) SosNotifications.showActive(context, detail) else SosNotifications.clearActive(context)
                result.success(null)
            }
            "notifyNearby" -> {
                SosNotifications.showNearby(
                    context,
                    call.argument<String>("id") ?: "",
                    call.argument<String>("title") ?: "SOS nearby",
                    call.argument<String>("body") ?: "",
                )
                result.success(null)
            }
            "clearNearby" -> {
                SosNotifications.clearNearby(context, call.argument<String>("id") ?: "")
                result.success(null)
            }
            "requestNotifications" -> {
                val a = activity?.get()
                if (Build.VERSION.SDK_INT >= 33 && !SosNotifications.allowed(context) && a != null) {
                    a.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
                }
                result.success(SosNotifications.allowed(context))
            }
            "openBatterySettings" -> {
                val a = activity?.get()
                try {
                    val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${context.packageName}"))
                    if (a != null) a.startActivity(i) else context.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                } catch (_: Exception) {
                    val i = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(i)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun hasLocationPermission(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
}
