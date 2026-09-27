import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/services/watch/watch_plan_builder.dart';
import 'package:urbanpulse/services/watch/watch_protocol.dart';

final base = DateTime(2026, 10, 12);
DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 12, h, m);

TransportLeg leg({
  String from = 'Panvel',
  String to = 'CST',
  TripTransportMode mode = TripTransportMode.train,
  bool walking = false,
}) => TransportLeg(
  id: 'l',
  from: from,
  to: to,
  mode: mode,
  distanceKm: 40,
  durationMin: 70,
  costInr: 40,
  walking: walking,
);

void main() {
  group('buildWatchPlan', () {
    test('numbers the steps in time order from one', () {
      final day = ItineraryDay(
        number: 2,
        date: base,
        title: 'Day out',
        slots: [
          // Deliberately out of order.
          ItinerarySlot(kind: SlotKind.meal, start: at(13), end: at(14), title: 'Lunch at Laxmi'),
          ItinerarySlot(
            kind: SlotKind.transit,
            start: at(9),
            end: at(10),
            title: 'Train',
            leg: leg(),
          ),
          ItinerarySlot(kind: SlotKind.visit, start: at(11), end: at(12), title: 'Gateway of India'),
        ],
      );

      final steps = buildWatchPlan(day);
      expect(steps.map((s) => s.number), [1, 2, 3]);
      expect(steps.map((s) => s.at), ['09:00', '11:00', '13:00']);
    });

    test('a transit leg reads as a whole instruction', () {
      final day = ItineraryDay(
        number: 1,
        date: base,
        title: 'd',
        slots: [
          ItinerarySlot(
            kind: SlotKind.transit,
            start: at(9),
            end: at(10),
            title: 'Train',
            leg: leg(from: 'Panvel', to: 'CST'),
          ),
        ],
      );
      expect(buildWatchPlan(day).single.text, 'Take the train from Panvel to CST');
      expect(buildWatchPlan(day).single.mode, WatchStepMode.train);
    });

    test('a walking leg says walk, not its placeholder mode', () {
      final day = ItineraryDay(
        number: 1,
        date: base,
        title: 'd',
        slots: [
          ItinerarySlot(
            kind: SlotKind.transit,
            start: at(9),
            end: at(10),
            title: 'Walk',
            // `mode` is a placeholder when walking is true and must not surface.
            leg: leg(from: 'Hotel', to: 'Fort', mode: TripTransportMode.carTaxi, walking: true),
          ),
        ],
      );
      final step = buildWatchPlan(day).single;
      expect(step.text, 'Walk from Hotel to Fort');
      expect(step.mode, WatchStepMode.walk);
      expect(step.text.toLowerCase(), isNot(contains('taxi')));
    });

    test('says only what is known when a leg has no endpoints', () {
      final day = ItineraryDay(
        number: 1,
        date: base,
        title: 'd',
        slots: [
          ItinerarySlot(
            kind: SlotKind.transit,
            start: at(9),
            end: at(10),
            title: 'Metro to the museum',
            leg: leg(from: '', to: ''),
          ),
        ],
      );
      // No invented "from" or dangling "to".
      expect(buildWatchPlan(day).single.text, 'Metro to the museum');
    });

    test('does not double a verb the title already has', () {
      final day = ItineraryDay(
        number: 1,
        date: base,
        title: 'd',
        slots: [
          ItinerarySlot(kind: SlotKind.visit, start: at(9), end: at(10), title: 'Visit Amber Fort'),
          ItinerarySlot(kind: SlotKind.visit, start: at(11), end: at(12), title: 'Amber Fort'),
        ],
      );
      final steps = buildWatchPlan(day);
      expect(steps[0].text, 'Visit Amber Fort');
      expect(steps[1].text, 'Visit Amber Fort');
    });

    test('drops rest slots, which are not instructions', () {
      final day = ItineraryDay(
        number: 1,
        date: base,
        title: 'd',
        slots: [
          ItinerarySlot(kind: SlotKind.rest, start: at(12), end: at(13), title: 'Free time'),
          ItinerarySlot(kind: SlotKind.visit, start: at(14), end: at(15), title: 'Museum'),
        ],
      );
      final steps = buildWatchPlan(day);
      expect(steps, hasLength(1));
      expect(steps.single.number, 1);
    });

    test('maps every transport mode to something the watch draws', () {
      for (final mode in TripTransportMode.values) {
        final day = ItineraryDay(
          number: 1,
          date: base,
          title: 'd',
          slots: [
            ItinerarySlot(
              kind: SlotKind.transit,
              start: at(9),
              end: at(10),
              title: 't',
              leg: leg(mode: mode),
            ),
          ],
        );
        expect(buildWatchPlan(day).single.mode, isNot(WatchStepMode.other));
      }
    });
  });

  group('chunkWatchPlan', () {
    List<WatchStep> steps(int n, {int chars = 40}) => [
      for (var i = 1; i <= n; i++)
        WatchStep(number: i, at: '09:00', text: 'x' * chars, mode: WatchStepMode.walk),
    ];

    test('every chunk fits one transmit', () {
      for (final count in [1, 5, 12, 40]) {
        final messages = chunkWatchPlan(steps(count), ts: base, day: 'Day 2');
        for (final m in messages) {
          expect(
            fitsOneTransmit(m.toWire()),
            isTrue,
            reason: 'chunk of a $count-step plan overflowed',
          );
        }
      }
    });

    test('every step is carried exactly once, in order', () {
      final all = steps(17);
      final messages = chunkWatchPlan(all, ts: base);
      final seen = <int>[];
      for (final m in messages) {
        for (var i = 0; i < m.steps.length; i++) {
          // `from` is the index of the chunk's first step.
          expect(m.steps[i].number, all[m.from + i].number);
          seen.add(m.steps[i].number);
        }
      }
      expect(seen, List.generate(17, (i) => i + 1));
    });

    test('every chunk reports the whole plan length', () {
      for (final m in chunkWatchPlan(steps(17), ts: base)) {
        // So the watch can show "3/17" before the last chunk lands.
        expect(m.total, 17);
      }
    });

    test('long steps make more chunks than short ones', () {
      final short = chunkWatchPlan(steps(20, chars: 10), ts: base).length;
      final long = chunkWatchPlan(steps(20, chars: 90), ts: base).length;
      expect(long, greaterThan(short));
    });

    test('an empty day still sends one message, so the watch clears', () {
      final messages = chunkWatchPlan(const [], ts: base);
      expect(messages, hasLength(1));
      expect(messages.single.total, 0);
      expect(messages.single.from, 0);
    });

    test('step text is sanitised and capped', () {
      final step = WatchStep(
        number: 1,
        at: '09:00',
        text: 'Take the tràin from Panvél ${'x' * 200}',
        mode: WatchStepMode.train,
      );
      final text = step.toWire()['x'] as String;
      expect(text.length, lessThanOrEqualTo(WatchStep.maxTextChars));
      for (final unit in text.codeUnits) {
        expect(unit, inInclusiveRange(0x20, 0x7E));
      }
    });
  });
}
