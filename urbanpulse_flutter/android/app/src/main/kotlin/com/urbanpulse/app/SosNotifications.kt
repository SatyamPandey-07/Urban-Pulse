package com.urbanpulse.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build

/** The SOS notifications and their channels. */
object SosNotifications {
    const val ID_WATCH = 4001
    const val ID_ACTIVE = 4002
    private const val CH_WATCH = "sos_watch"
    private const val CH_ALERT = "sos_alert"
    const val EXTRA_OPEN_SOS = "urbanpulse.open_sos"
    const val ACTION_CANCEL = "com.urbanpulse.app.SOS_CANCEL"

    fun createChannels(context: Context) {
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CH_WATCH, "Power-button SOS", NotificationManager.IMPORTANCE_MIN).apply {
                description = "Shown while UrbanPulse listens for three quick presses of the power button."
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_ALERT, "SOS alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Your active SOS, and SOS alerts from people near you."
                enableVibration(true)
                enableLights(true)
                lightColor = Color.RED
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
        )
    }

    fun allowed(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun openApp(context: Context, request: Int): PendingIntent {
        val i = Intent(context, MainActivity::class.java)
            .putExtra(EXTRA_OPEN_SOS, true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(context, request, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    fun watching(context: Context): Notification {
        createChannels(context)
        return Notification.Builder(context, CH_WATCH)
            .setSmallIcon(R.drawable.ic_stat_sos)
            .setContentTitle("Power-button SOS is on")
            .setContentText("Press the power button 3 times quickly to send an SOS.")
            .setOngoing(true)
            .setContentIntent(openApp(context, 1))
            .build()
    }

    fun showActive(context: Context, detail: String?) {
        if (!allowed(context)) return
        createChannels(context)
        val cancel = PendingIntent.getBroadcast(
            context,
            2,
            Intent(context, SosActionReceiver::class.java).setAction(ACTION_CANCEL),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = Notification.Builder(context, CH_ALERT)
            .setSmallIcon(R.drawable.ic_stat_sos)
            .setColor(Color.parseColor("#DC2626"))
            .setContentTitle("SOS active")
            .setContentText(detail ?: "Nearby UrbanPulse users can see it.")
            .setStyle(Notification.BigTextStyle().bigText(detail ?: "Nearby UrbanPulse users can see it."))
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(openApp(context, 3))
            .addAction(Notification.Action.Builder(null, "I'm safe: cancel SOS", cancel).build())
            .build()
        context.getSystemService(NotificationManager::class.java).notify(ID_ACTIVE, n)
    }

    fun clearActive(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(ID_ACTIVE)
    }

    private fun nearbyId(sosId: String) = 5000 + (sosId.hashCode() and 0x7fff)

    fun showNearby(context: Context, sosId: String, title: String, body: String) {
        if (!allowed(context)) return
        createChannels(context)
        val n = Notification.Builder(context, CH_ALERT)
            .setSmallIcon(R.drawable.ic_stat_sos)
            .setColor(Color.parseColor("#DC2626"))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(openApp(context, nearbyId(sosId)))
            .build()
        context.getSystemService(NotificationManager::class.java).notify(nearbyId(sosId), n)
    }

    fun clearNearby(context: Context, sosId: String) {
        context.getSystemService(NotificationManager::class.java).cancel(nearbyId(sosId))
    }
}

/** "I'm safe: cancel SOS" on the notification. */
class SosActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != SosNotifications.ACTION_CANCEL) return
        SosEngine.ensure(context.applicationContext)
        SosBridge.send("cancel")
    }
}

/** Starts the power-button watch again after a reboot, if it was on. */
class SosBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED && intent.action != "android.intent.action.QUICKBOOT_POWERON") return
        if (SosTriggerService.isEnabled(context)) SosTriggerService.start(context)
    }
}
