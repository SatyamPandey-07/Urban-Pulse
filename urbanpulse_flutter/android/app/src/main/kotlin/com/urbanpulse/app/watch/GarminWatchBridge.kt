package com.urbanpulse.app.watch

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.IQDevice
import com.garmin.android.connectiq.exception.InvalidStateException
import com.garmin.android.connectiq.exception.ServiceUnavailableException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The phone end of the Garmin link, over the Connect IQ Mobile SDK for Android.
 *
 * Two things are worth knowing before reading the rest.
 *
 * **The status it reports is the SDK's, never a guess.** Every one of the six
 * states the Dart side knows about maps onto something the SDK actually told us:
 * `GCM_NOT_INSTALLED` from the init callback, an empty known-device list, a
 * device status that is not `CONNECTED`, and `onApplicationNotInstalled` for the
 * watch app itself. When we do not know, the answer is "not connected", not
 * "connected".
 *
 * **There are two transports.** [ConnectIQ.IQConnectType.WIRELESS] goes through
 * Garmin Connect Mobile to a real watch. [ConnectIQ.IQConnectType.TETHERED] talks
 * to the Connect IQ *simulator* over TCP, which is the only way to exercise this
 * code without a watch in the room:
 *
 * ```
 * adb forward tcp:7381 tcp:7381
 * ```
 *
 * then start the connection from the simulator's Connection menu. Tethered mode
 * needs no Garmin Connect Mobile on the phone. See `garmin/README.md`.
 */
class GarminWatchBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "com.urbanpulse.app/garmin"
        const val EVENT_CHANNEL = "com.urbanpulse.app/garmin_events"

        /** Must match `garmin/urbanpulse-watch/manifest.xml`. */
        const val WATCH_APP_ID = "f2ad5fab4ae240d984032ec48e3179d8"

        /** The port the Connect IQ simulator listens on. */
        const val DEFAULT_ADB_PORT = 7381

        private const val TAG = "GarminWatchBridge"

        // The status strings the Dart side parses. Kept as literals on both sides
        // so a rename cannot silently become "deviceNotConnected".
        private const val CONNECTED = "connected"
        private const val WATCH_APP_NOT_INSTALLED = "watchAppNotInstalled"
        private const val DEVICE_NOT_CONNECTED = "deviceNotConnected"
        private const val NO_DEVICE_PAIRED = "noDevicePaired"
        private const val GARMIN_APP_MISSING = "garminAppMissing"
    }

    private val main = Handler(Looper.getMainLooper())
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL).apply {
        setMethodCallHandler(this@GarminWatchBridge)
    }
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL).apply {
        setStreamHandler(this@GarminWatchBridge)
    }

    private var events: EventChannel.EventSink? = null
    private var connectIq: ConnectIQ? = null
    private var watchApp = IQApp(WATCH_APP_ID)
    private var device: IQDevice? = null

    /** Whether the SDK has called back `onSdkReady`. */
    private var sdkReady = false

    /** Set when `onInitializeError` said Garmin Connect is missing or too old. */
    private var gcmProblem = false

    /** Set once `getApplicationInfo` confirms the watch app is side-loaded. */
    private var appConfirmed = false

    /** Completes the pending `connect` call exactly once. */
    private var pendingConnect: MethodChannel.Result? = null

    // ---------------------------------------------------------------- method channel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> connect(call, result)
            "send" -> send(call, result)
            "openWatchApp" -> openWatchApp(result)
            "shutdown" -> {
                shutdown()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val tethered = call.argument<Boolean>("tethered") ?: false
        val adbPort = call.argument<Int>("adbPort") ?: DEFAULT_ADB_PORT

        // Re-connecting with the same transport just re-probes; changing transport
        // needs a fresh SDK instance.
        if (sdkReady && connectIq != null) {
            probe(result)
            return
        }

        val type = if (tethered) {
            ConnectIQ.IQConnectType.TETHERED
        } else {
            ConnectIQ.IQConnectType.WIRELESS
        }
        val iq = ConnectIQ.getInstance(context, type)
        connectIq = iq
        if (tethered) {
            try {
                iq.adbPort = adbPort
            } catch (e: IllegalArgumentException) {
                result.error(DEVICE_NOT_CONNECTED, "Invalid ADB port $adbPort", null)
                return
            }
        }

        pendingConnect = result
        sdkReady = false
        gcmProblem = false
        appConfirmed = false

        // `false` suppresses the SDK's own "install Garmin Connect" dialog: the
        // settings row reports that state itself, and an app should not throw up a
        // system dialog because a settings screen was opened.
        iq.initialize(context, false, object : ConnectIQ.ConnectIQListener {
            override fun onSdkReady() {
                sdkReady = true
                probeAndFinish()
            }

            override fun onInitializeError(status: ConnectIQ.IQSdkErrorStatus?) {
                sdkReady = false
                gcmProblem = status == ConnectIQ.IQSdkErrorStatus.GCM_NOT_INSTALLED ||
                    status == ConnectIQ.IQSdkErrorStatus.GCM_UPGRADE_NEEDED
                val reported = if (gcmProblem) GARMIN_APP_MISSING else DEVICE_NOT_CONNECTED
                finishConnect(reported)
                emitStatus(reported)
            }

            override fun onSdkShutDown() {
                sdkReady = false
                emitStatus(DEVICE_NOT_CONNECTED)
            }
        })
    }

    /** Finds the watch, subscribes to it, and reports what the SDK said. */
    private fun probeAndFinish() {
        val status = findDeviceAndSubscribe()
        // `watchAppNotInstalled` is provisional until `getApplicationInfo` answers,
        // which it does asynchronously; `emitStatus` from that callback corrects it.
        finishConnect(status)
        emitStatus(status)
    }

    private fun probe(result: MethodChannel.Result) {
        val status = findDeviceAndSubscribe()
        result.success(status)
        emitStatus(status)
    }

    /**
     * Picks a device, registers for its events, and asks whether our watch app is
     * on it. Returns the status known synchronously.
     */
    private fun findDeviceAndSubscribe(): String {
        val iq = connectIq ?: return DEVICE_NOT_CONNECTED
        if (gcmProblem) return GARMIN_APP_MISSING

        val known = try {
            iq.knownDevices ?: emptyList()
        } catch (e: InvalidStateException) {
            return DEVICE_NOT_CONNECTED
        } catch (e: ServiceUnavailableException) {
            // The SDK is up but Garmin Connect's service is not answering.
            return GARMIN_APP_MISSING
        }
        if (known.isEmpty()) return NO_DEVICE_PAIRED

        // Prefer a connected device; fall back to the first known one so the
        // status can say "not connected" about a specific watch.
        val connected = try {
            iq.connectedDevices ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
        val target = connected.firstOrNull() ?: known.first()
        device = target

        val deviceStatus = try {
            iq.getDeviceStatus(target)
        } catch (e: Exception) {
            null
        }
        if (deviceStatus != IQDevice.IQDeviceStatus.CONNECTED) {
            return DEVICE_NOT_CONNECTED
        }

        subscribe(iq, target)
        askIfAppInstalled(iq, target)

        // The device is there and connected. Whether the *app* is installed is
        // still outstanding, so report the honest interim answer: an app we have
        // not confirmed is not one we can claim to be talking to.
        return if (appConfirmed) CONNECTED else WATCH_APP_NOT_INSTALLED
    }

    private fun subscribe(iq: ConnectIQ, target: IQDevice) {
        try {
            iq.registerForDeviceEvents(target) { _, status ->
                emitStatus(
                    if (status == IQDevice.IQDeviceStatus.CONNECTED) {
                        if (appConfirmed) CONNECTED else WATCH_APP_NOT_INSTALLED
                    } else {
                        DEVICE_NOT_CONNECTED
                    }
                )
            }
        } catch (e: InvalidStateException) {
            android.util.Log.w(TAG, "could not register for device events", e)
        }

        try {
            iq.registerForAppEvents(target, watchApp) { _, _, payload, status ->
                if (status == ConnectIQ.IQMessageStatus.SUCCESS) {
                    // A message arriving is the strongest possible proof the watch
                    // app is installed and running.
                    if (!appConfirmed) {
                        appConfirmed = true
                        emitStatus(CONNECTED)
                    }
                    payload?.forEach { emitMessage(it) }
                } else {
                    android.util.Log.w(TAG, "inbound message status $status")
                }
            }
        } catch (e: InvalidStateException) {
            android.util.Log.w(TAG, "could not register for app events", e)
        }
    }

    private fun askIfAppInstalled(iq: ConnectIQ, target: IQDevice) {
        try {
            iq.getApplicationInfo(
                WATCH_APP_ID,
                target,
                object : ConnectIQ.IQApplicationInfoListener {
                    override fun onApplicationInfoReceived(app: IQApp?) {
                        if (app != null) watchApp = app
                        appConfirmed = true
                        emitStatus(CONNECTED)
                    }

                    override fun onApplicationNotInstalled(applicationId: String?) {
                        appConfirmed = false
                        emitStatus(WATCH_APP_NOT_INSTALLED)
                    }
                },
            )
        } catch (e: Exception) {
            // Leave `appConfirmed` false: not knowing is not the same as installed.
            android.util.Log.w(TAG, "getApplicationInfo failed", e)
        }
    }

    private fun send(call: MethodCall, result: MethodChannel.Result) {
        val iq = connectIq
        val target = device
        if (iq == null || !sdkReady) {
            result.error(DEVICE_NOT_CONNECTED, "The Connect IQ SDK is not ready", null)
            return
        }
        if (target == null) {
            result.error(NO_DEVICE_PAIRED, "No Garmin device to send to", null)
            return
        }
        val payload = (call.arguments as? Map<*, *>)?.let { stripNulls(it) }
        if (payload == null) {
            result.error("badPayload", "Expected a map payload", null)
            return
        }

        try {
            iq.sendMessage(target, watchApp, payload) { _, _, status ->
                // The listener is the only honest place to answer: an accepted
                // call is not a delivered message.
                if (status == ConnectIQ.IQMessageStatus.SUCCESS) {
                    result.success(null)
                } else {
                    result.error(status.name, "Connect IQ reported $status", null)
                }
            }
        } catch (e: InvalidStateException) {
            result.error(DEVICE_NOT_CONNECTED, e.message ?: "SDK not initialised", null)
        } catch (e: ServiceUnavailableException) {
            result.error(GARMIN_APP_MISSING, e.message ?: "Garmin Connect unavailable", null)
        }
    }

    private fun openWatchApp(result: MethodChannel.Result) {
        val iq = connectIq
        val target = device
        if (iq == null || target == null) {
            result.success(if (gcmProblem) GARMIN_APP_MISSING else DEVICE_NOT_CONNECTED)
            return
        }
        try {
            iq.openApplication(target, watchApp) { _, _, status ->
                val reported = when (status) {
                    ConnectIQ.IQOpenApplicationStatus.PROMPT_SHOWN_ON_DEVICE,
                    ConnectIQ.IQOpenApplicationStatus.APP_IS_ALREADY_RUNNING,
                    -> {
                        appConfirmed = true
                        CONNECTED
                    }
                    ConnectIQ.IQOpenApplicationStatus.APP_IS_NOT_INSTALLED -> {
                        appConfirmed = false
                        WATCH_APP_NOT_INSTALLED
                    }
                    else -> DEVICE_NOT_CONNECTED
                }
                result.success(reported)
                emitStatus(reported)
            }
        } catch (e: Exception) {
            result.success(DEVICE_NOT_CONNECTED)
        }
    }

    private fun shutdown() {
        val iq = connectIq ?: return
        try {
            iq.unregisterAllForEvents()
        } catch (e: Exception) {
            // Already down.
        }
        try {
            iq.shutdown(context)
        } catch (e: InvalidStateException) {
            // Never initialised.
        }
        connectIq = null
        device = null
        sdkReady = false
        appConfirmed = false
    }

    /** Called when the Flutter engine detaches. */
    fun dispose() {
        shutdown()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        events = null
    }

    // ---------------------------------------------------------------- event channel

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun finishConnect(status: String) {
        val pending = pendingConnect ?: return
        pendingConnect = null
        main.post { pending.success(status) }
    }

    private fun emitStatus(status: String) {
        main.post { events?.success(mapOf("status" to status)) }
    }

    /**
     * Forwards one deserialised Monkey C object to Dart.
     *
     * The SDK hands back whatever the watch transmitted; only a dictionary is a
     * protocol message, and anything else is dropped rather than guessed at.
     */
    private fun emitMessage(payload: Any?) {
        val map = payload as? Map<*, *> ?: return
        val converted = HashMap<String, Any?>(map.size)
        for ((key, value) in map) {
            val name = key as? String ?: continue
            converted[name] = flatten(value)
        }
        if (converted.isEmpty()) return
        main.post { events?.success(converted) }
    }

    /** Recursively drops nulls, which the Monkey C serialiser will not take. */
    private fun stripNulls(map: Map<*, *>): HashMap<String, Any> {
        val out = HashMap<String, Any>(map.size)
        for ((key, value) in map) {
            val name = key as? String ?: continue
            when (value) {
                null -> Unit
                is Map<*, *> -> out[name] = stripNulls(value)
                else -> out[name] = value
            }
        }
        return out
    }

    /** Makes a deserialised value safe for the Flutter codec. */
    private fun flatten(value: Any?): Any? = when (value) {
        null, is Boolean, is Int, is Long, is Float, is Double, is String -> value
        is Map<*, *> -> stripNulls(value)
        is List<*> -> value.map { flatten(it) }
        // Char and the other Monkey C scalars have no codec entry of their own.
        else -> value.toString()
    }
}
