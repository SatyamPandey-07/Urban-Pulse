import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Where the traveller is, as reported by the device.
class UserFix {
  const UserFix({required this.point, this.accuracyM, this.headingDeg, this.speedMps});

  final LatLng point;
  final double? accuracyM;

  /// Direction of travel in degrees, when moving.
  final double? headingDeg;
  final double? speedMps;
}

/// Why there may be no position.
enum LocationStatus { unknown, ok, denied, deniedForever, serviceOff, unavailable }

class LocationResult {
  const LocationResult(this.status, [this.fix]);

  final LocationStatus status;
  final UserFix? fix;
}

/// The device location, behind an interface so the map can be driven in tests.
abstract class LiveLocation {
  /// Asks for permission if needed and reads one position.
  Future<LocationResult> request();

  /// Positions as the traveller moves.
  Stream<UserFix> watch({int distanceFilterM = 5});

  /// Opens the system page where location can be switched on or allowed.
  Future<void> openSettings(LocationStatus status);
}

class DeviceLocation implements LiveLocation {
  const DeviceLocation();

  static UserFix _fix(Position p) => UserFix(
    point: LatLng(p.latitude, p.longitude),
    accuracyM: p.accuracy > 0 ? p.accuracy : null,
    headingDeg: p.heading >= 0 && p.speed > 0.8 ? p.heading : null,
    speedMps: p.speed >= 0 ? p.speed : null,
  );

  @override
  Future<LocationResult> request() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return const LocationResult(LocationStatus.serviceOff);
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) return const LocationResult(LocationStatus.deniedForever);
      if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
        return const LocationResult(LocationStatus.denied);
      }
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)).timeout(const Duration(seconds: 12));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return const LocationResult(LocationStatus.unavailable);
      return LocationResult(LocationStatus.ok, _fix(pos));
    } catch (_) {
      return const LocationResult(LocationStatus.unavailable);
    }
  }

  @override
  Stream<UserFix> watch({int distanceFilterM = 5}) {
    try {
      return Geolocator.getPositionStream(locationSettings: LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: distanceFilterM)).map(_fix);
    } catch (_) {
      return const Stream.empty();
    }
  }

  @override
  Future<void> openSettings(LocationStatus status) async {
    try {
      if (status == LocationStatus.serviceOff) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
  }
}
