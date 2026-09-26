import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/agents/raah/day_planner.dart';
import 'package:urbanpulse/domain/opening_hours.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/services/data/forecast_client.dart';

const centre = LatLng(10.0889, 77.0595);

Hotspot spot(String id, double dLat, double dLng, {HotspotKind kind = HotspotKind.nature, int mins = 90, String? hours, bool outdoor = true, double score = 0.6, int fee = 0}) => Hotspot(
  id: id,
  name: 'Place $id',
  location: LatLng(centre.latitude + dLat, centre.longitude + dLng),
  kind: kind,
  visitMinutes: mins,
  openingHours: hours,
  isOutdoor: outdoor,
  score: score,
  feeInr: fee,
);

TransportLeg train(String from, String to, {int minutes = 600}) =>
    TransportLeg(id: 'intercity.train', from: from, to: to, mode: TripTransportMode.train, distanceKm: 900, durationMin: minutes, costInr: 3000);

DayPlanInput input(
  List<Hotspot> places, {
  DateTime? start,
  DateTime? end,
  int travellers = 2,
  Map<String, DayForecast> weather = const {},
  Set<String> banned = const {},
  TransportLeg? arrival,
  TransportLeg? departure,
  Set<AccessibilityNeed> needs = const {},
  List<Hotspot> alternates = const [],
}) => DayPlanInput(
  start: start ?? DateTime(2026, 10, 12, 8),
  end: end ?? DateTime(2026, 10, 15, 20),
  base: centre,
  baseName: 'Hotel',
  places: places,
  alternates: alternates,
  travellers: travellers,
  weather: weather,
  bannedOutdoorDates: banned,
  arrival: arrival,
  departure: departure,
  needs: needs,
);

List<ItinerarySlot> visits(DayPlanResult r) => [for (final d in r.days) for (final s in d.slots) if (s.kind == SlotKind.visit) s];

