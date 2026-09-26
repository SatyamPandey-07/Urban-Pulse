import 'package:latlong2/latlong.dart';

import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../runtime/report.dart';

/// A sample three-day Jaipur trip for the weather twin when the traveller has
/// not planned one yet. Real places and coordinates; times, fares and fees are
/// typical values, and the trip says it is a sample.
abstract final class TwinDemo {
  static const hotelPoint = LatLng(26.9181, 75.7960);

  static Itinerary jaipur({DateTime? start}) {
    final today = DateTime.now();
    final d0 = start ?? DateTime(today.year, today.month, today.day).add(const Duration(days: 5));
    DateTime at(int day, int h, int m) => DateTime(d0.year, d0.month, d0.day + day, h, m);

    const hotel = HotelOption(
      id: 'demo-hotel',
      name: 'ITC Rajputana',
      location: hotelPoint,
      address: 'Palace Road, Gopalbari, Jaipur',
      rating: 4.5,
      nightlyInr: 9000,
      totalStayInr: 18000,
      provenance: Provenance(source: 'Sample trip'),
    );

    const hawa = LatLng(26.9239, 75.8267);
    const cityPalace = LatLng(26.9258, 75.8237);
    const jantar = LatLng(26.9248, 75.8246);
    const johari = LatLng(26.9196, 75.8267);
    const lmb = LatLng(26.9195, 75.8237);
    const amber = LatLng(26.9855, 75.8513);
    const panna = LatLng(26.9876, 75.8538);
    const jal = LatLng(26.9534, 75.8462);
    const nahargarh = LatLng(26.9373, 75.8155);
    const albert = LatLng(26.9116, 75.8195);
    const birla = LatLng(26.8921, 75.8155);
    const patrika = LatLng(26.8418, 75.8027);

    var n = 0;
    ItinerarySlot leg(int day, int h1, int m1, int h2, int m2, String from, String to, LatLng a, LatLng b, double km, {bool walk = false, int cost = 0}) {
      final minutes = at(day, h2, m2).difference(at(day, h1, m1)).inMinutes;
      return ItinerarySlot(
        kind: SlotKind.transit,
        start: at(day, h1, m1),
        end: at(day, h2, m2),
        title: walk ? 'Walk to $to' : 'Cab to $to',
        leg: TransportLeg(
          id: 'demo-leg-${n++}',
          from: from,
          to: to,
          mode: walk ? TripTransportMode.metroLocal : TripTransportMode.carTaxi,
          distanceKm: km,
          durationMin: minutes,
          costInr: cost,
          co2Grams: walk ? 0 : (TripTransportMode.carTaxi.gCo2PerPaxKm * km).round(),
          walking: walk,
          fromPoint: a,
          toPoint: b,
        ),
      );
    }

    ItinerarySlot visit(int day, int h1, int m1, int h2, int m2, String name, LatLng p, {int fee = 0}) => ItinerarySlot(
      kind: SlotKind.visit,
      start: at(day, h1, m1),
      end: at(day, h2, m2),
      title: name,
      location: p,
      refId: 'demo-${name.toLowerCase().replaceAll(' ', '-')}',
      costInr: fee,
    );

    ItinerarySlot meal(int day, int h1, int m1, int h2, int m2, String name, LatLng p, int cost) =>
        ItinerarySlot(kind: SlotKind.meal, start: at(day, h1, m1), end: at(day, h2, m2), title: name, location: p, costInr: cost);

    final days = [
      ItineraryDay(
        number: 1,
        date: at(0, 0, 0),
        title: 'The walled Pink City',
        slots: [
          ItinerarySlot(kind: SlotKind.stay, start: at(0, 12, 0), end: at(0, 12, 30), title: 'Check in at ITC Rajputana', location: hotelPoint),
          leg(0, 14, 0, 14, 25, 'ITC Rajputana', 'Hawa Mahal', hotelPoint, hawa, 3.4, cost: 180),
          visit(0, 14, 30, 15, 30, 'Hawa Mahal', hawa, fee: 200),
          leg(0, 15, 30, 15, 40, 'Hawa Mahal', 'City Palace', hawa, cityPalace, 0.6, walk: true),
          visit(0, 15, 40, 17, 10, 'City Palace', cityPalace, fee: 700),
          leg(0, 17, 10, 17, 15, 'City Palace', 'Jantar Mantar', cityPalace, jantar, 0.3, walk: true),
          visit(0, 17, 15, 18, 15, 'Jantar Mantar', jantar, fee: 200),
          leg(0, 18, 15, 18, 30, 'Jantar Mantar', 'Johari Bazaar', jantar, johari, 0.9, walk: true),
          visit(0, 18, 30, 19, 45, 'Johari Bazaar', johari),
          leg(0, 19, 45, 20, 0, 'Johari Bazaar', 'Laxmi Mishthan Bhandar', johari, lmb, 0.4, walk: true),
          meal(0, 20, 0, 21, 0, 'Dinner at Laxmi Mishthan Bhandar', lmb, 900),
          leg(0, 21, 0, 21, 20, 'Laxmi Mishthan Bhandar', 'ITC Rajputana', lmb, hotelPoint, 3.2, cost: 170),
        ],
      ),
      ItineraryDay(
        number: 2,
        date: at(1, 0, 0),
        title: 'Forts of the Aravallis',
        slots: [
          leg(1, 8, 30, 9, 10, 'ITC Rajputana', 'Amber Fort', hotelPoint, amber, 13, cost: 450),
          visit(1, 9, 15, 12, 0, 'Amber Fort', amber, fee: 500),
          leg(1, 12, 0, 12, 10, 'Amber Fort', 'Panna Meena ka Kund', amber, panna, 0.7, walk: true),
          visit(1, 12, 10, 12, 50, 'Panna Meena ka Kund', panna),
          meal(1, 13, 0, 14, 0, 'Lunch near Amer', panna, 800),
          leg(1, 14, 15, 14, 40, 'Amer', 'Jal Mahal', panna, jal, 6, cost: 220),
          visit(1, 14, 45, 15, 30, 'Jal Mahal', jal),
          leg(1, 15, 45, 16, 20, 'Jal Mahal', 'Nahargarh Fort', jal, nahargarh, 12, cost: 380),
          visit(1, 16, 30, 18, 45, 'Nahargarh Fort', nahargarh, fee: 200),
          leg(1, 19, 0, 19, 40, 'Nahargarh Fort', 'ITC Rajputana', nahargarh, hotelPoint, 8, cost: 300),
        ],
      ),
      ItineraryDay(
        number: 3,
        date: at(2, 0, 0),
        title: 'Museums and the new city',
        slots: [
          leg(2, 9, 0, 9, 20, 'ITC Rajputana', 'Albert Hall Museum', hotelPoint, albert, 4, cost: 170),
          visit(2, 9, 30, 11, 30, 'Albert Hall Museum', albert, fee: 300),
          leg(2, 11, 30, 11, 45, 'Albert Hall Museum', 'Birla Mandir', albert, birla, 2.4, cost: 120),
          visit(2, 11, 50, 12, 40, 'Birla Mandir', birla),
          meal(2, 13, 0, 14, 0, 'Lunch at Tapri Central', birla, 700),
          leg(2, 14, 15, 14, 35, 'Tapri Central', 'Patrika Gate', birla, patrika, 5, cost: 200),
          visit(2, 14, 40, 15, 40, 'Patrika Gate', patrika),
          leg(2, 16, 0, 16, 30, 'Patrika Gate', 'ITC Rajputana', patrika, hotelPoint, 9, cost: 260),
          ItinerarySlot(kind: SlotKind.stay, start: at(2, 16, 30), end: at(2, 17, 0), title: 'Check out of ITC Rajputana', location: hotelPoint),
        ],
      ),
    ];

    return Itinerary(
      id: 'demo-jaipur',
      createdAt: today,
      destination: 'Jaipur',
      origin: 'Mumbai',
      start: at(0, 12, 0),
      end: at(2, 17, 0),
      travellerSummary: '2 adults · sample trip',
      hotel: hotel,
      days: days,
      budget: const Budget(
        lines: [
          BudgetLine(label: 'ITC Rajputana, 2 nights', amountInr: 18000, category: BudgetCategory.stay),
          BudgetLine(label: 'Cabs in Jaipur', amountInr: 2450, category: BudgetCategory.transport),
          BudgetLine(label: 'Entry fees', amountInr: 2100, category: BudgetCategory.activities),
          BudgetLine(label: 'Meals', amountInr: 2400, category: BudgetCategory.food),
        ],
      ),
      assumptions: const ['A sample trip for the weather twin. Plan your own with Yatri and open its twin from the itinerary.'],
    );
  }
}
