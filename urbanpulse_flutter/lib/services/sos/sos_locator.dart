import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'sos_models.dart';

/// Why there is no fix.
enum LocationIssue { none, denied, serviceOff, unavailable }

/// Where the phone is, for SOS. Never prompts on its own (an SOS may be raised
/// with the screen off); [askPermission] does that from the SOS screen.
abstract class SosLocator {
  Future<(SosPoint?, LocationIssue)> locate({bool precise = true});

  Future<bool> askPermission();
}

class GeoSosLocator implements SosLocator {
  const GeoSosLocator();

  @override
  Future<(SosPoint?, LocationIssue)> locate({bool precise = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return (await _lastKnown(), LocationIssue.serviceOff);
      final p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever || p == LocationPermission.unableToDetermine) {
        return (null, LocationIssue.denied);
      }
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: precise ? LocationAccuracy.high : LocationAccuracy.medium,
            timeLimit: Duration(seconds: precise ? 12 : 8),
          ),
        );
        return (_point(pos), LocationIssue.none);
      } on TimeoutException {
        final last = await _lastKnown();
        return (last, last == null ? LocationIssue.unavailable : LocationIssue.none);
      }
    } catch (_) {
      final last = await _lastKnown();
      return (last, last == null ? LocationIssue.unavailable : LocationIssue.none);
    }
  }

  @override
  Future<bool> askPermission() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      return p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  static Future<SosPoint?> _lastKnown() async {
    if (kIsWeb) return null;
    try {
      final pos = await Geolocator.getLastKnownPosition();
      return pos == null ? null : _point(pos);
    } catch (_) {
      return null;
    }
  }

  static SosPoint _point(Position p) => SosPoint(p.latitude, p.longitude, accuracyM: p.accuracy, at: p.timestamp);
}
