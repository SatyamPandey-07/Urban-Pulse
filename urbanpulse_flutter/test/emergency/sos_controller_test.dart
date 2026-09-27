import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbanpulse/services/emergency/emergency_contacts.dart';
import 'package:urbanpulse/services/emergency/emergency_sms.dart';
import 'package:urbanpulse/services/live_location.dart';
import 'package:urbanpulse/services/watch/watch_protocol.dart';
import 'package:urbanpulse/state/sos_controller.dart';

/// An [EmergencySms] the test drives, recording what it was asked to send.
class FakeSms implements EmergencySms {
  FakeSms(this._result, {this.direct = true});

  SmsResult _result;
  bool direct;

  final List<String> bodies = [];
  final List<List<String>> recipients = [];
  int permissionRequests = 0;

  set result(SmsResult r) => _result = r;

  @override
  Future<bool> canSendDirectly() async => direct;

  @override
  Future<bool> requestDirectPermission() async {
    permissionRequests++;
    return direct;
  }

  @override
  Future<SmsResult> send({required List<EmergencyContact> to, required String body}) async {
    bodies.add(body);
    recipients.add(to.map((c) => c.dialable).toList());
    return _result;
  }
}

/// A [LiveLocation] with a scripted answer.
class FakeLocation implements LiveLocation {
  FakeLocation(this.result);

  LocationResult result;

  @override
  Future<LocationResult> request() async => result;

  @override
  Stream<UserFix> watch({int distanceFilterM = 5}) => const Stream.empty();

  @override
  Future<void> openSettings(LocationStatus status) async {}
}

