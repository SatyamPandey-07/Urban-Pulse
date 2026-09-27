import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/services/watch/watch_protocol.dart';

void main() {
  group('sanitiseWatchText', () {
    test('keeps plain ASCII unchanged', () {
      expect(sanitiseWatchText('Gateway of India'), 'Gateway of India');
    });

    test('collapses runs of whitespace and trims', () {
      expect(sanitiseWatchText('  Leave   now\tfor\nthe ferry '), 'Leave now for the ferry');
    });

    test('folds Latin-1 accents the watch font cannot draw', () {
      expect(sanitiseWatchText('Café Müller'), 'Cafe Muller');
    });

    test('folds smart punctuation to ASCII', () {
      expect(sanitiseWatchText('It’s 5–10 min — hurry'), "It's 5-10 min - hurry");
    });

    test('replaces anything else with a space rather than a blank box', () {
      // Devanagari has no ASCII equivalent; the words around it must survive.
      expect(sanitiseWatchText('Stop गेट now'), 'Stop now');
    });

    test('turns a rupee sign into something printable', () {
      expect(sanitiseWatchText('₹250 entry'), 'Rs 250 entry');
    });

    test('truncates to the line budget and marks the cut', () {
      final out = sanitiseWatchText(
        'Leave now to reach the Gateway of India before the last ferry departs',
        max: 30,
      );
      expect(out.length, lessThanOrEqualTo(30));
      expect(out, endsWith('...'));
    });

    test('breaks on a word boundary when truncating', () {
      // 20 chars leaves 17 for text; the last space inside that is after "for".
      final out = sanitiseWatchText('Leave now for the ferry terminal', max: 20);
      expect(out, 'Leave now for...');
      expect(out.length, lessThanOrEqualTo(20));
    });

    test('still fits when there is no space to break on', () {
      final out = sanitiseWatchText('Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', max: 10);
      expect(out.length, 10);
      expect(out, endsWith('...'));
    });

    test('handles a budget too small for the ellipsis', () {
      expect(sanitiseWatchText('abcdef', max: 2).length, 2);
      expect(sanitiseWatchText('abcdef', max: 0), '');
    });

    test('output is always pure ASCII', () {
      const messy = 'Café ₹250 — 5°C गेट';
      for (final unit in sanitiseWatchText(messy).codeUnits) {
        expect(unit, inInclusiveRange(0x20, 0x7E));
      }
    });
  });

  group('watchClock', () {
    test('pads to HH:MM on a 24 hour clock', () {
      expect(watchClock(DateTime(2026, 9, 27, 9, 5)), '09:05');
      expect(watchClock(DateTime(2026, 9, 27, 14, 20)), '14:20');
      expect(watchClock(DateTime(2026, 9, 27, 0, 0)), '00:00');
    });
  });

  group('encoding', () {
    final ts = DateTime.utc(2026, 9, 27, 12, 0);

    test('state carries the version and sanitises the title', () {
      final wire = WatchStateMessage(
        live: true,
        day: 'Day 2',
        next: const WatchNextStop(title: 'Café Leopold', at: '14:20', distanceM: 1200),
        ts: ts,
      ).toWire();

      expect(wire['t'], 'state');
      expect(wire['v'], protocolVersion);
      expect(wire['live'], true);
      expect(wire['day'], 'Day 2');
      expect(wire['ts'], watchEpoch(ts));
      final next = wire['next'] as Map<String, Object?>;
      expect(next['title'], 'Cafe Leopold');
      expect(next['at'], '14:20');
      expect(next['dist'], 1200);
    });

    test('omits a distance the phone does not know', () {
      final wire = WatchStateMessage(
        live: true,
        next: const WatchNextStop(title: 'Colaba', at: '11:00'),
        ts: ts,
      ).toWire();
      final next = wire['next'] as Map<String, Object?>;
      // Absent, not zero: zero would read on the watch as "you are there".
      expect(next.containsKey('dist'), isFalse);
    });

    test('omits a negative distance rather than sending nonsense', () {
      final wire = WatchStateMessage(
        live: true,
        next: const WatchNextStop(title: 'Colaba', at: '11:00', distanceM: -5),
        ts: ts,
      ).toWire();
      expect((wire['next'] as Map)['dist'], isNull);
    });

    test('omits next and day entirely when there is no plan', () {
      final wire = WatchStateMessage(live: false, ts: ts).toWire();
      expect(wire.containsKey('next'), isFalse);
      expect(wire.containsKey('day'), isFalse);
      expect(wire['live'], false);
    });

    test('alert carries its kind on the wire', () {
      for (final kind in WatchAlertKind.values) {
        final wire = WatchAlertMessage(id: 'a1', kind: kind, text: 'x', ts: ts).toWire();
        expect(wire['kind'], kind.wire);
      }
      // `late` is a Dart keyword, so the constant is named differently.
      expect(WatchAlertKind.runningBehind.wire, 'late');
    });

    test('alert text is sanitised and truncated', () {
      final wire = WatchAlertMessage(
        id: 'a1',
        kind: WatchAlertKind.leave,
        text: 'Leave now — the ferry to Elephanta Caves departs in twelve minutes sharp',
        ts: ts,
      ).toWire();
      expect((wire['text'] as String).length, lessThanOrEqualTo(maxLineChars));
    });

    test('sosAck includes only the fields that apply', () {
      final counting = const SosAckMessage(
        status: SosAckStatus.countdown,
        secondsLeft: 7,
      ).toWire();
      expect(counting['status'], 'countdown');
      expect(counting['secondsLeft'], 7);
      expect(counting.containsKey('detail'), isFalse);

      final failed = const SosAckMessage(
        status: SosAckStatus.failed,
        detail: 'No emergency contacts',
      ).toWire();
      expect(failed['status'], 'failed');
      expect(failed['detail'], 'No emergency contacts');
      expect(failed.containsKey('secondsLeft'), isFalse);
    });

    test('ping is minimal', () {
      expect(watchPing(), {'t': 'ping', 'v': 1});
    });

    test('every message fits one transmit', () {
      final long = 'x' * 500;
      expect(
        fitsOneTransmit(WatchStateMessage(
          live: true,
          day: long,
          next: WatchNextStop(title: long, at: '14:20', distanceM: 999999),
          ts: ts,
        ).toWire()),
        isTrue,
      );
      expect(
        fitsOneTransmit(
          WatchAlertMessage(id: long, kind: WatchAlertKind.rain, text: long, ts: ts).toWire(),
        ),
        isTrue,
      );
      expect(
        fitsOneTransmit(SosAckMessage(status: SosAckStatus.failed, detail: long).toWire()),
        isTrue,
      );
    });

    test('a pathological id is the one thing that could overflow, and is caught', () {
      // Ids are ours, not the traveller's, but the guard must still be real.
      final wire = WatchAlertMessage(
        id: 'i' * 2000,
        kind: WatchAlertKind.meal,
        text: 'Lunch',
        ts: ts,
      ).toWire();
      expect(watchMessageBytes(wire), greaterThan(maxMessageBytes));
      expect(fitsOneTransmit(wire), isFalse);
    });
  });

  group('decodeWatchMessage', () {
    test('decodes hello', () {
      final msg = decodeWatchMessage({
        't': 'hello',
        'v': 1,
        'device': 'fr965',
        'appVersion': '1.0.0',
      });
      expect(msg, isA<WatchHello>());
      expect((msg! as WatchHello).device, 'fr965');
      expect((msg as WatchHello).appVersion, '1.0.0');
    });

    test('decodes sos with its timestamp', () {
      final msg = decodeWatchMessage({'t': 'sos', 'v': 1, 'ts': 1790000000});
      expect(msg, isA<WatchSosRequest>());
      expect(
        (msg! as WatchSosRequest).ts,
        DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000),
      );
    });

    test('decodes sos without a timestamp rather than dropping an emergency', () {
      // A missing ts must not lose the SOS; "now" is the safe reading.
      expect(decodeWatchMessage({'t': 'sos', 'v': 1}), isA<WatchSosRequest>());
    });

    test('decodes cancel and ack', () {
      expect(decodeWatchMessage({'t': 'sosCancel', 'v': 1}), isA<WatchSosCancel>());
      final ack = decodeWatchMessage({'t': 'ack', 'v': 1, 'id': 'a1'});
      expect((ack! as WatchAlertAck).id, 'a1');
    });

    test('ignores an ack with no id', () {
      expect(decodeWatchMessage({'t': 'ack', 'v': 1}), isNull);
    });

    test('ignores a newer protocol version safely', () {
      expect(decodeWatchMessage({'t': 'sos', 'v': 2, 'ts': 1}), isNull);
      expect(decodeWatchMessage({'t': 'hello', 'v': 99}), isNull);
    });

    test('ignores a missing or non-numeric version', () {
      expect(decodeWatchMessage({'t': 'sos'}), isNull);
      expect(decodeWatchMessage({'t': 'sos', 'v': '1'}), isNull);
    });

    test('ignores an unknown type', () {
      expect(decodeWatchMessage({'t': 'selfDestruct', 'v': 1}), isNull);
    });

    test('ignores anything that is not a map', () {
      expect(decodeWatchMessage(null), isNull);
      expect(decodeWatchMessage('sos'), isNull);
      expect(decodeWatchMessage([1, 2, 3]), isNull);
      expect(decodeWatchMessage(42), isNull);
    });

    test('tolerates a hello with missing fields', () {
      final msg = decodeWatchMessage({'t': 'hello', 'v': 1});
      expect((msg! as WatchHello).device, 'unknown');
    });
  });
}
