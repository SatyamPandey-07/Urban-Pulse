import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_models.dart';

/// The traveler's saved trips, persisted as JSON in shared preferences.
/// Port of `TripRepository.kt`.
class TripRepository {
  TripRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _keyTrips = 'urbanpulse_trips.saved_trips_json';

  /// The user's real saved trips — starts empty on first run, not pre-seeded
  /// with sample data.
  List<TripPlan> getTrips() {
    final json = _prefs.getString(_keyTrips);
    if (json == null) return const [];
    try {
      return (jsonDecode(json) as List<dynamic>)
          .map((t) => TripPlan.fromJson(t as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> addTrip(TripPlan trip) async {
    final list = [trip, ...getTrips()];
    await _prefs.setString(
      _keyTrips,
      jsonEncode(list.map((t) => t.toJson()).toList()),
    );
  }

  /// Illustrative quick-start templates shown only by the "Quick Lonavala" /
  /// "Quick Alibaug" shortcut buttons on the Trips tab — never a new user's real
  /// trip history. [getTrips] starts empty; a trip only appears there once
  /// genuinely created via Yatri AI or saved from one of these templates.
  static List<TripPlan> getSampleTrips() => _sampleQuickTrips;

  static final List<TripPlan> _sampleQuickTrips = [
    const TripPlan(
      id: 'trip_lonavala_01',
      destination: 'Lonavala',
      title: 'Lonavala Monsoon Eco-Retreat',
      durationDays: 2,
      travelDates: 'Sep 12 - Sep 14, 2026',
      travelMode: 'Electric Express Train (Indrayani Exp)',
      co2SavedKg: 18.4,
      pulsePointsEarned: 250,
      isCompleted: false,
      hotelName: 'The Machan Eco Resort (100% Solar)',
      hotelRating: 4.8,
      isStepFreeAccessible: true,
      totalBudgetInr: 4200,
      aqiStatus: 'Clean Mountain Air (AQI 28)',
      transitCostInr: 150,
      dailyItinerary: [
        TripDaySchedule(
          dayNumber: 1,
          dayTitle: 'Scenic Ridge & Heritage Caves',
          activities: [
            TripActivity(
              time: '07:10 AM',
              title: 'Indrayani Express Train',
              description: 'Dadar to Lonavala (Electric Traction • Low Carbon)',
              transportType: 'Train',
              isAccessible: true,
              co2Grams: 28,
              costInr: 75,
            ),
            TripActivity(
              time: '09:45 AM',
              title: 'Step-Free Check-in',
              description: 'The Machan Solar Treehouse Resort',
              transportType: 'Hotel',
              isAccessible: true,
              co2Grams: 0,
              costInr: 0,
            ),
            TripActivity(
              time: '11:30 AM',
              title: 'Karla Caves & E-Shuttle',
              description: 'Ancient Buddhist caves with wheelchair accessible lower plaza',
              transportType: 'E-Bus',
              isAccessible: true,
              co2Grams: 40,
              costInr: 50,
            ),
            TripActivity(
              time: '03:30 PM',
              title: 'Bhushi Dam Eco Trail',
              description:
                  'Zero-plastic walking corridor with rain harvest viewing',
              transportType: 'Walk',
              isAccessible: true,
              co2Grams: 0,
              costInr: 0,
            ),
            TripActivity(
              time: '07:00 PM',
              title: 'Farm-to-Fork Organic Dinner',
              description: 'Locally sourced Maharashtrian millet cuisine',
              transportType: 'Hotel',
              isAccessible: true,
              co2Grams: 10,
              costInr: 350,
            ),
          ],
        ),
        TripDaySchedule(
          dayNumber: 2,
          dayTitle: 'Tiger Point & Sunset Valley',
          activities: [
            TripActivity(
              time: '08:30 AM',
              title: 'Guided Nature Walk',
              description: 'Ryewood Botanical Garden (Accessible Paved Trails)',
              transportType: 'Walk',
              isAccessible: true,
              co2Grams: 0,
              costInr: 0,
            ),
            TripActivity(
              time: '12:00 PM',
              title: "Tiger's Leap Scenic Valley",
              description:
                  'Electric shuttle to viewpoint with tactile edge safety',
              transportType: 'E-Bus',
              isAccessible: true,
              co2Grams: 35,
              costInr: 60,
            ),
            TripActivity(
              time: '04:30 PM',
              title: 'Lonavala Chikki Heritage Stop',
              description: 'Traditional organic jaggery fudge workshop',
              transportType: 'Walk',
              isAccessible: true,
              co2Grams: 0,
              costInr: 100,
            ),
            TripActivity(
              time: '06:15 PM',
              title: 'Deccan Express Return',
              description: 'Lonavala to Mumbai CSMT (Electric Rail)',
              transportType: 'Train',
              isAccessible: true,
              co2Grams: 28,
              costInr: 75,
            ),
          ],
        ),
      ],
    ),
    const TripPlan(
      id: 'trip_alibaug_02',
      destination: 'Alibaug',
      title: 'Alibaug Coastal Low-Carbon Trail',
      durationDays: 1,
      travelDates: 'Upcoming: Sep 20, 2026',
      travelMode: 'Ro-Pax Electric Hybrid Ferry (Bhaucha Dhakka)',
      co2SavedKg: 12.2,
      pulsePointsEarned: 180,
      isCompleted: false,
      hotelName: 'Radisson Blu Resort (LEED Gold)',
      hotelRating: 4.6,
      isStepFreeAccessible: true,
      totalBudgetInr: 2800,
      aqiStatus: 'Pristine Coastal Breeze (AQI 34)',
      transitCostInr: 380,
      dailyItinerary: [
        TripDaySchedule(
          dayNumber: 1,
          dayTitle: 'Mandwa to Varsoli Coastal Loop',
          activities: [
            TripActivity(
              time: '08:00 AM',
              title: 'M2M Ro-Pax Hybrid Ferry',
              description: 'Ferry Wharf Mumbai to Mandwa Port (Level Boarding)',
              transportType: 'Train',
              isAccessible: true,
              co2Grams: 45,
              costInr: 380,
            ),
            TripActivity(
              time: '10:00 AM',
              title: 'Electric AC Feeder Bus',
              description: 'Mandwa to Alibaug City Center',
              transportType: 'E-Bus',
              isAccessible: true,
              co2Grams: 20,
              costInr: 35,
            ),
            TripActivity(
              time: '12:30 PM',
              title: 'Kolaba Fort Low-Tide Walk',
              description: 'Step-free viewing ramp & solar information kiosk',
              transportType: 'Walk',
              isAccessible: true,
              co2Grams: 0,
              costInr: 50,
            ),
            TripActivity(
              time: '05:30 PM',
              title: 'Varsoli Sunset & Organic Coconut Grove',
              description: 'Locally preserved coastal mangrove walk',
              transportType: 'Walk',
              isAccessible: true,
              co2Grams: 0,
              costInr: 0,
            ),
          ],
        ),
      ],
    ),
    const TripPlan(
      id: 'trip_mumbai_done_01',
      destination: 'Mumbai Heritage',
      title: 'South Mumbai Green & Art Deco Corridor',
      durationDays: 1,
      travelDates: 'Completed: Aug 28, 2026',
      travelMode: 'Metro Line 3 (Aqua Line Electric)',
      co2SavedKg: 6.8,
      pulsePointsEarned: 140,
      isCompleted: true,
      hotelName: 'The Taj Mahal Palace (Green Key Certified)',
      hotelRating: 4.9,
      isStepFreeAccessible: true,
      totalBudgetInr: 650,
      aqiStatus: 'Moderate Sea Breeze (AQI 58)',
      transitCostInr: 40,
      dailyItinerary: [
        TripDaySchedule(
          dayNumber: 1,
          dayTitle: 'Art Deco & Step-Free Promenade',
          activities: [
            TripActivity(
              time: '09:30 AM',
              title: 'Metro Line 3 Underground',
              description: 'BKC to Churchgate (100% Elevator & Tactile Paving)',
              transportType: 'Metro',
              isAccessible: true,
              co2Grams: 12,
              costInr: 40,
            ),
            TripActivity(
              time: '11:00 AM',
              title: 'CSMT Heritage Museum',
              description: 'Audio-guided & ramp accessible gothic architecture',
              transportType: 'Walk',
              isAccessible: true,
              co2Grams: 0,
              costInr: 50,
            ),
            TripActivity(
              time: '03:00 PM',
              title: 'Marine Drive Low-Emission Walk',
              description: 'Clean energy pedestrian zone',
              transportType: 'Walk',
              isAccessible: true,
              co2Grams: 0,
              costInr: 0,
            ),
          ],
        ),
      ],
    ),
  ];
}