void main() {
  late SharedPreferences prefs;
  late EmergencyContactsRepository contacts;
  late FakeSms sms;
  late FakeLocation location;
  late List<SosAckMessage> acks;
  late DateTime now;

  const fix = UserFix(point: LatLng(18.9894, 73.1175), accuracyM: 8);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    contacts = EmergencyContactsRepository(prefs);
    sms = FakeSms(const SmsResult(SmsOutcome.sent, detail: 'Sent to 1 contact', reached: ['+919876543210']));
    location = FakeLocation(const LocationResult(LocationStatus.ok, fix));
    acks = [];
    now = DateTime(2026, 9, 27, 14, 30);
  });

  SosController build({Duration window = const Duration(seconds: 10)}) => SosController(
    contacts: contacts,
    sms: sms,
    location: location,
    cancelWindow: window,
    now: () => now,
    ackSink: (ack) async => acks.add(ack),
  );

  Future<void> addContact() =>
      contacts.add(const EmergencyContact(name: 'Asha', phone: '+91 98765 43210'));

  List<SosAckStatus> ackStatuses() => acks.map((a) => a.status).toList();

  group('no contacts', () {
    test('refuses to start and says why', () async {
      final c = build();
      addTearDown(c.dispose);

      expect(await c.trigger(), isFalse);
      expect(c.state.phase, SosPhase.failed);
      expect(c.state.detail, contains('No emergency contacts'));
      // Nothing was sent, and the watch is told so rather than left counting.
      expect(sms.bodies, isEmpty);
      expect(ackStatuses(), [SosAckStatus.failed]);
    });

    test('never reports a countdown it cannot honour', () async {
      final c = build();
      addTearDown(c.dispose);
      await c.trigger();
      expect(ackStatuses(), isNot(contains(SosAckStatus.countdown)));
    });
  });

  group('countdown', () {
    test('starts armed and acks a countdown each second', () async {
      await addContact();
      final c = build(window: const Duration(seconds: 3));
      addTearDown(c.dispose);

      expect(await c.trigger(), isTrue);
      expect(c.state.phase, SosPhase.armed);
      expect(c.state.secondsLeft, 3);
      expect(acks.first.status, SosAckStatus.countdown);
      expect(acks.first.secondsLeft, 3);

      // Let the real timer run out.
      await Future<void>.delayed(const Duration(milliseconds: 3400));
      expect(c.state.phase, SosPhase.sent);
      // Countdowns for 2 and 1, then the outcome.
      expect(acks.where((a) => a.status == SosAckStatus.countdown).length, greaterThanOrEqualTo(2));
      expect(acks.last.status, SosAckStatus.sent);
    });

    test('records the origin so the message can say where it came from', () async {
      await addContact();
      final c = build(window: const Duration(seconds: 2));
      addTearDown(c.dispose);

      await c.trigger(origin: SosOrigin.watch);
      expect(c.state.origin, SosOrigin.watch);
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      expect(sms.bodies.single, contains('raised from my Garmin watch'));
    });

    test('a second trigger while armed does not restart it', () async {
      await addContact();
      final c = build();
      addTearDown(c.dispose);

      await c.trigger();
      final first = c.state.secondsLeft;
      expect(await c.trigger(), isTrue);
      expect(c.state.secondsLeft, first);
      expect(acks.where((a) => a.status == SosAckStatus.countdown).length, 1);
    });

    test('raises the alarm callback once', () async {
      await addContact();
      var raised = 0;
      final c = build()..onRaised = (_) => raised++;
      addTearDown(c.dispose);
      await c.trigger();
      await c.trigger();
      expect(raised, 1);
    });
  });

  group('cancel', () {
    test('cancels from either side during the window', () async {
      await addContact();
      final c = build();
      addTearDown(c.dispose);

      await c.trigger();
      expect(await c.cancel(), isTrue);
      expect(c.state.phase, SosPhase.cancelled);
      expect(acks.last.status, SosAckStatus.cancelled);
      // The whole point: nothing left the phone.
      expect(sms.bodies, isEmpty);
    });

    test('stops the countdown so nothing is sent later', () async {
      await addContact();
      final c = build(window: const Duration(seconds: 2));
      addTearDown(c.dispose);

      await c.trigger();
      await c.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(sms.bodies, isEmpty);
      expect(c.state.phase, SosPhase.cancelled);
    });

    test('refuses to cancel once it is no longer cancellable', () async {
      await addContact();
      final c = build(window: const Duration(seconds: 1));
      addTearDown(c.dispose);

      await c.trigger();
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      expect(c.state.phase, SosPhase.sent);
      // Claiming to cancel a sent message would be the same lie inverted.
      expect(await c.cancel(), isFalse);
      expect(c.state.phase, SosPhase.sent);
    });

    test('cancelling when idle does nothing', () async {
      final c = build();
      addTearDown(c.dispose);
      expect(await c.cancel(), isFalse);
      expect(acks, isEmpty);
    });
  });

  group('honest outcomes', () {
    Future<SosController> run({Duration window = const Duration(seconds: 1)}) async {
      await addContact();
      final c = build(window: window);
      await c.trigger();
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      return c;
    }

    test('sent only when the OS accepted the message', () async {
      final c = await run();
      addTearDown(c.dispose);
      expect(c.state.phase, SosPhase.sent);
      expect(c.state.reached, ['+919876543210']);
      expect(acks.last.status, SosAckStatus.sent);
    });

    test('prepared when only a composer was opened', () async {
      sms.result = const SmsResult(SmsOutcome.prepared, detail: 'Tap send');
      final c = await run();
      addTearDown(c.dispose);
      // This is the iOS path, and it must never read as "sent".
      expect(c.state.phase, SosPhase.prepared);
      expect(c.state.reached, isEmpty);
      expect(acks.last.status, SosAckStatus.prepared);
      expect(acks.last.status, isNot(SosAckStatus.sent));
    });

    test('failed with a reason when nothing could be done', () async {
      sms.result = const SmsResult.failed('No messaging app would open');
      final c = await run();
      addTearDown(c.dispose);
      expect(c.state.phase, SosPhase.failed);
      expect(acks.last.status, SosAckStatus.failed);
      expect(acks.last.detail, contains('No messaging app'));
    });

    test('still sends when the watch ack cannot be delivered', () async {
      await addContact();
      final c = SosController(
        contacts: contacts,
        sms: sms,
        location: location,
        cancelWindow: const Duration(seconds: 1),
        now: () => now,
        // A dead watch link must not stop the message to the contacts.
        ackSink: (_) async => throw StateError('watch gone'),
      );
      addTearDown(c.dispose);
      await c.trigger();
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      expect(c.state.phase, SosPhase.sent);
      expect(sms.bodies, hasLength(1));
    });
  });

  group('position', () {
    Future<SosController> run() async {
      await addContact();
      final c = build(window: const Duration(seconds: 1));
      await c.trigger();
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      return c;
    }

    test('includes a maps link for a fresh fix', () async {
      final c = await run();
      addTearDown(c.dispose);
      expect(sms.bodies.single, contains('https://maps.google.com/?q=18.98940,73.11750'));
      expect(sms.bodies.single, contains('My location'));
      expect(c.state.positionAgeS, isNull);
    });

    test('falls back to the last known fix and says how old it is', () async {
      location.result = const LocationResult(LocationStatus.denied);
      await addContact();
      final c = build(window: const Duration(seconds: 1));
      addTearDown(c.dispose);

      c.noteFix(fix);
      now = now.add(const Duration(minutes: 4));
      await c.trigger();
      await Future<void>.delayed(const Duration(milliseconds: 1400));

      expect(sms.bodies.single, contains('Last known location'));
      expect(sms.bodies.single, contains('4min old'));
      expect(c.state.positionAgeS, 240);
    });

    test('says the position is unknown rather than inventing one', () async {
      location.result = const LocationResult(LocationStatus.serviceOff);
      final c = await run();
      addTearDown(c.dispose);

      expect(sms.bodies.single, contains('Location unknown'));
      expect(sms.bodies.single, isNot(contains('maps.google.com')));
      expect(c.state.mapsUrl, isNull);
      // A missing position must not stop the SOS.
      expect(c.state.phase, SosPhase.sent);
    });
  });

  group('message', () {
    test('names the app, the time and the position', () {
      final body = buildSosMessage(where: 'My location: https://x', at: now);
      expect(body, contains('SOS from UrbanPulse'));
      expect(body, contains('14:30'));
      expect(body, contains('https://x'));
    });

    test('marks a watch-raised SOS', () {
      final body = buildSosMessage(where: 'x', at: now, origin: SosOrigin.watch);
      expect(body, contains('Garmin watch'));
    });

    test('fits comfortably in a couple of SMS segments', () {
      final body = buildSosMessage(
        where: 'Last known location (12min old): https://maps.google.com/?q=18.98940,73.11750',
        at: now,
        origin: SosOrigin.watch,
      );
      expect(body.length, lessThan(320));
    });
  });

  group('acknowledge', () {
    test('resets a finished SOS back to idle', () async {
      await addContact();
      final c = build(window: const Duration(seconds: 1));
      addTearDown(c.dispose);
      await c.trigger();
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      c.acknowledge();
      expect(c.state.phase, SosPhase.idle);
    });

    test('refuses to reset one that is still running', () async {
      await addContact();
      final c = build();
      addTearDown(c.dispose);
      await c.trigger();
      c.acknowledge();
      expect(c.state.phase, SosPhase.armed);
    });
  });
}
