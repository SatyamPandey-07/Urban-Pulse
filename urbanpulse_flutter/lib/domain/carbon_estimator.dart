import 'dart:math' as math;

import '../models/mobility.dart';

/// Computes real, distance-driven trip estimates instead of hardcoded per-mode
/// numbers. Per-km factors are approximate published averages for an Indian
/// metro-city grid mix; they are deliberately simple (linear in distance) rather
/// than a fabricated ML model.
///
/// Port of the pure half of `mobility/CarbonEstimator.kt`; the live TomTom
/// road-distance lookup lives in `services/tomtom_routing_service.dart`.
abstract final class CarbonEstimator {
  static const _earthRadiusKm = 6371.0;

  /// name-fragment (lowercase) -> (lat, lng). First match wins.
  static const _landmarks = <String, (double, double)>{
    'chhatrapati shivaji': (18.9398, 72.8355),
    'csmt': (18.9398, 72.8355),
    'vile parle': (19.0970, 72.8479),
    'bandra': (19.0596, 72.8295),
    'parel': (19.0018, 72.8339),
    'borivali': (19.2307, 72.8567),
    'andheri': (19.1136, 72.8697),
    'dadar': (19.0178, 72.8478),
    'thane': (19.2183, 72.9781),
    'mulund': (19.1728, 72.9425),
  };

  static final _gpsCoordinatePattern = RegExp(
    r'(-?\d+\.\d+)\s*°?\s*N.*?(-?\d+\.\d+)\s*°?\s*E',
    caseSensitive: false,
  );

  static const _profiles = <TravelMode, _ModeProfile>{
    TravelMode.walk: _ModeProfile(
      avgSpeedKmh: 4.8,
      baseFare: 0,
      farePerKm: 0.0,
      gramsPerKm: 0.0,
      stepFree: false,
      accessibilityNote: 'Self-paced, no vehicle boarding — not suited to wheelchair users over distance',
      maxPracticalKm: 3.0,
      impracticalReason: 'Too far to walk practically',
    ),
    TravelMode.cycle: _ModeProfile(
      avgSpeedKmh: 14.0,
      baseFare: 10,
      farePerKm: 2.0,
      gramsPerKm: 0.0,
      stepFree: false,
      accessibilityNote:
          'Requires cycling ability — bike-share dock access only',
      maxPracticalKm: 10.0,
      impracticalReason: 'Too far for a shared-cycle trip',
    ),
    TravelMode.metro: _ModeProfile(
      avgSpeedKmh: 32.0,
      baseFare: 10,
      farePerKm: 2.5,
      gramsPerKm: 14.0,
      stepFree: true,
      accessibilityNote: '100% Step-Free • Tactile Paving • Level Boarding',
    ),
    TravelMode.bus: _ModeProfile(
      avgSpeedKmh: 18.0,
      baseFare: 5,
      farePerKm: 1.2,
      gramsPerKm: 21.0,
      stepFree: true,
      accessibilityNote: 'Low-floor hydraulic wheelchair ramp',
    ),
    TravelMode.evCab: _ModeProfile(
      avgSpeedKmh: 24.0,
      baseFare: 40,
      farePerKm: 12.0,
      gramsPerKm: 35.0,
      stepFree: false,
      accessibilityNote: 'Curbside door-to-door, folding wheelchair trunk',
    ),
    TravelMode.taxi: _ModeProfile(
      avgSpeedKmh: 22.0,
      baseFare: 50,
      farePerKm: 18.0,
      gramsPerKm: 140.0,
      stepFree: false,
      accessibilityNote: 'Standard sedan curbside',
    ),
  };

  /// Resolves free-text (a GPS-lock string or a landmark name) to lat/lng, with
  /// a Mumbai-center fallback.
  static (double, double) resolveCoordinates(String text) {
    final match = _gpsCoordinatePattern.firstMatch(text);
    if (match != null) {
      final lat = double.tryParse(match.group(1) ?? '');
      final lng = double.tryParse(match.group(2) ?? '');
      if (lat != null && lng != null) return (lat, lng);
    }
    final lower = text.toLowerCase();
    for (final entry in _landmarks.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return (19.0760, 72.8777); // Mumbai city-center fallback
  }

  /// Great-circle distance between two lat/lng points, in kilometers.
  static double haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    double toRadians(double deg) => deg * math.pi / 180.0;
    final dLat = toRadians(lat2 - lat1);
    final dLng = toRadians(lng2 - lng1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(toRadians(lat1)) *
            math.cos(toRadians(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusKm * c;
  }

  static double estimateDistanceKm(String originText, String destinationText) {
    final (lat1, lng1) = resolveCoordinates(originText);
    final (lat2, lng2) = resolveCoordinates(destinationText);
    final straightLine = haversineKm(lat1, lng1, lat2, lng2);
    // Road/rail routes are never a straight line; apply a realistic detour factor.
    final routed = straightLine * 1.35;
    return math.max(math.min(routed, 60.0), 1.5);
  }

  static MobilityOption estimateOption(TravelMode mode, double distanceKm) {
    final profile = _profiles[mode]!;
    final durationMin = math.max(
      ((distanceKm / profile.avgSpeedKmh) * 60).round(),
      3,
    );
    final fare = (profile.baseFare + distanceKm * profile.farePerKm).round();
    final carbon = distanceKm * profile.gramsPerKm;
    final isPractical =
        profile.maxPracticalKm == null || distanceKm <= profile.maxPracticalKm!;
    return MobilityOption(
      mode: mode,
      distanceKm: distanceKm,
      durationMin: durationMin,
      fareRupees: fare,
      carbonGrams: carbon,
      stepFreeAccessible: profile.stepFree,
      accessibilityNote: profile.accessibilityNote,
      practical: isPractical,
      impracticalReason: isPractical ? null : profile.impracticalReason,
    );
  }

  static List<MobilityOption> estimateAllModes(double distanceKm) =>
      TravelMode.values.map((m) => estimateOption(m, distanceKm)).toList();
}

class _ModeProfile {
  const _ModeProfile({
    required this.avgSpeedKmh,
    required this.baseFare,
    required this.farePerKm,
    required this.gramsPerKm,
    required this.stepFree,
    required this.accessibilityNote,
    this.maxPracticalKm,
    this.impracticalReason,
  });

  final double avgSpeedKmh;
  final int baseFare;
  final double farePerKm;
  final double gramsPerKm;
  final bool stepFree;
  final String accessibilityNote;

  /// Beyond this distance the mode is not a realistic choice (e.g. walking
  /// 20km). Null = no cap.
  final double? maxPracticalKm;
  final String? impracticalReason;
}
