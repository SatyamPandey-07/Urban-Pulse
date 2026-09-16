package com.urbanpulse.app.mobility

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Computes real, distance-driven trip estimates instead of hardcoded per-mode numbers.
 * Per-km factors are approximate published averages for an Indian metro-city grid mix;
 * they are deliberately simple (linear in distance) rather than a fabricated ML model.
 */
object CarbonEstimator {

    private const val EARTH_RADIUS_KM = 6371.0

    // name-fragment (lowercase) -> (lat, lng). Longest match wins.
    private val landmarks = linkedMapOf(
        "chhatrapati shivaji" to (18.9398 to 72.8355),
        "csmt" to (18.9398 to 72.8355),
        "vile parle" to (19.0970 to 72.8479),
        "bandra" to (19.0596 to 72.8295),
        "parel" to (19.0018 to 72.8339),
        "borivali" to (19.2307 to 72.8567),
        "andheri" to (19.1136 to 72.8697),
        "dadar" to (19.0178 to 72.8478),
        "thane" to (19.2183 to 72.9781),
        "mulund" to (19.1728 to 72.9425)
    )

    private val gpsCoordinatePattern = Regex("""(-?\d+\.\d+)\s*°?\s*N.*?(-?\d+\.\d+)\s*°?\s*E""", RegexOption.IGNORE_CASE)

    private data class ModeProfile(
        val avgSpeedKmh: Double,
        val baseFare: Int,
        val farePerKm: Double,
        val gramsPerKm: Double,
        val stepFree: Boolean,
        val accessibilityNote: String,
        /** Beyond this distance the mode is not a realistic choice (e.g. walking 20km). Null = no cap. */
        val maxPracticalKm: Double? = null,
        val impracticalReason: String? = null
    )

    private val profiles = mapOf(
        TravelMode.WALK to ModeProfile(
            avgSpeedKmh = 4.8, baseFare = 0, farePerKm = 0.0, gramsPerKm = 0.0,
            stepFree = false, accessibilityNote = "Self-paced, no vehicle boarding — not suited to wheelchair users over distance",
            maxPracticalKm = 3.0, impracticalReason = "Too far to walk practically"
        ),
        TravelMode.CYCLE to ModeProfile(
            avgSpeedKmh = 14.0, baseFare = 10, farePerKm = 2.0, gramsPerKm = 0.0,
            stepFree = false, accessibilityNote = "Requires cycling ability — bike-share dock access only",
            maxPracticalKm = 10.0, impracticalReason = "Too far for a shared-cycle trip"
        ),
        TravelMode.METRO to ModeProfile(32.0, 10, 2.5, 14.0, true, "100% Step-Free • Tactile Paving • Level Boarding"),
        TravelMode.BUS to ModeProfile(18.0, 5, 1.2, 21.0, true, "Low-floor hydraulic wheelchair ramp"),
        TravelMode.EV_CAB to ModeProfile(24.0, 40, 12.0, 35.0, false, "Curbside door-to-door, folding wheelchair trunk"),
        TravelMode.TAXI to ModeProfile(22.0, 50, 18.0, 140.0, false, "Standard sedan curbside")
    )

    /** Resolves free-text (a GPS-lock string or a landmark name) to lat/lng, with a Mumbai-center fallback. */
    fun resolveCoordinates(text: String): Pair<Double, Double> {
        gpsCoordinatePattern.find(text)?.let { match ->
            val lat = match.groupValues[1].toDoubleOrNull()
            val lng = match.groupValues[2].toDoubleOrNull()
            if (lat != null && lng != null) return lat to lng
        }
        val lower = text.lowercase()
        landmarks.entries.firstOrNull { lower.contains(it.key) }?.let { return it.value }
        return 19.0760 to 72.8777 // Mumbai city-center fallback
    }

    /** Great-circle distance between two lat/lng points, in kilometers. */
    fun haversineKm(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val dLat = Math.toRadians(lat2 - lat1)
        val dLng = Math.toRadians(lng2 - lng1)
        val a = sin(dLat / 2).pow(2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) * sin(dLng / 2).pow(2)
        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return EARTH_RADIUS_KM * c
    }

    fun estimateDistanceKm(originText: String, destinationText: String): Double {
        val (lat1, lng1) = resolveCoordinates(originText)
        val (lat2, lng2) = resolveCoordinates(destinationText)
        val straightLine = haversineKm(lat1, lng1, lat2, lng2)
        // Road/rail routes are never a straight line; apply a realistic detour factor.
        val routed = straightLine * 1.35
        return min(routed, 60.0).coerceAtLeast(1.5)
    }

    private val routeHttpClient = OkHttpClient.Builder()
        .connectTimeout(6, TimeUnit.SECONDS)
        .readTimeout(6, TimeUnit.SECONDS)
        .build()

    /**
     * Fetches a real road-network distance from the TomTom Routing API for the resolved
     * origin/destination coordinates. Returns null (caller falls back to [estimateDistanceKm]'s
     * haversine+detour-factor estimate) if the key is missing or the call fails.
     */
    suspend fun fetchRealRouteDistanceKm(originText: String, destinationText: String, apiKey: String): Double? {
        if (apiKey.isBlank() || apiKey == "DEMO_TOMTOM_KEY") return null
        val (lat1, lng1) = resolveCoordinates(originText)
        val (lat2, lng2) = resolveCoordinates(destinationText)
        return withContext(Dispatchers.IO) {
            try {
                val url = "https://api.tomtom.com/routing/1/calculateRoute/$lat1,$lng1:$lat2,$lng2/json?key=$apiKey&routeType=eco&traffic=true"
                val req = Request.Builder().url(url).get().build()
                routeHttpClient.newCall(req).execute().use { resp ->
                    if (!resp.isSuccessful) return@withContext null
                    val body = resp.body?.string() ?: return@withContext null
                    val json = JSONObject(body)
                    val routes = json.optJSONArray("routes") ?: return@withContext null
                    if (routes.length() == 0) return@withContext null
                    val summary = routes.getJSONObject(0).optJSONObject("summary") ?: return@withContext null
                    val lengthMeters = summary.optDouble("lengthInMeters", 0.0)
                    if (lengthMeters > 0.0) lengthMeters / 1000.0 else null
                }
            } catch (e: Exception) {
                null
            }
        }
    }

    fun estimateOption(mode: TravelMode, distanceKm: Double): MobilityOption {
        val profile = profiles.getValue(mode)
        val durationMin = ((distanceKm / profile.avgSpeedKmh) * 60).roundToInt().coerceAtLeast(3)
        val fare = (profile.baseFare + distanceKm * profile.farePerKm).roundToInt()
        val carbon = distanceKm * profile.gramsPerKm
        val isPractical = profile.maxPracticalKm == null || distanceKm <= profile.maxPracticalKm
        return MobilityOption(
            mode = mode,
            distanceKm = distanceKm,
            durationMin = durationMin,
            fareRupees = fare,
            carbonGrams = carbon,
            stepFreeAccessible = profile.stepFree,
            accessibilityNote = profile.accessibilityNote,
            practical = isPractical,
            impracticalReason = if (isPractical) null else profile.impracticalReason
        )
    }

    fun estimateAllModes(distanceKm: Double): List<MobilityOption> =
        TravelMode.values().map { estimateOption(it, distanceKm) }
}
