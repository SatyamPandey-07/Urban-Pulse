import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/raah/day_planner.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';

import 'day_planner_test.dart' show centre, spot;

DayPlanInput fixed(List<Hotspot> places, Map<int, List<String>> days, {Map<int, (int, int)> windows = const {}, Map<int, int> caps = const {}}) => DayPlanInput(
  start: DateTime(2026, 10, 12, 8),
  end: DateTime(2026, 10, 14, 20),
  base: centre,
  baseName: 'Hotel',
  places: places,
  travellers: 2,
  fixedDays: days,
  dayWindows: windows,
  dayStopCaps: caps,
);

List<String> ids(DayPlanResult r, int day) => [
  for (final s in r.days[day - 1].slots)
    if (s.kind == SlotKind.visit) s.refId!,
];

void main() {
  final pool = [
    spot('a', 0.01, 0.01, mins: 60),
    spot('b', 0.02, 0.01, mins: 60),
    spot('c', 0.03, 0.02, mins: 60),
    spot('d', 0.01, 0.04, mins: 60),
    spot('e', 0.02, 0.05, mins: 60),
    spot('f', 0.04, 0.03, mins: 60),
  ];

  test('fixed days keep exactly the places asked for, per day, in order', () {
    final r = DayPlanner.plan(fixed(pool, {1: ['a', 'b'], 2: ['c', 'd'], 3: ['e', 'f']}));
    expect(r.days.length, 3);
    expect([for (var d = 1; d <= 3; d++) ids(r, d).toSet()], [
      {'a', 'b'},
      {'c', 'd'},
      {'e', 'f'},
    ]);
  });

  test('places that are not listed are left out, and no spares are added', () {
    final r = DayPlanner.plan(fixed(pool, {1: ['a'], 2: ['b'], 3: []}));
    expect([ids(r, 1), ids(r, 2), ids(r, 3)], [['a'], ['b'], <String>[]]);
  });

  test('an unknown id or a place listed twice is ignored, never duplicated', () {
    final r = DayPlanner.plan(fixed(pool, {1: ['a', 'zzz', 'a'], 2: ['a', 'b']}));
    final all = [for (var d = 1; d <= r.days.length; d++) ...ids(r, d)];
    expect(all.toSet().length, all.length);
    expect(all, isNot(contains('zzz')));
  });

  test('a rest-day window starts later and ends earlier', () {
    final normal = DayPlanner.plan(fixed(pool, {1: ['a'], 2: ['b', 'c'], 3: ['d']}));
    final rest = DayPlanner.plan(fixed(pool, {1: ['a'], 2: ['b', 'c'], 3: ['d']}, windows: {2: (11 * 60, 16 * 60)}));
    int firstVisit(DayPlanResult r) {
      final s = r.days[1].slots.firstWhere((s) => s.kind == SlotKind.visit);
      return s.start.hour * 60 + s.start.minute;
    }

    expect(firstVisit(rest), greaterThanOrEqualTo(11 * 60));
    expect(firstVisit(rest), greaterThan(firstVisit(normal)));
    // the other days are untouched by the window
    expect(ids(rest, 1), ids(normal, 1));
    expect(ids(rest, 3), ids(normal, 3));
  });

  test('a per-day cap limits that day, and what it displaces moves to a later day', () {
    final r = DayPlanner.plan(fixed(pool, {1: ['a', 'b', 'c'], 2: ['d'], 3: []}, caps: {1: 1}));
    expect(ids(r, 1).length, lessThanOrEqualTo(1));
    final all = [for (var d = 1; d <= 3; d++) ...ids(r, d)];
    expect(all.toSet(), {'a', 'b', 'c', 'd'}, reason: 'nothing is silently lost');
  });

  test('out-of-range days in the request are ignored', () {
    final r = DayPlanner.plan(fixed(pool, {0: ['a'], 9: ['b'], 1: ['c']}, windows: {7: (600, 700)}, caps: {-1: 0}));
    expect(r.days.length, 3);
    expect(ids(r, 1), ['c']);
  });
}
