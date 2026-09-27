
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/agents/live/live_mode_engine.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/services/live_location.dart';
import 'package:urbanpulse/state/live_mode_controller.dart';

import '../state/live_map_controller_test.dart' show ScriptedLocation;

final base = DateTime(2026, 10, 12);
DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 12, h, m);

// Places about 1.1 km apart going north from (10, 77).
const fort = LatLng(10.0, 77.0);
const palace = LatLng(10.01, 77.0);

ItineraryDay dayWith({String? weather}) => ItineraryDay(
  number: 2,
  date: base,
  title: 'Old city',
  weather: weather,
  slots: [
    ItinerarySlot(kind: SlotKind.visit, start: at(9, 30), end: at(11), title: 'Amber Fort', location: fort, refId: 'a', note: 'Go early for the light. Bring water.'),
    ItinerarySlot(kind: SlotKind.meal, start: at(13), end: at(14), title: 'Lunch at Laxmi Restaurant', location: palace),
    ItinerarySlot(kind: SlotKind.visit, start: at(15), end: at(17), title: 'City Palace', location: palace, refId: 'p', flags: const ['outdoor']),
  ],
);

void main() {
  group('what Live Mode says', () {
    test('the start: the day, what comes first, and the weather', () {
      final e = LiveModeEngine(day: dayWith(weather: '31°C, 20% rain'));
      final t = e.briefing(at(8)).text;
      expect(t, contains('Day 2: Old city'));
      expect(t, contains('Amber Fort at 9:30 AM'));
      expect(t, contains('31°C, 20% rain'));
    });

    test('a likely rain says which places are outdoors', () {
      final e = LiveModeEngine(day: dayWith(), rainProbability: 80);
      final t = e.briefing(at(8)).text;
      expect(t, contains('about 80 percent'));
      expect(t, contains('City Palace'));
    });

    test('nothing is said too early, and a stop is announced once, 15 minutes before', () {
      final e = LiveModeEngine(day: dayWith());
      expect(e.check(at(8), null), isEmpty);
      final u = e.check(at(9, 20), null);
      expect(u.single.text, 'Amber Fort at 9:30 AM, in 10 minutes.');
      expect(e.check(at(9, 22), null), isEmpty, reason: 'only once');
    });

    test('with a position it says how far, and when it is time to leave', () {
      final e = LiveModeEngine(day: dayWith());
      // 1.1 km from the fort: about 17 minutes on foot; 9:30 - 17 - 5 = 9:08
      const far = LatLng(9.99, 77.0);
      expect(e.check(at(8, 50), far), isEmpty);
      final u = e.check(at(9, 10), far);
      expect(u.single.kind, UpdateKind.leaveNow);
      expect(u.single.text, contains('Time to leave for Amber Fort at 9:30 AM'));
      expect(u.single.text, contains('estimate'));
      expect(e.check(at(9, 15), far), isEmpty, reason: 'leave is said once, and it replaces the countdown');
    });

    test('arriving is noticed near the place, with its note and the time left', () {
      final e = LiveModeEngine(day: dayWith());
      final u = e.check(at(9, 32), const LatLng(10.0003, 77.0));
      expect(u.single.kind, UpdateKind.arrived);
      expect(u.single.text, contains("You've arrived at Amber Fort."));
      expect(u.single.text, contains('Go early for the light.'));
      expect(u.single.text, isNot(contains('Bring water')));
      expect(u.single.text, contains('until 11:00 AM'));
      expect(e.check(at(9, 40), const LatLng(10.0003, 77.0)), isEmpty);
      expect(e.visited, 1);
      expect(e.nextSlot(at(9, 40))!.title, 'Lunch at Laxmi Restaurant');
    });

    test('being far from a place never counts as arriving', () {
      final e = LiveModeEngine(day: dayWith());
      final u = e.check(at(9, 32), const LatLng(10.05, 77.05));
      expect(u.where((x) => x.kind == UpdateKind.arrived), isEmpty);
    });

    test('running late is said once for the next stop', () {
      final e = LiveModeEngine(day: dayWith());
      final u = e.check(at(9, 55), null);
      expect(u.single.kind, UpdateKind.late);
      expect(u.single.text, contains('25 minutes behind for Amber Fort'));
      expect(e.check(at(10, 5), null), isEmpty);
    });

    test('a meal is a reminder, not an arrival', () {
      final e = LiveModeEngine(day: dayWith());
      e.check(at(9, 32), fort); // arrive at the fort
      final u = e.check(at(12, 50), null);
      expect(u.single.kind, UpdateKind.meal);
      expect(u.single.text, startsWith('Lunch at Laxmi Restaurant is coming up at 1:00 PM'));
    });

    test('the end of the day is summed up', () {
      final e = LiveModeEngine(day: dayWith());
      e.check(at(9, 32), fort);
      final u = e.check(at(17, 30), null);
      expect(u.single.kind, UpdateKind.dayDone);
      expect(u.single.text, contains('You reached 1 of 2 places'));
    });

    test('several things due at once: two are spoken, the rest wait', () {
      final busy = ItineraryDay(
        number: 1,
        date: base,
        title: 'Busy',
        slots: [
          for (var i = 0; i < 4; i++) ItinerarySlot(kind: SlotKind.visit, start: at(10, i), end: at(10, 30), title: 'Place $i', location: null),
        ],
      );
      final e = LiveModeEngine(day: busy);
      final first = e.check(at(9, 55), null);
      expect(first.length, 2);
      final second = e.check(at(9, 56), null);
      expect(second.length, 2, reason: 'what waited is said next');
      expect({...first.map((u) => u.id), ...second.map((u) => u.id)}.length, 4);
    });

    test('an empty day says so and never fails', () {
      final e = LiveModeEngine(day: ItineraryDay(number: 1, date: base, title: 'Free', slots: const []));
      expect(e.briefing(at(8)).text, contains('nothing left'));
      expect(e.check(at(12), const LatLng(1, 1)), isEmpty);
    });

    test('travel estimates are on foot up close and by road beyond', () {
      expect(LiveModeEngine.travelEstimate(600).$2, 'on foot');
      expect(LiveModeEngine.travelEstimate(600).$1, inInclusiveRange(9, 12));
      expect(LiveModeEngine.travelEstimate(8000).$2, 'by road');
    });
  });

  group('what the traveller can say', () {
    test('the common requests, in English and Hindi', () {
      final cases = {
        "what's next": LiveCommand.whatsNext,
        'What is the next stop?': LiveCommand.whatsNext,
        'how far is it': LiveCommand.howFar,
        'kitna door hai': LiveCommand.howFar,
        'where am I': LiveCommand.whereAmI,
        'take me there': LiveCommand.navigate,
        'navigate to the next place': LiveCommand.navigate,
        'say that again': LiveCommand.repeatLast,
        'will it rain': LiveCommand.weather,
        'be quiet for a while': LiveCommand.quiet,
        'resume updates': LiveCommand.resume,
        'stop live mode': LiveCommand.stop,
        'what is the plan for today': LiveCommand.today,
        'blah blah': LiveCommand.unknown,
        '': LiveCommand.unknown,
      };
      for (final e in cases.entries) {
        expect(parseLiveCommand(e.key), e.value, reason: e.key);
      }
    });
  });

  group('the controller', () {
    late ScriptedLocation loc;
    late List<String> said;
    late DateTime now;
    late List<(int, String?)> navigated;
    late List<bool> awake;
    late LiveModeController c;

    Itinerary trip() => Itinerary(
      id: 't',
      createdAt: base,
      destination: 'Jaipur',
      origin: 'Delhi',
      start: base,
      end: base,
      days: [dayWith()],
      budget: const Budget(lines: []),
    );

    setUp(() {
      loc = ScriptedLocation()..result = const LocationResult(LocationStatus.ok, UserFix(point: LatLng(9.99, 77.0)));
      said = [];
      navigated = [];
      awake = [];
      now = at(9, 0);
      c = LiveModeController(
        location: loc,
        say: (t) async => said.add(t),
        describe: (p) async => 'MG Road',
        onNavigate: (d, ref) => navigated.add((d.number, ref)),
        keepAwake: awake.add,
        now: () => now,
        checkEvery: const Duration(milliseconds: 20),
      );
    });
    tearDown(() => c.dispose());

    test('starting speaks the briefing, keeps the screen on; stopping lets go', () async {
      await c.start(trip(), dayWith());
      expect(c.active, isTrue);
      expect(said.first, startsWith('Live mode is on. Day 2: Old city.'));
      expect(awake, [true]);
      await c.stop();
      expect(c.active, isFalse);
      expect(awake, [true, false]);
      expect(said.last, 'Live mode is off.');
    });

    test('without a position it says it will go by the clock', () async {
      loc.result = const LocationResult(LocationStatus.serviceOff);
      await c.start(trip(), dayWith());
      expect(said.any((t) => t.contains('only go by the clock')), isTrue);
    });

    test('as time passes it says when to leave, and notices the arrival', () async {
      await c.start(trip(), dayWith());
      said.clear();
      now = at(9, 20);
      await c.tick();
      expect(said.single, contains('Time to leave for Amber Fort at 9:30 AM'));
      loc.positions.add(const UserFix(point: LatLng(10.0002, 77.0)));
      await Future<void>.delayed(Duration.zero);
      now = at(9, 31);
      await c.tick();
      expect(said.last, contains("You've arrived at Amber Fort."));
    });

    test('quiet holds updates back until it ends', () async {
      await c.start(trip(), dayWith());
      said.clear();
      await c.ask('be quiet');
      final n = said.length;
      now = at(9, 20);
      await c.tick();
      expect(said.length, n, reason: 'nothing while quiet');
      now = at(9, 40);
      await c.ask('resume');
      expect(c.quiet, isFalse);
    });

    test('questions are answered from the plan and the position', () async {
      await c.start(trip(), dayWith());
      loc.positions.add(const UserFix(point: LatLng(9.99, 77.0)));
      await Future<void>.delayed(Duration.zero);
      expect(await c.ask("what's next"), contains('Next is Amber Fort at 9:30 AM.'));
      expect(await c.ask('how far'), allOf(contains('Amber Fort is'), contains('on foot'), contains('estimate')));
      expect(await c.ask('where am I'), 'You are near MG Road.');
      expect(await c.ask('repeat'), contains('MG Road'));
      expect(await c.ask('weather'), isNotEmpty);
      expect(await c.ask('what is the plan for today'), contains('City Palace at 3:00 PM'));
      expect(await c.ask('gibberish words'), contains('what is next'));
    });

    test('take me there sets off on the map for the next stop', () async {
      await c.start(trip(), dayWith());
      final a = await c.ask('take me there');
      expect(a, contains('Taking you to Amber Fort'));
      expect(navigated, [(2, 'a')]);
    });

    test('asking when live mode is off says so', () async {
      expect(await c.ask("what's next"), 'Live mode is not on.');
    });

    test('a speech engine that fails does not stop anything', () async {
      final bad = LiveModeController(location: loc, say: (_) async => throw StateError('no audio'), now: () => now);
      addTearDown(bad.dispose);
      await bad.start(trip(), dayWith());
      expect(bad.active, isTrue);
      expect(bad.log, isNotEmpty);
    });

    test('the day that is today is found, or none', () {
      expect(LiveModeController.dayForToday(trip(), at(12))!.number, 2);
      expect(LiveModeController.dayForToday(trip(), DateTime(2026, 10, 20)), isNull);
    });
  });
}
