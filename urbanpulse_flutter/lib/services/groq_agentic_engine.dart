import 'dart:convert';

import '../core/config.dart';
import '../models/trip_models.dart';
import 'groq_api_client.dart';

/// Autonomous multi-day itinerary planner. Asks Groq for a structured JSON
/// itinerary and, when the call is unavailable or fails, falls back to a
/// destination-tailored template that is explicitly labelled as an offline
/// estimate (`TripPlan.source`) so the UI never claims live AI generation it
/// didn't get.
///
/// Port of `network/GroqAgenticEngine.kt`.
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

    // Realistic fallback tailored from origin to destination.
    return _buildRealisticFallbackTrip(
      destination,
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
3. Return ONLY valid, unescaped JSON matching this schema:
{
    "title": "...",
    "travelMode": "...",
    "hotelName": "...",
    "hotelRating": 4.8,
    "aqiStatus": "...",
    "totalBudgetInr": 5200,
    "transitCostInr": 280,
    "co2SavedKg": 18.5,
    "transitOpt1Name": "🚆 Green Transit (e.g. Electric Rail / Local)",
    "transitOpt1Metrics": "₹75 • 2h 05m • 28g CO2",
    "transitOpt2Name": "⚡ AC E-Bus / Shared Shuttle",
    "transitOpt2Metrics": "₹210 • 2h 20m • 54g CO2",
    "transitOpt3Name": "🚗 Standard Petrol Taxi",
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

  static TripPlan _buildRealisticFallbackTrip(
    String dest, {
    required String originCity,
    required int days,
    required bool isAccessible,
  }) {
    final lower = dest.toLowerCase();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    if (lower.contains('matheran')) {
      return TripPlan(
        id: 'trip_dyn_matheran_$stamp',
        destination: 'Matheran',
        title: 'Matheran Vehicle-Free Eco-Hill Journey',
        durationDays: days,
        travelDates: 'Upcoming Weekend ($days Days)',
        travelMode: '$originCity Central Local to Neral + Matheran Toy Train',
        co2SavedKg: 11.5 * days,
        pulsePointsEarned: 130 * days,
        isCompleted: false,
        hotelName: 'The Byke Heritage Eco-Resort (Pure Veg & Solar)',
        hotelRating: 4.8,
        isStepFreeAccessible: isAccessible,
        totalBudgetInr: 2200 * days,
        aqiStatus: 'Pristine Forest Air (AQI 22 • 100% Automobile-Free)',
        transitCostInr: 110,
        dailyItinerary: [
          TripDaySchedule(
            dayNumber: 1,
            dayTitle: '$originCity to Neral & Matheran Toy Train Ascent',
            activities: [
              TripActivity(
                time: '07:30 AM',
                title: 'Central Railway AC Local',
                description:
                    '$originCity CSMT/Dadar/Thane to Neral Junction (Electric Rail • Level Boarding)',
                transportType: 'Train',
                isAccessible: true,
                co2Grams: 35,
                costInr: 60,
              ),
              const TripActivity(
                time: '09:45 AM',
                title: 'Matheran Heritage Toy Train',
                description: 'Neral to Matheran / Aman Lodge Shuttle (Zero Emission Eco-Zone)',
                transportType: 'Train',
                isAccessible: true,
                co2Grams: 10,
                costInr: 50,
              ),
              const TripActivity(
                time: '11:30 AM',
                title: 'The Byke Heritage Check-in',
                description:
                    '100% Solar Powered Heritage Villa (Step-Free Ramps)',
                transportType: 'Hotel',
                isAccessible: true,
                co2Grams: 0,
                costInr: 0,
              ),
              const TripActivity(
                time: '03:30 PM',
                title: 'Charlotte Lake & Echo Point',
                description: 'Vehicle-free forest pedestrian walking trail & bird watching',
                transportType: 'Walk',
                isAccessible: true,
                co2Grams: 0,
                costInr: 0,
              ),
            ],
          ),
          TripDaySchedule(
            dayNumber: 2,
            dayTitle: 'Louisa Point & Return to $originCity',
            activities: [
              const TripActivity(
                time: '08:00 AM',
                title: 'Louisa Point & Panorama Peak',
                description:
                    'Morning valley sunrise view with bio-toilets along trail',
                transportType: 'Walk',
                isAccessible: true,
                co2Grams: 0,
                costInr: 0,
              ),
              const TripActivity(
                time: '01:00 PM',
                title: 'Eco-E-Rickshaw to Aman Lodge',
                description:
                    'Govt Authorized Electric Shuttle (Low Speed Zero Noise)',
                transportType: 'E-Bus',
                isAccessible: true,
                co2Grams: 5,
                costInr: 35,
              ),
              TripActivity(
                time: '04:30 PM',
                title: 'Central AC Local to $originCity',
                description:
                    'Neral Junction return express train to $originCity',
                transportType: 'Train',
                isAccessible: true,
                co2Grams: 35,
                costInr: 60,
              ),
            ],
          ),
        ],
        transitOpt1Name: '🚆 Central Local + Matheran Toy Train',
        transitOpt1Metrics: '₹110 • 2h 15m • 35g CO2',
        transitOpt2Name: '⚡ Neral E-Rickshaw + Shuttle',
        transitOpt2Metrics: '₹90 • 1h 50m • 18g CO2',
        transitOpt3Name: '🚗 Standard Petrol Taxi (to Dasturi Naka)',
        transitOpt3Metrics: '₹2,100 • 2h 30m • 1,600g CO2',
      );
    }

    if (lower.contains('kedar')) {
      return TripPlan(
        id: 'trip_dyn_kedarnath_$stamp',
        destination: 'Kedarnath',
        title: 'Kedarnath Dham Holy Eco-Yatra',
        durationDays: days,
        travelDates: 'Upcoming Spiritual Journey ($days Days)',
        travelMode:
            '$originCity-Haridwar Superfast Rail + Electric Pilgrim Shuttle',
        co2SavedKg: 14.2 * days,
        pulsePointsEarned: 160 * days,
        isCompleted: false,
        hotelName: 'GMVN Mandakini Eco Tourist Rest House (Solar Heated)',
        hotelRating: 4.8,
        isStepFreeAccessible: isAccessible,
        totalBudgetInr: 2800 * days,
        aqiStatus: 'Pristine Himalayan Alpine Air (AQI 18)',
        transitCostInr: 1450,
        dailyItinerary: [
          TripDaySchedule(
            dayNumber: 1,
            dayTitle: '$originCity Departure to Haridwar Hub',
            activities: [
              TripActivity(
                time: '08:30 AM',
                title: 'Haridwar AC Superfast Express',
                description:
                    '$originCity CSMT/Bandra to Haridwar Jn (100% Electric Rail • Level Boarding)',
                transportType: 'Train',
                isAccessible: true,
                co2Grams: 280,
                costInr: 1450,
              ),
              const TripActivity(
                time: '03:00 PM',
                title: 'Solar Eco Guest House Check-in',
                description:
                    'Haridwar GMVN Alaknanda Rest House (Step-Free Concourse)',
                transportType: 'Hotel',
                isAccessible: true,
                co2Grams: 0,
                costInr: 0,
              ),
              const TripActivity(
                time: '06:30 PM',
                title: 'Har Ki Pauri Ganga Aarti',
                description: 'Paved accessible riverside walkway & bio-toilets',
                transportType: 'Walk',
                isAccessible: true,
                co2Grams: 0,
                costInr: 0,
              ),
            ],
          ),
          const TripDaySchedule(
            dayNumber: 2,
            dayTitle: 'Haridwar to Sonprayag & Gaurikund Base',
            activities: [
              TripActivity(
                time: '06:00 AM',
                title: 'AC Electric Pilgrim Coach',
                description:
                    'Haridwar to Sonprayag Hub (Low-Carbon Scenic Valley)',
                transportType: 'E-Bus',
                isAccessible: true,
                co2Grams: 45,
                costInr: 650,
              ),
              TripActivity(
                time: '02:30 PM',
                title: 'Govt Electric Local Shuttle',
                description:
                    'Sonprayag to Gaurikund Base (Zero Emission E-Shuttle)',
                transportType: 'E-Bus',
                isAccessible: true,
                co2Grams: 10,
                costInr: 50,
              ),
              TripActivity(
                time: '04:30 PM',
                title: 'Eco Rest House Check-in',
                description:
                    'GMVN Mandakini Solar Guest House (Heated Step-Free)',
                transportType: 'Hotel',
                isAccessible: true,
                co2Grams: 0,
                costInr: 0,
              ),
            ],
          ),
          TripDaySchedule(
            dayNumber: 3,
            dayTitle: 'Gaurikund to Shri Kedarnath Dham',
            activities: [
              TripActivity(
                time: '05:30 AM',
                title: 'Eco Pilgrim Ascent',
                description: isAccessible
                    ? 'Assisted Step-free Palki / Wheelchair Hoist route'
                    : 'Paved Himalayan Walking Trail',
                transportType: 'Walk',
                isAccessible: true,
                co2Grams: 0,
                costInr: 0,
              ),
              const TripActivity(
                time: '01:00 PM',
                title: 'Shri Kedarnath Temple Darshan',
                description: '12th Jyotirlinga Darshan & Zero-Plastic Eco Zone',
                transportType: 'Walk',
                isAccessible: true,
                co2Grams: 0,
                costInr: 0,
              ),
              const TripActivity(
                time: '06:30 PM',
                title: 'Evening Mandakini Aarti',
                description: 'Solar lit temple complex with bio-toilets',
                transportType: 'Walk',
                isAccessible: true,
                co2Grams: 0,
                costInr: 0,
              ),
            ],
          ),
          TripDaySchedule(
            dayNumber: 4,
            dayTitle: 'Bhairavnath Ridge & Return Journey to $originCity',
            activities: [
              const TripActivity(
                time: '07:00 AM',
                title: 'Bhairavnath Panoramic Shrine',
                description: 'Morning alpine view overlooking Kedarnath temple',
                transportType: 'Walk',
                isAccessible: true,
                co2Grams: 0,
                costInr: 0,
              ),
              const TripActivity(
                time: '11:30 AM',
                title: 'Descent to Gaurikund Base',
                description: 'Govt E-Shuttle back to Sonprayag',
                transportType: 'E-Bus',
                isAccessible: true,
                co2Grams: 10,
                costInr: 50,
              ),
              TripActivity(
                time: '06:00 PM',
                title: 'Return Superfast Express',
                description: 'Haridwar Junction to $originCity CSMT',
                transportType: 'Train',
                isAccessible: true,
                co2Grams: 280,
                costInr: 1450,
              ),
            ],
          ),
        ],
        transitOpt1Name: '🚆 $originCity-Haridwar Superfast + E-Shuttle',
        transitOpt1Metrics: '₹1,450 • Level Boarding • 280g CO2',
        transitOpt2Name: '⚡ AC Pilgrim Express Coach',
        transitOpt2Metrics: '₹2,200 • AC Seater • 350g CO2',
        transitOpt3Name: '🚗 Private Highway Diesel SUV Taxi',
        transitOpt3Metrics: '₹18,500 • High Emissions • 24,000g CO2',
      );
    }

    return TripPlan(
      id: 'trip_dyn_gen_$stamp',
      destination: dest,
      title: '$dest $days-Day Low-Carbon Journey',
      durationDays: days,
      travelDates: 'Upcoming Journey ($days Days)',
      travelMode: 'Electric Express Train / AC E-Coach from $originCity',
      co2SavedKg: 12.0 * days,
      pulsePointsEarned: 130 * days,
      isCompleted: false,
      hotelName: 'Green Key Certified Eco-Stay $dest',
      hotelRating: 4.8,
      isStepFreeAccessible: isAccessible,
      totalBudgetInr: 2500 * days,
      aqiStatus: 'Clean Regional Air (AQI 28)',
      transitCostInr: 250,
      dailyItinerary: [
        TripDaySchedule(
          dayNumber: 1,
          dayTitle: '$originCity to $dest Transit & Eco-Check-in',
          activities: [
            TripActivity(
              time: '08:00 AM',
              title: 'Electric Transit Departure',
              description:
                  'Depart from $originCity via high-speed electric rail or e-bus '
                  '(Level Boarding)',
              transportType: 'Train',
              isAccessible: true,
              co2Grams: 35,
              costInr: 250,
            ),
            const TripActivity(
              time: '11:00 AM',
              title: 'Step-Free Eco Stay Check-in',
              description: 'Solar powered certified hotel accommodation with greywater recycling',
              transportType: 'Hotel',
              isAccessible: true,
              co2Grams: 0,
              costInr: 0,
            ),
            TripActivity(
              time: '03:30 PM',
              title: '$dest Heritage & Nature Trail',
              description: 'Pedestrianized zero-emission sightseeing zone & cultural center',
              transportType: 'Walk',
              isAccessible: true,
              co2Grams: 0,
              costInr: 0,
            ),
          ],
        ),
        TripDaySchedule(
          dayNumber: 2,
          dayTitle: '$dest Eco-Exploration & Return to $originCity',
          activities: [
            const TripActivity(
              time: '09:00 AM',
              title: 'Botanical & Scenic Viewpoint',
              description: 'Accessible paved paths with solar audio guides',
              transportType: 'Walk',
              isAccessible: true,
              co2Grams: 0,
              costInr: 50,
            ),
            TripActivity(
              time: '04:30 PM',
              title: 'Electric Return Coach to $originCity',
              description: 'Return to $originCity with zero tailpipe emissions',
              transportType: 'Train',
              isAccessible: true,
              co2Grams: 35,
              costInr: 250,
            ),
          ],
        ),
      ],
      transitOpt1Name: '🚆 Electric Train / E-Coach from $originCity',
      transitOpt1Metrics: '₹250 • Level Boarding • 35g CO2',
      transitOpt2Name: '⚡ AC Electric Bus Corridor',
      transitOpt2Metrics: '₹350 • Zero Emission • 48g CO2',
      transitOpt3Name: '🚗 Private Petrol Taxi',
      transitOpt3Metrics: '₹3,400 • High Emissions • 2,600g CO2',
    );
  }
}
