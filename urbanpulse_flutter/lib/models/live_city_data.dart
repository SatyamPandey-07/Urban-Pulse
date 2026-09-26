// Response shapes for the live-intelligence services (TomTom POI/traffic and
// Open-Meteo weather/AQI). Port of the data classes in
// `network/LiveCityIntelligenceService.kt`.

class LivePoiResult {
  const LivePoiResult({
    required this.name,
    required this.address,
    required this.distanceMeters,
    required this.lat,
    required this.lon,
    this.phone,
    this.category,
  });

  final String name;
  final String address;
  final double distanceMeters;
  final String? phone;
  final double lat;
  final double lon;
  final String? category;
}

class LiveTrafficData {
  const LiveTrafficData({
    required this.roadName,
    required this.currentSpeedKmh,
    required this.freeFlowSpeedKmh,
    required this.delaySeconds,
    required this.confidence,
  });

  final String roadName;
  final int currentSpeedKmh;
  final int freeFlowSpeedKmh;
  final int delaySeconds;
  final double confidence;
}

class LiveWeatherAqiData {
  const LiveWeatherAqiData({
    required this.temperatureC,
    required this.humidityPercent,
    required this.windSpeedKmh,
    required this.pm25,
    required this.pm10,
    required this.usAqi,
    required this.condition,
  });

  final double temperatureC;
  final int humidityPercent;
  final double windSpeedKmh;
  final double pm25;
  final double pm10;
  final int usAqi;

  /// "Clear Sky", "Partly Cloudy", "Foggy / Hazy", "Showers", "Cloudy".
  final String condition;

  bool get isRaining => condition == 'Showers';
}

/// One real road route returned by the TomTom Routing API.
class RouteResult {
  const RouteResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
  });

  /// Ordered `[lat, lon]` pairs of the route geometry.
  final List<List<double>> points;
  final double distanceKm;
  final int durationMin;
}

/// A live flow reading together with the real road geometry it describes.
class LiveTrafficSegment {
  const LiveTrafficSegment({required this.data, required this.geometry});

  final LiveTrafficData data;

  /// Ordered `[lat, lon]` pairs tracing the segment.
  final List<List<double>> geometry;
}
