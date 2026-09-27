import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbanpulse/services/watch/watch_link.dart';
import 'package:urbanpulse/services/watch/watch_service.dart';

void main() {
  late ScriptedWatchLink link;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    link = ScriptedWatchLink();
  });

  tearDown(() => link.dispose());

  /// A watch SOS, as the link would deliver it.
  void pressSosOnWatch() => link.receive({'t': 'sos', 'v': 1, 'ts': 1790000000});

  group('watch SOS where the platform cannot send', () {
    late WatchService service;

    setUp(() {
      // iOS: no API sends an SMS without the traveller tapping send.
      link.supportsSosFromWatch = false;
      service = WatchService(link: link, prefs: prefs);
    });

    tearDown(() => service.dispose());

    test('the toggle cannot be switched on', () async {
      expect(service.sosFromWatchSupported, isFalse);
      expect(await service.setSosFromWatch(true), isFalse);
      expect(service.sosFromWatch, isFalse);
    });

    test('raises a notice for the phone to show', () async {
      final notices = <WatchSosNotice>[];
      service.watchSosRequests.listen(notices.add);

      pressSosOnWatch();
      await Future<void>.delayed(Duration.zero);

      expect(notices, hasLength(1));
      expect(notices.single.started, isFalse);
      // The reason has to explain the platform limit, not just say "off".
      expect(notices.single.reason.toLowerCase(), contains('ios'));
      expect(notices.single.reason, contains('cannot complete'));
    });

    test('tells the watch too, so the wrist does not wait on a countdown', () async {
      pressSosOnWatch();
      await Future<void>.delayed(Duration.zero);

      final acks = link.sentOfType('sosAck');
      expect(acks, hasLength(1));
      expect(acks.single['status'], 'failed');
      expect(acks.single['detail'], contains('iPhone'));
    });

    test('never claims anything was sent', () async {
      pressSosOnWatch();
      await Future<void>.delayed(Duration.zero);
      for (final ack in link.sentOfType('sosAck')) {
        expect(ack['status'], isNot('sent'));
        expect(ack['status'], isNot('countdown'));
      }
    });
  });

  group('watch SOS where the toggle is simply off', () {
    late WatchService service;

    setUp(() {
      link.supportsSosFromWatch = true;
      service = WatchService(link: link, prefs: prefs);
    });

    tearDown(() => service.dispose());

    test('gives the switchable reason, not the platform one', () async {
      final notices = <WatchSosNotice>[];
      service.watchSosRequests.listen(notices.add);

      pressSosOnWatch();
      await Future<void>.delayed(Duration.zero);

      expect(notices.single.started, isFalse);
      // This one the traveller can actually act on.
      expect(notices.single.reason, contains('switched off'));
      expect(service.sosFromWatchRefused, isTrue);
    });
  });

  group('reconnectIfPaired', () {
    test('does nothing for a phone that has never reached a watch', () async {
      // A link that has never been connected: nothing to reconnect to.
      final fresh = ScriptedWatchLink(initial: WatchStatus.noDevicePaired);
      addTearDown(fresh.dispose);
      final service = WatchService(link: fresh, prefs: prefs);
      addTearDown(service.dispose);

      await service.reconnectIfPaired();
      expect(fresh.connectCalls, 0);
    });

    test('reconnects once a watch has been reached before', () async {
      final paired = ScriptedWatchLink(initial: WatchStatus.deviceNotConnected);
      addTearDown(paired.dispose);
      final first = WatchService(link: paired, prefs: prefs);
      // Reaching a watch is what records it.
      paired.setStatus(WatchStatus.connected);
      await Future<void>.delayed(Duration.zero);
      await first.dispose();

      final again = ScriptedWatchLink(initial: WatchStatus.deviceNotConnected);
      addTearDown(again.dispose);
      final service = WatchService(link: again, prefs: prefs);
      addTearDown(service.dispose);

      await service.reconnectIfPaired();
      // Without this the watch's SOS button could not reach a phone whose owner
      // had not opened the Garmin screen this launch.
      expect(again.connectCalls, 1);
    });
  });
}
