import 'package:urbanpulse/models/trip_brief.dart';

/// A fixed "now" so date validation is deterministic: Fri 2026-10-02 10:00.
final testNow = DateTime(2026, 10, 2, 10);

/// A brief that satisfies every mandatory field.
TripBrief completeBrief() => TripBrief(
  id: 'b1',
  createdAt: testNow,
  destination: 'Munnar',
  originCity: 'Pune',
  start: DateTime(2026, 10, 10, 9),
  end: DateTime(2026, 10, 13, 18),
  travellerCount: 4,
  adults: 2,
  seniors: 0,
  children: 2,
  women: 1,
  childAges: const [6, 9],
  womenSafety: const {WomenSafetyPref.verifiedStays},
  accessibilityNeeds: const {AccessibilityNeed.none},
  accessibilityConfirmed: true,
  transportModes: const {TripTransportMode.train},
  budgetMinInr: 20000,
  budgetMaxInr: 40000,
);
