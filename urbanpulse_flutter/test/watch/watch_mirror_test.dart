import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/services/watch/watch_link.dart';
import 'package:urbanpulse/services/watch/watch_mirror.dart';
import 'package:urbanpulse/services/watch/watch_protocol.dart';

void main() {
  late ScriptedWatchLink link;
  late DateTime now;
  late WatchMirror mirror;

  setUp(() {
    link = ScriptedWatchLink();
    now = DateTime(2026, 9, 27, 10, 0);
    mirror = WatchMirror(
      link: link,
      limits: const WatchMirrorLimits(
        minAlertGap: Duration(seconds: 20),
        alertWindow: Duration(minutes: 5),
        maxAlertsPerWindow: 3,
        duplicateWindow: Duration(minutes: 2),
        stateRefresh: Duration(minutes: 2),
      ),
      now: () => now,
    )..mirroring = true;
  });

  tearDown(() => link.dispose());

  WatchAlertMessage alert(String id, {WatchAlertKind kind = WatchAlertKind.leave, String text = 'Leave now'}) =>
      WatchAlertMessage(id: id, kind: kind, text: text, ts: now);

  WatchStateMessage state({String title = 'Gateway', int? dist = 500}) => WatchStateMessage(
    live: true,
    next: WatchNextStop(title: title, at: '14:20', distanceM: dist),
    ts: now,
  );

  group('state', () {
    test('sends the first state', () async {
      expect(await mirror.pushState(state()), isTrue);
      expect(link.sentOfType('state'), hasLength(1));
    });

    test('drops an unchanged state while it is still fresh', () async {
      await mirror.pushState(state());
      now = now.add(const Duration(seconds: 5));
      // Only `ts` differs, and the watch has nothing new to show.
      expect(await mirror.pushState(state()), isFalse);
      expect(link.sentOfType('state'), hasLength(1));
    });

    test('resends an unchanged state once it would go stale', () async {
      await mirror.pushState(state());
      now = now.add(const Duration(minutes: 3));
      expect(await mirror.pushState(state()), isTrue);
      expect(link.sentOfType('state'), hasLength(2));
    });

    test('sends a changed distance immediately', () async {
      await mirror.pushState(state(dist: 500));
      now = now.add(const Duration(seconds: 3));
      expect(await mirror.pushState(state(dist: 420)), isTrue);
      expect(link.sentOfType('state'), hasLength(2));
    });

    test('notices a change nested inside next', () async {
      await mirror.pushState(state(title: 'Gateway'));
      now = now.add(const Duration(seconds: 3));
      expect(await mirror.pushState(state(title: 'Colaba')), isTrue);
    });

    test('treats losing the distance as a change', () async {
      await mirror.pushState(state(dist: 500));
      now = now.add(const Duration(seconds: 3));
      expect(await mirror.pushState(state(dist: null)), isTrue);
    });

    test('sends nothing while mirroring is off', () async {
      mirror.mirroring = false;
      expect(await mirror.pushState(state()), isFalse);
      expect(link.sent, isEmpty);
    });

    test('sends nothing when the watch is not connected', () async {
      link.setStatus(WatchStatus.deviceNotConnected);
      expect(await mirror.pushState(state()), isFalse);
      expect(link.sent, isEmpty);
    });

    test('a failed send is retried on the next tick', () async {
      link.failNextSend = StateError('radio busy');
      expect(await mirror.pushState(state()), isFalse);
      // The failure must not be remembered as "already sent this".
      expect(await mirror.pushState(state()), isTrue);
      expect(link.sentOfType('state'), hasLength(1));
    });
  });

  group('alerts', () {
    test('sends the first alert', () async {
      expect(await mirror.pushAlert(alert('a1')), WatchAlertOutcome.sent);
      expect(link.sentOfType('alert'), hasLength(1));
    });

    test('refuses a repeated id', () async {
      await mirror.pushAlert(alert('a1'));
      now = now.add(const Duration(minutes: 10));
      expect(await mirror.pushAlert(alert('a1')), WatchAlertOutcome.duplicateId);
      expect(link.sentOfType('alert'), hasLength(1));
    });

    test('refuses the same text under a new id inside the duplicate window', () async {
      await mirror.pushAlert(alert('a1', text: 'Leave now for the ferry'));
      now = now.add(const Duration(seconds: 30));
      expect(
        await mirror.pushAlert(alert('a2', text: 'Leave now for the ferry')),
        WatchAlertOutcome.duplicateText,
      );
    });

    test('allows the same text again after the duplicate window', () async {
      await mirror.pushAlert(alert('a1', text: 'Leave now'));
      now = now.add(const Duration(minutes: 3));
      expect(await mirror.pushAlert(alert('a2', text: 'Leave now')), WatchAlertOutcome.sent);
    });

    test('compares duplicates after sanitising, not before', () async {
      await mirror.pushAlert(alert('a1', text: 'Café stop'));
      now = now.add(const Duration(seconds: 30));
      // Both sanitise to "Caf stop", so the second is the same buzz.
      expect(
        await mirror.pushAlert(alert('a2', text: 'Café   stop')),
        WatchAlertOutcome.duplicateText,
      );
    });

    test('the same text with a different kind is a different alert', () async {
      await mirror.pushAlert(alert('a1', kind: WatchAlertKind.leave, text: 'Move'));
      now = now.add(const Duration(seconds: 30));
      expect(
        await mirror.pushAlert(alert('a2', kind: WatchAlertKind.runningBehind, text: 'Move')),
        WatchAlertOutcome.sent,
      );
    });

    test('enforces the minimum gap between buzzes', () async {
      await mirror.pushAlert(alert('a1', text: 'One'));
      now = now.add(const Duration(seconds: 5));
      expect(await mirror.pushAlert(alert('a2', text: 'Two')), WatchAlertOutcome.rateLimited);
      expect(link.sentOfType('alert'), hasLength(1));
    });

    test('allows the next alert once the gap has passed', () async {
      await mirror.pushAlert(alert('a1', text: 'One'));
      now = now.add(const Duration(seconds: 25));
      expect(await mirror.pushAlert(alert('a2', text: 'Two')), WatchAlertOutcome.sent);
    });

    test('enforces the per-window budget', () async {
      // maxAlertsPerWindow is 3 here, each spaced past the minimum gap.
      for (var i = 0; i < 3; i++) {
        expect(await mirror.pushAlert(alert('a$i', text: 'Alert $i')), WatchAlertOutcome.sent);
        now = now.add(const Duration(seconds: 25));
      }
      expect(await mirror.pushAlert(alert('a9', text: 'Alert 9')), WatchAlertOutcome.rateLimited);
      expect(link.sentOfType('alert'), hasLength(3));
    });

    test('the budget is a rolling window, not a hard cap', () async {
      for (var i = 0; i < 3; i++) {
        await mirror.pushAlert(alert('a$i', text: 'Alert $i'));
        now = now.add(const Duration(seconds: 25));
      }
      expect(await mirror.pushAlert(alert('b1', text: 'Blocked')), WatchAlertOutcome.rateLimited);
      // Once the oldest falls out of the 5 minute window there is room again.
      now = now.add(const Duration(minutes: 5));
      expect(await mirror.pushAlert(alert('b2', text: 'Allowed')), WatchAlertOutcome.sent);
    });

    test('reports mirroringOff rather than silently dropping', () async {
      mirror.mirroring = false;
      expect(await mirror.pushAlert(alert('a1')), WatchAlertOutcome.mirroringOff);
    });

    test('reports notConnected', () async {
      link.setStatus(WatchStatus.watchAppNotInstalled);
      expect(await mirror.pushAlert(alert('a1')), WatchAlertOutcome.notConnected);
    });

    test('reports failed and does not consume the budget', () async {
      link.failNextSend = StateError('nope');
      expect(await mirror.pushAlert(alert('a1')), WatchAlertOutcome.failed);
      // A send that never happened must not block the retry.
      expect(await mirror.pushAlert(alert('a1')), WatchAlertOutcome.sent);
    });
  });

  group('sos acks bypass the gates', () {
    test('sent even while mirroring is off', () async {
      mirror.mirroring = false;
      expect(
        await mirror.pushSosAck(const SosAckMessage(status: SosAckStatus.countdown, secondsLeft: 9)),
        isTrue,
      );
      expect(link.sentOfType('sosAck'), hasLength(1));
    });

    test('not rate limited, because a stale SOS status would be a lie', () async {
      for (var i = 10; i > 0; i--) {
        await mirror.pushSosAck(SosAckMessage(status: SosAckStatus.countdown, secondsLeft: i));
      }
      expect(link.sentOfType('sosAck'), hasLength(10));
    });

    test('returns false when the link refuses', () async {
      link.failAllSends = true;
      expect(await mirror.pushSosAck(const SosAckMessage(status: SosAckStatus.sent)), isFalse);
    });

    test('returns false when not connected', () async {
      link.setStatus(WatchStatus.noDevicePaired);
      expect(await mirror.pushSosAck(const SosAckMessage(status: SosAckStatus.sent)), isFalse);
    });
  });

  group('acks and reset', () {
    test('records what the watch displayed', () {
      mirror.onAck(const WatchAlertAck(id: 'a1'));
      expect(mirror.acknowledged, contains('a1'));
    });

    test('reset clears the history so a new trip starts fresh', () async {
      await mirror.pushAlert(alert('a1'));
      await mirror.pushState(state());
      mirror.onAck(const WatchAlertAck(id: 'a1'));
      mirror.reset();

      expect(mirror.acknowledged, isEmpty);
      // The same id and the same state are both sendable again.
      expect(await mirror.pushAlert(alert('a1')), WatchAlertOutcome.sent);
      expect(await mirror.pushState(state()), isTrue);
    });
  });

  group('ping', () {
    test('goes out regardless of mirroring, since the traveller asked', () async {
      mirror.mirroring = false;
      expect(await mirror.pushPing(), isTrue);
      expect(link.sentOfType('ping'), hasLength(1));
    });

    test('fails honestly when not connected', () async {
      link.setStatus(WatchStatus.deviceNotConnected);
      expect(await mirror.pushPing(), isFalse);
    });
  });
}
