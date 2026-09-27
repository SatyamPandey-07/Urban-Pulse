package com.urbanpulse.app.sms

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

/**
 * Sending the SOS message itself, on Android.
 *
 * This is the only place in the app that can make an SOS reach anyone without the
 * traveller tapping send, and it is deliberately narrow:
 *
 * * it reports [canSendSms] honestly — a refused `SEND_SMS` permission means
 *   false, and the Dart side then falls back to the system composer;
 * * [sendSms] returns the list of numbers `SmsManager` **accepted**, and nothing
 *   else. A number that threw is absent from that list, so a partial send reports
 *   as a partial send rather than a success.
 *
 * Accepted is still not delivered. Nothing in the app says "delivered".
 */
class SmsBridge(
    private val messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, PluginRegistry.RequestPermissionsResultListener {

    companion object {
        const val CHANNEL = "com.urbanpulse.app/sms"
        private const val REQUEST_CODE = 4711
    }

    private val channel = MethodChannel(messenger, CHANNEL).apply {
        setMethodCallHandler(this@SmsBridge)
    }

    private var activity: Activity? = null
    private var pendingPermission: MethodChannel.Result? = null

    fun attach(activity: Activity) {
        this.activity = activity
    }

    fun detach() {
        activity = null
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canSendSms" -> result.success(hasPermission())
            "requestSmsPermission" -> requestPermission(result)
            "sendSms" -> sendSms(call, result)
            else -> result.notImplemented()
        }
    }

    private fun hasPermission(): Boolean {
        val host = activity ?: return false
        return ContextCompat.checkSelfPermission(host, Manifest.permission.SEND_SMS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission(result: MethodChannel.Result) {
        val host = activity
        if (host == null) {
            result.success(false)
            return
        }
        if (hasPermission()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            // A second prompt would stack dialogs; answer the new caller with what
            // we know right now rather than queueing.
            result.success(false)
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(
            host,
            arrayOf(Manifest.permission.SEND_SMS),
            REQUEST_CODE,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>?,
        grantResults: IntArray?,
    ): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val pending = pendingPermission ?: return true
        pendingPermission = null
        val granted = grantResults != null &&
            grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pending.success(granted)
        return true
    }

    private fun sendSms(call: MethodCall, result: MethodChannel.Result) {
        val host = activity
        if (host == null) {
            result.error("noActivity", "No activity to send from", null)
            return
        }
        if (!hasPermission()) {
            // Not an error the traveller needs to see: the Dart side opens the
            // composer instead.
            result.error("noPermission", "SEND_SMS is not granted", null)
            return
        }
        val numbers = call.argument<List<String>>("numbers").orEmpty()
        val body = call.argument<String>("body")
        if (numbers.isEmpty() || body.isNullOrEmpty()) {
            result.error("badArgs", "numbers and body are required", null)
            return
        }

        val manager = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                host.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
        } catch (e: Exception) {
            null
        }
        if (manager == null) {
            result.error("noSmsManager", "This device has no SMS service", null)
            return
        }

        val accepted = ArrayList<String>(numbers.size)
        val failures = ArrayList<String>()
        for (number in numbers) {
            if (number.isBlank()) continue
            try {
                // A long message must go as a multipart, or the tail is dropped.
                val parts = manager.divideMessage(body)
                if (parts.size > 1) {
                    manager.sendMultipartTextMessage(number, null, parts, null, null)
                } else {
                    manager.sendTextMessage(number, null, body, null, null)
                }
                accepted.add(number)
            } catch (e: Exception) {
                failures.add(number)
            }
        }

        if (accepted.isEmpty()) {
            result.error(
                "sendFailed",
                "SmsManager rejected every number (${failures.size} failed)",
                null,
            )
            return
        }
        // Only the numbers the OS took. The Dart side reports this count verbatim.
        result.success(accepted)
    }
}
