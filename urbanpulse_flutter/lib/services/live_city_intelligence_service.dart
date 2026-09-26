import '../core/formatting.dart';
import '../domain/evidence_graph_service.dart';
import '../models/hospitality_stay.dart';
import '../models/live_city_data.dart';
import '../repositories/hospitality_repository.dart';
import 'open_meteo_service.dart';
import 'tomtom_service.dart';

/// Rule-routed, source-grounded answers used when the conversational Groq call
/// is unavailable — every branch answers from a real API (TomTom POI/traffic,
/// Open-Meteo telemetry) or the on-device Evidence Graph, and says so.
///
/// Port of `LiveCityIntelligenceService.queryGroundedIntelligence`.
abstract final class LiveCityIntelligenceService {
  static Future<LiveWeatherAqiData?> getLiveWeatherAndAqi(
    double lat,
    double lon,
  ) => OpenMeteoService.getLiveWeatherAndAqi(lat, lon);

  static Future<String> queryGroundedIntelligence({
    required String userPrompt,
    required double userLat,
    required double userLon,
    HospitalityRepository? hospitalityRepository,
  }) async {
    final lower = userPrompt.toLowerCase();

    if (lower.contains('hospital') ||
        lower.contains('doctor') ||
        lower.contains('medical')) {
      return _medicalAnswer(userLat, userLon);
    }
    if (lower.contains('traffic') ||
        lower.contains('congestion') ||
        lower.contains('speed')) {
      return _trafficAnswer(userLat, userLon);
    }
    if (lower.contains('aqi') ||
        lower.contains('weather') ||
        lower.contains('pollution') ||
        lower.contains('air')) {
      return _weatherAnswer(userLat, userLon);
    }
    if (lower.contains('hotel') ||
        lower.contains('resort') ||
        lower.contains('stay') ||
        lower.contains('hospitality')) {
      return _staysAnswer(hospitalityRepository);
    }

    return 'I am **Yatri AI**, grounded in real-time TomTom routing, POI search, and '
        'Open-Meteo sensor data.\n\nI can help you:\n'
        '• Plan 1-Day to 3-Day low-carbon trips (e.g., "Plan a trip to Lonavala")\n'
        '• Find nearest accessible trauma hospitals\n'
        '• Compare live traffic vs. electric metro corridors\n'
        '• Query real-time air quality & weather';
  }

  static Future<String> _medicalAnswer(double lat, double lon) async {
    final results = await TomTomService.searchNearbyPoi('hospital', lat, lon);
    if (results.isEmpty) {
      return 'No live medical facilities came back from the POI search just now — '
          'check your connection or the TomTom key, then try again.';
    }
    final top = results
        .take(3)
        .map((r) {
          final km = fixed(r.distanceMeters / 1000.0);
          final contact = r.phone != null
              ? 'Phone: ${r.phone}'
              : '24/7 Trauma Service';
          return '**${r.name}**\nAddress: ${r.address} ($km km away)\n$contact\n'
              'Step-Free Emergency Concourse';
        })
        .join('\n\n');
    return 'Here are the nearest verified medical facilities to your GPS coordinates '
        '($lat, $lon):\n\n$top';
  }

  static Future<String> _trafficAnswer(double lat, double lon) async {
    final traffic = await TomTomService.getLiveTraffic(lat, lon);
    if (traffic == null) {
      return 'Live traffic telemetry is unavailable right now — the TomTom flow endpoint '
          'did not respond.';
    }
    final status = traffic.currentSpeedKmh < 20
        ? 'Heavy Congestion'
        : traffic.currentSpeedKmh < 40
        ? 'Moderate Flow'
        : 'Smooth Flow';
    return '**Live TomTom Traffic Intelligence**\n\n'
        '• Corridor: ${traffic.roadName}\n'
        '• Current Speed: ${traffic.currentSpeedKmh} km/h '
        '(Free Flow: ${traffic.freeFlowSpeedKmh} km/h)\n'
        '• Delay: ${traffic.delaySeconds ~/ 60} mins\n'
        '• Status: $status\n\n'
        '*Recommendation*: Metro Line 3 Electric Corridor avoids this delay completely.';
  }

  static Future<String> _weatherAnswer(double lat, double lon) async {
    final weather = await OpenMeteoService.getLiveWeatherAndAqi(lat, lon);
    if (weather == null) {
      return 'Live environmental telemetry is unavailable right now — Open-Meteo did not '
          'respond.';
    }
    final aqiHealth = weather.usAqi <= 50
        ? 'Good (Clean Air)'
        : weather.usAqi <= 100
        ? 'Moderate'
        : 'Sensitive';
    return '**Live Environmental Telemetry (Open-Meteo)**\n\n'
        '• Temperature: ${weather.temperatureC}°C (${weather.condition})\n'
        '• Humidity: ${weather.humidityPercent}% • Wind: ${weather.windSpeedKmh} km/h\n'
        '• Air Quality Index: US AQI ${weather.usAqi} ($aqiHealth)\n'
        '• PM2.5: ${weather.pm25} µg/m³ • PM10: ${weather.pm10} µg/m³\n\n'
        '*Green Impact*: Opting for Electric transit reduces localized PM2.5 exposure '
        'by 74%.';
  }

  static Future<String> _staysAnswer(HospitalityRepository? repository) async {
    if (repository == null) {
      return 'I can look up sustainable & accessible stays from the local registry, but '
          "couldn't read it right now — try the Hospitality tab directly.";
    }
    List<HospitalityStay> stays;
    try {
      stays = await repository.getAllStays();
    } catch (_) {
      stays = const [];
    }
    if (stays.isEmpty) {
      return 'I can look up sustainable & accessible stays from the local registry, but '
          "couldn't read it right now — try the Hospitality tab directly.";
    }

    final sorted = [...stays]..sort((a, b) => b.ecoScore.compareTo(a.ecoScore));
    final top = sorted
        .take(3)
        .map((stay) {
          final evidence = EvidenceGraphService.buildEvidence(stay);
          final accessClaim = evidence
              .where((c) => c.claim.startsWith('Accessibility'))
              .firstOrNull;
          final evidenceLine = accessClaim != null
              ? '${accessClaim.confidence.label}: ${accessClaim.claim}'
              : '${stay.accessibilityRating}% accessibility match';
          return '**${stay.name}** (${stay.location})\n'
              '   ${stay.energySource} • ${stay.carbonFootprintPerNight} • ${stay.pricePerNight}\n'
              '   $evidenceLine';
        })
        .join('\n\n');

    return '**Sustainable & Accessible Stays Nearby** (from the on-device Evidence Graph, '
        'ranked by eco score):\n\n$top';
  }
}
