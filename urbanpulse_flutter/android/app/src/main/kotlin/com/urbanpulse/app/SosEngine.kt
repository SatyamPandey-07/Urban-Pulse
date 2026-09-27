package com.urbanpulse.app

import android.content.Context
import com.urbanpulse.app.sms.SmsBridge
import com.urbanpulse.app.watch.GarminWatchBridge
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The app's one Flutter engine, shared by MainActivity and the SOS service.
 *
 * Normally MainActivity creates it. When the power button raises an SOS while
 * the app is closed, the service creates it instead, so the same Dart code
 * (location, Supabase, the SOS controller) runs without any screen; opening the
 * app later attaches to this engine and shows the SOS already in progress.
 *
 * The Garmin watch link and the SMS sender are attached here rather than in
 * MainActivity for the same reason: the engine outlives any screen, so a watch
 * that reconnects while the app is closed still has something to talk to, and the
 * bridges are registered exactly once instead of on every activity recreation.
 */
object SosEngine {
    const val ID = "urbanpulse_engine"

    /** Held for the process lifetime, like the engine itself. */
    private var garmin: GarminWatchBridge? = null
    private var sms: SmsBridge? = null

    @Synchronized
    fun ensure(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ID)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        SosBridge.attach(engine, context.applicationContext)

        val messenger = engine.dartExecutor.binaryMessenger
        garmin = GarminWatchBridge(context.applicationContext, messenger)
        val smsBridge = SmsBridge(messenger)
        sms = smsBridge
        // SmsPermissionPlugin is ActivityAware, so it picks up whichever activity
        // attaches to this engine - which is what lets the SEND_SMS prompt's
        // answer come back.
        engine.plugins.add(SmsPermissionPlugin(smsBridge))

        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ID, engine)
        return engine
    }
}