void main() {
  final sample = [
    spot('a', 0.06, 0.02, hours: 'Sa-Th 08:00-16:00', fee: 200, mins: 180),
    spot('b', 0.03, 0.05, mins: 60),
    spot('c', 0.005, 0.005, kind: HotspotKind.culture, outdoor: false, hours: 'Tu-Su 10:00-16:00', fee: 125, mins: 75),
    spot('d', 0.09, 0.09, kind: HotspotKind.viewpoint, mins: 60),
    spot('e', 0.05, 0.06, kind: HotspotKind.viewpoint, mins: 45),
    spot('f', -0.03, -0.02, mins: 60),
    spot('g', 0.004, 0.002, kind: HotspotKind.food, mins: 60),
    spot('h', 0.02, 0.15, mins: 150, fee: 500),
  ];

  test('every day of the trip is present, in order, with sorted non-inverted slots', () {
    final r = DayPlanner.plan(input(sample));
    expect(r.days.map((d) => d.number), [1, 2, 3, 4]);
    for (final d in r.days) {
      for (var i = 0; i < d.slots.length; i++) {
        expect(d.slots[i].end.isBefore(d.slots[i].start), isFalse, reason: d.slots[i].title);
        if (i > 0) expect(d.slots[i].start.isBefore(d.slots[i - 1].start), isFalse);
      }
    }
  });

  test('a place is used at most once, and only places that were given', () {
    final r = DayPlanner.plan(input(sample));
    final ids = visits(r).map((s) => s.refId).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids.every((id) => sample.any((h) => h.id == id)), isTrue);
  });

  test('opening hours are respected: nothing is scheduled while closed', () {
    final r = DayPlanner.plan(input(sample, start: DateTime(2026, 10, 12, 8), end: DateTime(2026, 10, 16, 20)));
    for (final d in r.days) {
      for (final s in d.slots.where((s) => s.kind == SlotKind.visit)) {
        final h = sample.firstWhere((x) => x.id == s.refId);
        final hours = OpeningHours.parse(h.openingHours);
        expect(hours.isOpenFor(d.date.weekday, s.start.hour * 60 + s.start.minute, s.duration.inMinutes) ?? true, isTrue, reason: '${s.title} on ${d.date}');
      }
    }
  });

  test('arrival and departure leave the days their real length', () {
    final r = DayPlanner.plan(input(sample, start: DateTime(2026, 10, 12, 6), end: DateTime(2026, 10, 15, 23), arrival: train('Pune', 'Munnar', minutes: 12 * 60), departure: train('Munnar', 'Pune', minutes: 12 * 60)));
    final arrivalAt = DateTime(2026, 10, 12, 18);
    final leaveAt = DateTime(2026, 10, 15, 11);
    for (final s in visits(r)) {
      expect(s.start.isBefore(arrivalAt), isFalse, reason: 'not before arriving: ${s.title}');
      expect(s.end.isAfter(leaveAt), isFalse, reason: 'not after leaving: ${s.title}');
    }
    expect(r.days.first.slots.any((s) => s.title.startsWith('Check in')), isTrue);
    expect(r.days.last.slots.any((s) => s.title.startsWith('Check out')), isTrue);
  });

  test('outdoor places are kept off a banned (rainy) day', () {
    final r = DayPlanner.plan(input(sample, banned: {'2026-10-13'}));
    final day2 = r.days.firstWhere((d) => d.date.day == 13);
    for (final s in day2.slots.where((s) => s.kind == SlotKind.visit)) {
      expect(sample.firstWhere((h) => h.id == s.refId).isOutdoor, isFalse, reason: s.title);
    }
  });

  test('a rainy forecast is reported with the outdoor places on that day', () {
    final wet = {for (var d = 12; d <= 15; d++) '2026-10-$d': const DayForecast(date: 'x', rainMm: 30, rainProbability: 95, weatherCode: 65)};
    final r = DayPlanner.plan(input(sample, weather: wet));
    expect(r.rainConflicts, isNotEmpty);
    for (final c in r.rainConflicts) {
      expect(c.places.every((h) => h.isOutdoor && h.kind != HotspotKind.food), isTrue);
    }
  });

  test('meals are added, food places are used for them and never as sightseeing', () {
    final r = DayPlanner.plan(input(sample));
    final all = [for (final d in r.days) ...d.slots];
    expect(all.any((s) => s.kind == SlotKind.meal), isTrue);
    expect(visits(r).any((s) => s.refId == 'g'), isFalse);
  });

  test('walking is used for very short hops, never for a wheelchair user beyond a few metres', () {
    final close = [spot('x', 0.001, 0.0), spot('y', 0.0015, 0.0005)];
    final walker = DayPlanner.plan(input(close));
    expect(walker.days.any((d) => d.slots.any((s) => s.leg?.walking == true)), isTrue);
    final chair = DayPlanner.plan(input(close, needs: {AccessibilityNeed.wheelchair}));
    for (final d in chair.days) {
      for (final s in d.slots) {
        if (s.leg?.walking == true) expect(s.leg!.distanceKm, lessThanOrEqualTo(0.25));
      }
    }
  });

  test('the group pays: children pay half the entry fee', () {
    final r = DayPlanner.plan(DayPlanInput(
      start: DateTime(2026, 10, 12, 8),
      end: DateTime(2026, 10, 12, 20),
      base: centre,
      baseName: 'Hotel',
      places: [spot('f', 0.001, 0.001, fee: 100, mins: 60)],
      travellers: 4,
      children: 2,
    ));
    expect(visits(r).single.costInr, 300, reason: '2 adults × 100 + 2 children × 50');
  });

  group('it never fails', () {
    test('no places, one place, no usable time, an inverted range', () {
      expect(() => DayPlanner.plan(input(const [])), returnsNormally);
      expect(DayPlanner.plan(input([sample.first])).days, isNotEmpty);
      final none = DayPlanner.plan(input(sample, start: DateTime(2026, 10, 12, 8), end: DateTime(2026, 10, 12, 9)));
      expect(none.days, hasLength(1));
      expect(visits(none), isEmpty);
      expect(() => DayPlanner.plan(input(sample, start: DateTime(2026, 10, 15), end: DateTime(2026, 10, 12))), returnsNormally);
    });

    test('a huge trip is capped, and sixty places in a day are handled', () {
      final many = [for (var i = 0; i < 60; i++) spot('p$i', (i % 10) * 0.004, (i ~/ 10) * 0.004)];
      final one = DayPlanner.plan(input(many, end: DateTime(2026, 10, 12, 21)));
      expect(one.days, hasLength(1));
      expect(one.unscheduled, isNotEmpty);
      final year = DayPlanner.plan(input(many, end: DateTime(2027, 10, 12)));
      expect(year.days.length, lessThanOrEqualTo(30));
    });

    test('fuzz: random places, hours, weather and windows', () {
      final rng = Random(7);
      for (var i = 0; i < 120; i++) {
        final n = rng.nextInt(25);
        final places = [
          for (var k = 0; k < n; k++)
            spot(
              'r$k',
              rng.nextDouble() * 0.3 - 0.15,
              rng.nextDouble() * 0.3 - 0.15,
              kind: HotspotKind.values[rng.nextInt(HotspotKind.values.length)],
              mins: 10 + rng.nextInt(400),
              hours: [null, '24/7', 'Mo-Fr 09:00-17:00', 'Sa,Su 10:00-14:00', 'garbage', 'Tu 08:00-12:00'][rng.nextInt(6)],
              outdoor: rng.nextBool(),
              score: rng.nextDouble(),
              fee: rng.nextInt(1000),
            ),
        ];
        final start = DateTime(2026, 10, 1 + rng.nextInt(20), rng.nextInt(24));
        final end = start.add(Duration(hours: rng.nextInt(24 * 12)));
        final r = DayPlanner.plan(input(
          places,
          start: start,
          end: end,
          travellers: 1 + rng.nextInt(12),
          arrival: rng.nextBool() ? train('A', 'B', minutes: rng.nextInt(2000)) : null,
          departure: rng.nextBool() ? train('B', 'A', minutes: rng.nextInt(2000)) : null,
          banned: rng.nextBool() ? {'2026-10-${5 + rng.nextInt(10)}'} : const {},
          needs: rng.nextBool() ? {AccessibilityNeed.wheelchair} : const {},
          alternates: [spot('alt', 0.01, 0.01, outdoor: false)],
        ));
        final ids = visits(r).map((s) => s.refId).toList();
        expect(ids.toSet().length, ids.length, reason: 'run $i: a place twice');
        expect(r.days, isNotEmpty, reason: 'run $i');
        for (final d in r.days) {
          for (final s in d.slots) {
            expect(s.end.isBefore(s.start), isFalse, reason: 'run $i: ${s.title}');
          }
        }
      }
    });
  });
}
