import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';
import 'package:urbanpulse/models/trip_brief.dart';

/// A finished three-day plan, in the shape `PlannerOrchestrator` hands back when
/// Bhatkanti, Atithi, Safar and Hisab have all reported: a chosen hotel, a
/// timeline per day with coordinates and costs, a budget broken down by line,
/// and a green report.
///
/// It is anchored to [from] (midnight of the given day, today by default) so the
/// watch has a live "now" and "next" to show rather than a plan in the past.
Itinerary demoItinerary({DateTime? from}) {
  final base = from ?? DateTime.now();
  final day1 = DateTime(base.year, base.month, base.day);
  DateTime at(int dayOffset, int hour, [int minute = 0]) =>
      day1.add(Duration(days: dayOffset)).add(Duration(hours: hour, minutes: minute));

  const hotel = HotelOption(
    id: 'hotel_ganga_view',
    name: 'Ganga View Homestay',
    location: LatLng(30.1068, 78.2947),
    address: 'Swarg Ashram Road, Rishikesh',
    type: 'Homestay',
    rating: 4.4,
    reviewCount: 612,
    nightlyInr: 2800,
    totalStayInr: 8400,
    priceIsEstimated: false,
    cheapestOta: 'Booking.com',
    ecoScore: 0.78,
    labels: ['Solar water', 'Step-free entrance'],
    priceBand: 'average',
  );

  final toRishikesh = TransportLeg(
    id: 'leg_delhi_rishikesh',
    from: 'Delhi',
    to: 'Rishikesh',
    mode: TripTransportMode.train,
    distanceKm: 236,
    durationMin: 300,
    costInr: 1740,
    co2Grams: 9400,
    stepFree: true,
    isEstimated: false,
    note: 'Dehradun Jan Shatabdi, 06:50 from Delhi',
  );

  final days = [
    ItineraryDay(
      number: 1,
      date: at(0, 0),
      title: 'Arrive and settle by the river',
      weather: '31°C, 20% rain',
      slots: [
        ItinerarySlot(
          kind: SlotKind.transit,
          start: at(0, 6, 50),
          end: at(0, 11, 50),
          title: 'Train to Rishikesh',
          leg: toRishikesh,
          costInr: 1740,
          location: const LatLng(30.1087, 78.2932),
        ),
        ItinerarySlot(
          kind: SlotKind.stay,
          start: at(0, 12, 30),
          end: at(0, 13, 30),
          title: 'Check in — Ganga View Homestay',
          refId: hotel.id,
          location: hotel.location,
          note: 'Ground-floor room held for the group',
        ),
        ItinerarySlot(
          kind: SlotKind.meal,
          start: at(0, 13, 30),
          end: at(0, 14, 30),
          title: 'Lunch at Chotiwala',
          costInr: 620,
          location: const LatLng(30.1246, 78.3197),
        ),
        ItinerarySlot(
          kind: SlotKind.visit,
          start: at(0, 17, 0),
          end: at(0, 18, 30),
          title: 'Ganga Aarti at Triveni Ghat',
          location: const LatLng(30.1087, 78.2932),
          note: 'Arrive 20 min early for a step-free spot',
          flags: ['Crowded after 17:30'],
        ),
        ItinerarySlot(
          kind: SlotKind.rest,
          start: at(0, 20, 0),
          end: at(0, 21, 0),
          title: 'Dinner at the homestay',
          costInr: 450,
        ),
      ],
    ),
    ItineraryDay(
      number: 2,
      date: at(1, 0),
      title: 'Temples and the valley',
      weather: '29°C, clear',
      slots: [
        ItinerarySlot(
          kind: SlotKind.meal,
          start: at(1, 8, 0),
          end: at(1, 8, 45),
          title: 'Breakfast',
          costInr: 300,
        ),
        ItinerarySlot(
          kind: SlotKind.transit,
          start: at(1, 9, 0),
          end: at(1, 10, 0),
          title: 'Shared taxi to Neelkanth',
          costInr: 900,
          location: const LatLng(30.1571, 78.3888),
          flags: ['Needs confirmation'],
        ),
        ItinerarySlot(
          kind: SlotKind.visit,
          start: at(1, 10, 0),
          end: at(1, 12, 0),
          title: 'Neelkanth Mahadev Temple',
          location: const LatLng(30.1571, 78.3888),
          note: 'Steep last 200 m — ramp on the north side',
        ),
        ItinerarySlot(
          kind: SlotKind.meal,
          start: at(1, 13, 0),
          end: at(1, 14, 0),
          title: 'Lunch at Beatles Cafe',
          costInr: 700,
          location: const LatLng(30.1284, 78.3237),
        ),
        ItinerarySlot(
          kind: SlotKind.visit,
          start: at(1, 15, 30),
          end: at(1, 17, 0),
          title: 'Laxman Jhula and the riverside market',
          location: const LatLng(30.1276, 78.3212),
        ),
      ],
    ),
    ItineraryDay(
      number: 3,
      date: at(2, 0),
      title: 'Morning on the water, then home',
      weather: '30°C, 10% rain',
      slots: [
        ItinerarySlot(
          kind: SlotKind.visit,
          start: at(2, 7, 30),
          end: at(2, 10, 0),
          title: 'Rafting, Shivpuri to Rishikesh',
          costInr: 2400,
          location: const LatLng(30.1428, 78.3765),
          flags: ['Life jackets included'],
        ),
        ItinerarySlot(
          kind: SlotKind.stay,
          start: at(2, 11, 0),
          end: at(2, 11, 30),
          title: 'Check out',
          refId: hotel.id,
          location: hotel.location,
        ),
        ItinerarySlot(
          kind: SlotKind.transit,
          start: at(2, 13, 0),
          end: at(2, 18, 30),
          title: 'Train back to Delhi',
          costInr: 1740,
          location: const LatLng(30.1087, 78.2932),
        ),
      ],
    ),
  ];

  return Itinerary(
    id: 'demo_rishikesh_3d',
    createdAt: base,
    destination: 'Rishikesh',
    origin: 'Delhi',
    start: at(0, 0),
    end: at(2, 23, 59),
    travellerSummary: '2 adults, 1 senior',
    hotel: hotel,
    transportOptions: [toRishikesh],
    chosenTransport: toRishikesh,
    days: days,
    budget: const Budget(
      budgetMinInr: 18000,
      budgetMaxInr: 30000,
      lines: [
        BudgetLine(label: 'Ganga View Homestay, 3 nights', amountInr: 8400, category: BudgetCategory.stay, isEstimated: false),
        BudgetLine(label: 'Train, both ways', amountInr: 3480, category: BudgetCategory.transport, isEstimated: false),
        BudgetLine(label: 'Local taxis', amountInr: 1800, category: BudgetCategory.transport),
        BudgetLine(label: 'Rafting', amountInr: 2400, category: BudgetCategory.activities, isEstimated: false),
        BudgetLine(label: 'Meals', amountInr: 4200, category: BudgetCategory.food),
        BudgetLine(label: 'Buffer', amountInr: 2000, category: BudgetCategory.buffer),
      ],
    ),
    green: const GreenReport(
      co2Kg: 38.4,
      co2SavedKg: 61.2,
      score: 74,
      tips: ['The train saves 61 kg CO₂ against driving'],
    ),
    assumptions: ['Taxi fares are typical September rates, not quoted'],
    confidence: 0.72,
  );
}
