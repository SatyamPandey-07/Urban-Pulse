import 'dart:convert';

import '../core/config.dart';
import '../core/formatting.dart';
import '../domain/carbon_estimator.dart';
import '../models/mobility.dart';
import '../models/trip_models.dart';
import 'groq_api_client.dart';
import 'open_meteo_service.dart';
import 'tomtom_service.dart';

/// Autonomous multi-day itinerary planner.
///
/// Asks Groq for a structured JSON itinerary. When that call is unavailable or
/// fails it does not fall back to a canned trip: it *computes* one from real
/// inputs — a routed origin-to-destination distance (TomTom, or a haversine
/// estimate), the real per-mode fares/durations/emissions from
/// [CarbonEstimator], and the live air quality at the destination. The result is
/// still marked `offline_estimate` because no model wrote it, but every number
/// in it is derived rather than invented.
///
/// Port of `network/GroqAgenticEngine.kt`, whose fallback was three hand-written
/// destination templates.
abstract final class GroqAgenticEngine {
  static Future<TripPlan> generateAutonomousTripPlan({
    required String destination,
    required String originCity,
    required int days,
    required bool isAccessible,
    required String travelStyle,
  }) async {
    if (AppConfig.hasGroqKey) {
      final systemPrompt = _systemPrompt(destination, originCity, isAccessible);
      final userPrompt =
          'Generate a $days-day $travelStyle itinerary from $originCity to '
          '$destination. Wheelchair accessible: $isAccessible.';

      for (final model in GroqApiClient.candidateModels) {
        final content = await GroqApiClient.completion(
          model: model,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          temperature: 0.2,
          maxTokens: 1500,
        );
        if (content == null) continue;

        final parsed = _parseTripPlanJson(
          _extractJsonSubstring(content),
          destination: destination,
          originCity: originCity,
          days: days,
          isAccessible: isAccessible,
        );
        if (parsed != null) return parsed;
      }
    }

    return _computeFallbackTrip(
      destination: destination,
      originCity: originCity,
      days: days,
      isAccessible: isAccessible,
    );
  }

  static String _systemPrompt(
    String destination,
    String originCity,
    bool isAccessible,
  ) =>
      '''
You are Yatri AI, the autonomous green mobility & accessible travel planner for UrbanPulse.
Generate a complete, highly realistic multi-day travel itinerary starting explicitly from the user's origin city ($originCity) to the destination ($destination).

Guidelines:
1. Day 1 MUST start from $originCity with real electric transit (e.g. electric rail, local suburban, Vande Bharat, AC e-bus, or ferry).
2. Include real verified eco-stays, real landmarks, accurate timing, and step-free accessibility details (Wheelchair: $isAccessible).
3. Strictly NEVER use any emojis or emoticons anywhere in your response (neither in titles, descriptions, transit names, nor notes). Keep all text clean, concise, and professional.
4. Return ONLY valid, unescaped JSON matching this schema:
{
    "title": "...",
    "travelMode": "...",
    "hotelName": "...",
    "hotelRating": 4.8,
    "aqiStatus": "...",
    "totalBudgetInr": 5200,
    "transitCostInr": 280,
    "co2SavedKg": 18.5,
    "transitOpt1Name": "Green Transit (e.g. Electric Rail / Local)",
    "transitOpt1Metrics": "₹75 • 2h 05m • 28g CO2",
    "transitOpt2Name": "AC E-Bus / Shared Shuttle",
    "transitOpt2Metrics": "₹210 • 2h 20m • 54g CO2",
    "transitOpt3Name": "Standard Petrol Taxi",
    "transitOpt3Metrics": "₹3,200 • 2h 45m • 2,400g CO2",
    "dailyItinerary": [
        {
            "dayNumber": 1,
            "dayTitle": "...",
            "activities": [
                {
                    "time": "08:00 AM",
                    "title": "...",
                    "description": "...",
                    "transportType": "Train",
                    "isAccessible": true,
                    "co2Grams": 30,
                    "costInr": 60
                }
            ]
        }
    ]
}''';

