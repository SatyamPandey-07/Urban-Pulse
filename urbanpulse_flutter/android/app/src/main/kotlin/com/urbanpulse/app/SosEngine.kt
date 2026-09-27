package com.urbanpulse.app

import android.content.Context
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
 */
object SosEngine {
    const val ID = "urbanpulse_engine"

    @Synchronized
    fun ensure(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ID)?.let { return it }
        val engine = FlutterEngine(context.applicationContext)
        SosBridge.attach(engine, context.applicationContext)
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        FlutterEngineCache.getInstance().put(ID, engine)
        return engine
    }
}
