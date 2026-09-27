import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/services/ble_sos_service.dart';

void main() {
  group('BleSosService', () {
    late BleSosService bleService;

    setUp(() {
      bleService = BleSosService.instance;
      bleService.clearSignals();
      bleService.cancelSos();
    });

    test('initial state has default values', () {
      expect(bleService.isScanning, isTrue);
      expect(bleService.isBroadcasting, isFalse);
      expect(bleService.activeBroadcast, isNull);
      expect(bleService.nearbySignals, isEmpty);
      expect(bleService.nearbyRespondersCount, greaterThan(0));
    });

    test('broadcasting SOS sets active broadcast and notifies listeners', () async {
      var notified = false;
      bleService.addListener(() => notified = true);

      final signal = await bleService.broadcastSos(
        category: 'Medical',
        latitude: 18.9894,
        longitude: 73.1175,
        locationName: 'Station Test',
      );

      expect(notified, isTrue);
      expect(bleService.isBroadcasting, isTrue);
      expect(bleService.activeBroadcast, isNotNull);
      expect(bleService.activeBroadcast?.category, EmergencyCategory.medical);
      expect(bleService.activeBroadcast?.latitude, 18.9894);
      expect(signal.isOwnBeacon, isTrue);
    });

    test('cancelling SOS resets broadcast state', () async {
      await bleService.broadcastSos(
        category: 'Fire',
        latitude: 19.0,
        longitude: 73.0,
      );
      expect(bleService.isBroadcasting, isTrue);

      bleService.cancelSos();
      expect(bleService.isBroadcasting, isFalse);
      expect(bleService.activeBroadcast, isNull);
    });

    test('simulating incoming peer beacon adds to nearby signals', () {
      bleService.simulateIncomingSignal(
        name: 'Traveler Ananya',
        category: EmergencyCategory.accident,
        distanceMeters: 30.0,
        locationName: 'North Gate',
      );

      expect(bleService.nearbySignals.length, equals(1));
      final signal = bleService.nearbySignals.first;
      expect(signal.senderName, equals('Traveler Ananya'));
      expect(signal.category, equals(EmergencyCategory.accident));
      expect(signal.distanceMeters, equals(30.0));
      expect(signal.isResponded, isFalse);
    });

    test('responding to peer signal marks it as responded', () {
      bleService.simulateIncomingSignal(
        name: 'Traveler Kabir',
        category: EmergencyCategory.violence,
      );

      final signalId = bleService.nearbySignals.first.id;
      bleService.respondToSignal(signalId);

      expect(bleService.nearbySignals.first.isResponded, isTrue);
    });
  });
}
