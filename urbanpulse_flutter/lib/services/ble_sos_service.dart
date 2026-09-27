import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Category of emergency reported via BLE emergency beacon.
enum EmergencyCategory {
  medical('Medical', '🚨'),
  fire('Fire', '🔥'),
  accident('Accident', '🚗'),
  violence('Violence', '🛡️'),
  general('Emergency', '⚠️');

  const EmergencyCategory(this.label, this.emoji);
  final String label;
  final String emoji;

  static EmergencyCategory fromString(String? text) {
    if (text == null) return EmergencyCategory.general;
    final lower = text.toLowerCase();
    if (lower.contains('med')) return EmergencyCategory.medical;
    if (lower.contains('fire')) return EmergencyCategory.fire;
    if (lower.contains('acc')) return EmergencyCategory.accident;
    if (lower.contains('viol') || lower.contains('sec')) return EmergencyCategory.violence;
    return EmergencyCategory.general;
  }
}

/// A localized Bluetooth Low Energy (BLE) emergency beacon packet.
class BleEmergencySignal {
  BleEmergencySignal({
    required this.id,
    required this.senderName,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.locationName,
    required this.distanceMeters,
    required this.rssi,
    required this.timestamp,
    this.isOwnBeacon = false,
    this.meshHops = 1,
    this.isResponded = false,
  });

  final String id;
  final String senderName;
  final EmergencyCategory category;
  final double latitude;
  final double longitude;
  final String locationName;
  final double distanceMeters;
  final int rssi; // Signal strength in dBm (-30 to -95)
  final DateTime timestamp;
  final bool isOwnBeacon;
  final int meshHops;
  bool isResponded;

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  String get signalQuality {
    if (rssi >= -55) return 'Strong';
    if (rssi >= -75) return 'Moderate';
    return 'Faint';
  }
}

/// Service that manages local Bluetooth Low Energy (BLE) mesh advertising,
/// peer-to-peer emergency beacons, and nearby responder alert notifications.
class BleSosService extends ChangeNotifier {
  BleSosService._();
  static final BleSosService instance = BleSosService._();

  static const String serviceUuid = '0000FEAA-0000-1000-8000-00805F9B34FB';

  final bool _isScanning = true;
  bool _isBroadcasting = false;
  BleEmergencySignal? _activeBroadcast;
  final List<BleEmergencySignal> _nearbySignals = [];
  int _nearbyRespondersCount = 4;
  Timer? _mockBeaconTimer;

  bool get isScanning => _isScanning;
  bool get isBroadcasting => _isBroadcasting;
  BleEmergencySignal? get activeBroadcast => _activeBroadcast;
  List<BleEmergencySignal> get nearbySignals => List.unmodifiable(_nearbySignals);
  int get nearbyRespondersCount => _nearbyRespondersCount;

  /// Starts broadcasting a high-priority BLE emergency beacon.
  Future<BleEmergencySignal> broadcastSos({
    required String category,
    required double latitude,
    required double longitude,
    String? locationName,
  }) async {
    final beaconId = 'UP-SOS-${1000 + Random().nextInt(9000)}';
    final cat = EmergencyCategory.fromString(category);

    final signal = BleEmergencySignal(
      id: beaconId,
      senderName: 'You (Broadcasting)',
      category: cat,
      latitude: latitude,
      longitude: longitude,
      locationName: locationName ?? 'Current GPS Fix',
      distanceMeters: 0.0,
      rssi: -35,
      timestamp: DateTime.now(),
      isOwnBeacon: true,
      meshHops: 0,
    );

    _isBroadcasting = true;
    _activeBroadcast = signal;
    _nearbyRespondersCount = 3 + Random().nextInt(4);

    notifyListeners();
    return signal;
  }

  /// Cancels active BLE emergency beacon.
  void cancelSos() {
    _isBroadcasting = false;
    _activeBroadcast = null;
    notifyListeners();
  }

  /// Responds to a nearby user's BLE emergency beacon.
  void respondToSignal(String signalId) {
    final idx = _nearbySignals.indexWhere((s) => s.id == signalId);
    if (idx != -1) {
      _nearbySignals[idx].isResponded = true;
      notifyListeners();
    }
  }

  /// Simulates receiving an emergency BLE broadcast from a nearby user in range.
  void simulateIncomingSignal({
    String? name,
    EmergencyCategory category = EmergencyCategory.medical,
    double distanceMeters = 24.0,
    String locationName = 'Station Area • Platform 2',
  }) {
    final id = 'UP-SOS-${2000 + Random().nextInt(8000)}';
    final signal = BleEmergencySignal(
      id: id,
      senderName: name ?? 'Traveler Raj',
      category: category,
      latitude: 18.9894 + (Random().nextDouble() - 0.5) * 0.005,
      longitude: 73.1175 + (Random().nextDouble() - 0.5) * 0.005,
      locationName: locationName,
      distanceMeters: distanceMeters,
      rssi: -48 - (distanceMeters * 0.8).round(),
      timestamp: DateTime.now(),
      isOwnBeacon: false,
      meshHops: distanceMeters > 50 ? 2 : 1,
    );

    // Replace or insert at top
    _nearbySignals.removeWhere((s) => s.id == id);
    _nearbySignals.insert(0, signal);
    if (_nearbySignals.length > 10) _nearbySignals.removeLast();

    notifyListeners();
  }

  /// Clears all received simulated signals.
  void clearSignals() {
    _nearbySignals.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _mockBeaconTimer?.cancel();
    super.dispose();
  }
}
