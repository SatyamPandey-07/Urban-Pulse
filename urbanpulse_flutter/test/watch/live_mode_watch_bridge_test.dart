import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/services/live_location.dart';
import 'package:urbanpulse/services/watch/live_mode_watch_bridge.dart';
import 'package:urbanpulse/services/watch/watch_link.dart';
import 'package:urbanpulse/services/watch/watch_mirror.dart';
import 'package:urbanpulse/state/live_mode_controller.dart';

import '../state/live_map_controller_test.dart' show ScriptedLocation;

final base = DateTime(2026, 10, 12);
DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 12, h, m);

const fort = LatLng(10.0, 77.0);
const palace = LatLng(10.01, 77.0);

ItineraryDay theDay() => ItineraryDay(
  number: 2,
  date: base,
  title: 'Old city',
  slots: [
    ItinerarySlot(
      kind: SlotKind.visit,
      start: at(9, 30),
      end: at(11),
      title: 'Amber Fort',
      location: fort,
      refId: 'a',
    ),
    ItinerarySlot(
      kind: SlotKind.meal,
      start: at(13),
      end: at(14),
      title: 'Lunch at Laxmi Restaurant',
      location: palace,
    ),
  ],
);

Itinerary theTrip() => Itinerary(
  id: 't',
  createdAt: base,
  destination: 'Jaipur',
  origin: 'Delhi',
  start: base,
  end: base,
  days: [theDay()],
  budget: const Budget(lines: []),
);

void main() {
  late ScriptedWatchLink link;
  late WatchMirror mirror;
  late ScriptedLocation loc;
  late LiveModeController controller;
  late LiveModeWatchBridge bridge;
  late DateTime now;

  LiveModeWatchBridge attach(LiveModeController c) =>
      LiveModeWatchBridge(controller: c, mirror: mirror, now: () => now);

  setUp(() {
    now = at(9);
    link = ScriptedWatchLink();
    mirror = WatchMirror(
      link: link,
      // The rate limiter has its own tests; this one is about what gets mapped.
      limits: const WatchMirrorLimits(
        minAlertGap: Duration.zero,
        maxAlertsPerWindow: 50,
        duplicateWindow: Duration.zero,
        stateRefresh: Duration(minutes: 2),
      ),
      now: () => now,
    )..mirroring = true;
    loc = ScriptedLocation()
      ..result = const LocationResult(LocationStatus.ok, UserFix(point: LatLng(9.99, 77.0)));
    controller = LiveModeController(location: loc, say: (_) async {}, now: () => now);
    bridge = attach(controller);
  });

  tearDown(() {
    bridge.dispose();
    controller.dispose();
    link.dispose();
  });

  test('sends nothing while Live Mode has never run', () async {
    await bridge.sync();
    expect(link.sent, isEmpty);
  });

  test('publishes the next stop once Live Mode is active', () async {
    await controller.start(theTrip(), theDay());
    await bridge.sync();

    final states = link.sentOfType('state');
    expect(states, isNotEmpty);
    final wire = states.last;
    expect(wire['live'], true);
    expect(wire['day'], 'Day 2');
    final next = wire['next'] as Map<String, Object?>;
    expect(next['title'], 'Amber Fort');
    // The slot's own start time, formatted for the watch.
    expect(next['at'], '09:30');
    expect(next['dist'], isA<int>());
  });

  test('omits the distance when the phone has no position', () async {
    loc.result = const LocationResult(LocationStatus.denied);
    final blind = LiveModeController(location: loc, say: (_) async {}, now: () => now);
    final b = attach(blind);
    addTearDown(() {
      b.dispose();
      blind.dispose();
    });

    await blind.start(theTrip(), theDay());
    await b.sync();

    final next = link.sentOfType('state').last['next'] as Map<String, Object?>?;
    // The watch must never be handed a distance the phone does not know.
    if (next != null) expect(next.containsKey('dist'), isFalse);
  });

  test('every alert that goes out carries a kind the watch renders', () async {
    await controller.start(theTrip(), theDay());
    await bridge.sync();
    for (final alert in link.sentOfType('alert')) {
      expect(['leave', 'arrived', 'late', 'meal', 'rain'], contains(alert['kind']));
    }
  });

  test('screen-only kinds are never buzzed', () async {
    await controller.start(theTrip(), theDay());
    await bridge.sync();
    // start() speaks a briefing; it has no wire kind and must not reach the watch.
    for (final alert in link.sentOfType('alert')) {
      expect(alert['kind'], isNot(anyOf('briefing', 'upcoming', 'dayDone', 'info')));
    }
  });

  test('forwards each spoken update only once', () async {
    await controller.start(theTrip(), theDay());
    await bridge.sync();
    final first = link.sentOfType('alert').length;
    // Notifications that changed nothing must not re-buzz the log.
    await bridge.sync();
    await bridge.sync();
    expect(link.sentOfType('alert'), hasLength(first));
  });

  test('says Live Mode is off when it stops', () async {
    await controller.start(theTrip(), theDay());
    await bridge.sync();
    link.sent.clear();

    await controller.stop(announce: false);
    await bridge.sync();

    final states = link.sentOfType('state');
    expect(states, isNotEmpty);
    expect(states.last['live'], false);
    // No stop is claimed once Live Mode is over.
    expect(states.last.containsKey('next'), isFalse);
  });

  test('sends nothing at all while mirroring is off', () async {
    mirror.mirroring = false;
    await controller.start(theTrip(), theDay());
    await bridge.sync();
    expect(link.sent, isEmpty);
  });

  test('sends nothing when no watch is connected', () async {
    link.setStatus(WatchStatus.noDevicePaired);
    await controller.start(theTrip(), theDay());
    await bridge.sync();
    expect(link.sent, isEmpty);
  });
}