  static String _extractJsonSubstring(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return text.substring(start, end + 1);
    }
    return text;
  }

  static TripPlan? _parseTripPlanJson(
    String jsonStr, {
    required String destination,
    required String originCity,
    required int days,
    required bool isAccessible,
  }) {
    try {
      final root = jsonDecode(jsonStr) as Map<String, dynamic>;

      final daysArray = root['dailyItinerary'] as List<dynamic>?;
      final itinerary = <TripDaySchedule>[];
      if (daysArray != null) {
        for (var i = 0; i < daysArray.length; i++) {
          final dayObj = daysArray[i] as Map<String, dynamic>;
          final dayNum = (dayObj['dayNumber'] as num?)?.toInt() ?? i + 1;
          final activities =
              ((dayObj['activities'] as List<dynamic>?) ?? const []).map((a) {
                final act = a as Map<String, dynamic>;
                return TripActivity(
                  time: act['time'] as String? ?? '09:00 AM',
                  title: act['title'] as String? ?? 'Eco Activity',
                  description:
                      act['description'] as String? ??
                      'Zero emission transit & visit',
                  transportType: act['transportType'] as String? ?? 'Train',
                  isAccessible: act['isAccessible'] as bool? ?? true,
                  co2Grams: (act['co2Grams'] as num?)?.toInt() ?? 25,
                  costInr: (act['costInr'] as num?)?.toInt() ?? 50,
                );
              }).toList();
          itinerary.add(
            TripDaySchedule(
              dayNumber: dayNum,
              dayTitle:
                  dayObj['dayTitle'] as String? ??
                  'Day $dayNum: $destination Exploration',
              activities: activities,
            ),
          );
        }
      }

      if (itinerary.isEmpty) return null;

      return TripPlan(
        id: 'trip_groq_${DateTime.now().millisecondsSinceEpoch}',
        destination: destination,
        title:
            root['title'] as String? ??
            '$destination $days-Day Low-Carbon Journey',
        durationDays: days,
        travelDates: 'Upcoming Journey ($days Days)',
        travelMode:
            root['travelMode'] as String? ??
            'Electric Rail / AC E-Bus from $originCity',
        co2SavedKg: (root['co2SavedKg'] as num?)?.toDouble() ?? 11.5 * days,
        pulsePointsEarned: 130 * days,
        isCompleted: false,
        hotelName:
            root['hotelName'] as String? ??
            'Green Key Certified Eco-Stay $destination',
        hotelRating: (root['hotelRating'] as num?)?.toDouble() ?? 4.8,
        isStepFreeAccessible: isAccessible,
        totalBudgetInr:
            (root['totalBudgetInr'] as num?)?.toInt() ?? 2500 * days,
        aqiStatus:
            root['aqiStatus'] as String? ?? 'Clean Regional Air (AQI 28)',
        transitCostInr: (root['transitCostInr'] as num?)?.toInt() ?? 350,
        dailyItinerary: itinerary,
        transitOpt1Name: root['transitOpt1Name'] as String?,
        transitOpt1Metrics: root['transitOpt1Metrics'] as String?,
        transitOpt2Name: root['transitOpt2Name'] as String?,
        transitOpt2Metrics: root['transitOpt2Metrics'] as String?,
        transitOpt3Name: root['transitOpt3Name'] as String?,
        transitOpt3Metrics: root['transitOpt3Metrics'] as String?,
        source: 'groq_ai',
      );
    } catch (_) {
      return null;
    }
  }

  /// Computes an itinerary skeleton from measured inputs when no model is
  /// available. Nothing here is a stored template: the distance is routed or
  /// computed, the transit options come from the same estimator the Green Route
  /// Planner uses, and the air quality is read live at the destination.
  static Future<TripPlan> _computeFallbackTrip({
    required String destination,
    required String originCity,
    required int days,
    required bool isAccessible,
  }) async {
    final routedKm = await TomTomService.fetchRealRouteDistanceKm(
      originCity,
      destination,
    );
    final distanceKm =
        routedKm ?? CarbonEstimator.estimateDistanceKm(originCity, destination);

    final options = CarbonEstimator.estimateAllModes(distanceKm);
    MobilityOption optionFor(TravelMode mode) =>
        options.firstWhere((o) => o.mode == mode);

    final rail = optionFor(TravelMode.metro);
    final bus = optionFor(TravelMode.bus);
    final taxi = optionFor(TravelMode.taxi);

    // Real avoided emissions: the petrol-cab baseline minus the rail option,
    // across the outbound and return legs.
    final avoidedKgPerLeg =
        rail.carbonAvoidedVsBaseline(taxi.carbonGrams) / 1000.0;
    final co2SavedKg = double.parse((avoidedKgPerLeg * 2).toStringAsFixed(1));

    // Live air quality at the destination's resolved coordinates.
    final (destLat, destLon) = CarbonEstimator.resolveCoordinates(destination);
    final weather = await OpenMeteoService.getLiveWeatherAndAqi(
      destLat,
      destLon,
    );
    final aqiStatus = weather != null
        ? '${_aqiBand(weather.usAqi)} (AQI ${weather.usAqi}, measured now)'
        : 'Air quality unavailable - no live reading for $destination';

    // Budget from the real fares plus a stated nightly allowance, so the number
    // is traceable rather than a round guess.
    const nightlyStayAllowance = 2200;
    final totalBudget = (rail.fareRupees * 2) + (nightlyStayAllowance * days);

    final itinerary = <TripDaySchedule>[
      TripDaySchedule(
        dayNumber: 1,
        dayTitle: '$originCity to $destination - low-carbon transit',
        activities: [
          TripActivity(
            time: '08:00 AM',
            title: 'Electric rail / metro leg',
            description:
                'Depart $originCity for $destination - ${fixed(distanceKm)} km, '
                '${rail.accessibilityNote}',
            transportType: 'Train',
            isAccessible: rail.stepFreeAccessible,
            co2Grams: rail.carbonGrams.round(),
            costInr: rail.fareRupees,
          ),
          TripActivity(
            time: _arrivalClock(rail.durationMin),
            title: 'Check in to a certified eco-stay',
            description: isAccessible
                ? 'Filter Sustainable Stays to step-free listings on arrival'
                : 'Pick a stay from Sustainable Stays on arrival',
            transportType: 'Hotel',
            isAccessible: isAccessible,
            co2Grams: 0,
            costInr: nightlyStayAllowance,
          ),
        ],
      ),
      for (var day = 2; day <= days; day++)
        TripDaySchedule(
          dayNumber: day,
          dayTitle: day == days
              ? '$destination - return to $originCity'
              : '$destination - local exploration',
          activities: [
            if (day == days)
              TripActivity(
                time: '04:30 PM',
                title: 'Return electric rail leg',
                description:
                    'Return to $originCity - ${fixed(distanceKm)} km, '
                    '${rail.durationMin} mins',
                transportType: 'Train',
                isAccessible: rail.stepFreeAccessible,
                co2Grams: rail.carbonGrams.round(),
                costInr: rail.fareRupees,
              )
            else
              const TripActivity(
                time: '09:00 AM',
                title: 'Local low-carbon day',
                description:
                    'Build this day in the Eco & Inclusive Itinerary tab, which ranks '
                    'real listings by carbon, accessibility and price',
                transportType: 'Walk',
                isAccessible: true,
                co2Grams: 0,
                costInr: 0,
              ),
          ],
        ),
    ];

    return TripPlan(
      id: 'trip_computed_${DateTime.now().millisecondsSinceEpoch}',
      destination: destination,
      title: '$destination $days-Day Low-Carbon Journey',
      durationDays: days,
      travelDates: 'Upcoming Journey ($days Days)',
      travelMode: '${rail.mode.label} from $originCity',
      co2SavedKg: co2SavedKg,
      pulsePointsEarned: (co2SavedKg * 10).round(),
      isCompleted: false,
      hotelName: 'Not selected - choose one in Sustainable Stays',
      hotelRating: 0,
      isStepFreeAccessible: isAccessible,
      totalBudgetInr: totalBudget,
      aqiStatus: aqiStatus,
      transitCostInr: rail.fareRupees * 2,
      dailyItinerary: itinerary,
      transitOpt1Name: rail.mode.label,
      transitOpt1Metrics: _metrics(rail),
      transitOpt2Name: bus.mode.label,
      transitOpt2Metrics: _metrics(bus),
      transitOpt3Name: taxi.mode.label,
      transitOpt3Metrics: _metrics(taxi),
    );
  }

  static String _metrics(MobilityOption option) =>
      '${rupees(option.fareRupees)} - ${option.durationMin} mins - '
      '${fixed(option.carbonGrams, 0)}g CO2';

  /// Clock time [minutesFromEight] after an 08:00 departure.
  static String _arrivalClock(int minutesFromEight) {
    final totalMinutes = 8 * 60 + minutesFromEight;
    final hour24 = (totalMinutes ~/ 60) % 24;
    final minute = totalMinutes % 60;
    final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')} '
        '${hour24 < 12 ? "AM" : "PM"}';
  }

  static String _aqiBand(int aqi) => switch (aqi) {
    <= 50 => 'Good',
    <= 100 => 'Moderate',
    <= 150 => 'Unhealthy for sensitive groups',
    <= 200 => 'Unhealthy',
    _ => 'Very unhealthy',
  };
}
