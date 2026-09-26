import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/live_city_data.dart';

/// Open-Meteo weather + air-quality telemetry. Replaces the two Retrofit
/// interfaces (`OpenMeteoService`, `AirQualityService`) and the inline
/// weather/AQI calls scattered across the Kotlin sources with one client.
abstract final class OpenMeteoService {
  static const _weatherBase = 'https://api.open-meteo.com/v1/forecast';
  static const _aqiBase =
      'https://air-quality-api.open-meteo.com/v1/air-quality';
  static const _timeout = Duration(seconds: 15);

  /// Current conditions + the past week of hourly AQI, used by the Dashboard.
  static Future<DashboardTelemetry?> fetchDashboardTelemetry(
    double lat,
    double lon,
  ) async {
    final weather = await _getJson(
      Uri.parse(
        '$_weatherBase?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m'
        '&timezone=auto',
      ),
    );
    final aqi = await _getJson(
      Uri.parse(
        '$_aqiBase?latitude=$lat&longitude=$lon'
        '&current=us_aqi,pm2_5&hourly=us_aqi&past_days=7&timezone=auto',
      ),
    );
    if (weather == null && aqi == null) return null;

    final current = weather?['current'] as Map<String, dynamic>?;
    final currentAqi = aqi?['current'] as Map<String, dynamic>?;
    final hourly = aqi?['hourly'] as Map<String, dynamic>?;

    return DashboardTelemetry(
      temperatureC: (current?['temperature_2m'] as num?)?.toDouble(),
      condition: current == null
          ? null
          : weatherCodeToCondition(
              (current['weather_code'] as num?)?.toInt() ?? 0,
            ),
      usAqi: (currentAqi?['us_aqi'] as num?)?.toInt(),
      pm25: (currentAqi?['pm2_5'] as num?)?.toDouble(),
      dailyAqi: _dailyAverages(
        (hourly?['time'] as List<dynamic>?)?.cast<String>(),
        (hourly?['us_aqi'] as List<dynamic>?),
      ),
    );
  }

  /// Combined current weather + AQI reading at one point. Port of
  /// `LiveCityIntelligenceService.getLiveWeatherAndAqi`; returns null only when
  /// both requests fail, and falls back to the same documented default figures
  /// the Kotlin version used for any individual missing field.
  static Future<LiveWeatherAqiData?> getLiveWeatherAndAqi(
    double lat,
    double lon,
  ) async {
    final weather = await _getJson(
      Uri.parse(
        '$_weatherBase?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m',
      ),
    );
    final aqi = await _getJson(
      Uri.parse(
        '$_aqiBase?latitude=$lat&longitude=$lon&current=pm2_5,pm10,us_aqi',
      ),
    );
    if (weather == null && aqi == null) return null;

    final current = weather?['current'] as Map<String, dynamic>?;
    final currentAqi = aqi?['current'] as Map<String, dynamic>?;

    return LiveWeatherAqiData(
      temperatureC: (current?['temperature_2m'] as num?)?.toDouble() ?? 28.0,
      humidityPercent:
          (current?['relative_humidity_2m'] as num?)?.toInt() ?? 65,
      windSpeedKmh: (current?['wind_speed_10m'] as num?)?.toDouble() ?? 12.0,
      pm25: (currentAqi?['pm2_5'] as num?)?.toDouble() ?? 38.0,
      pm10: (currentAqi?['pm10'] as num?)?.toDouble() ?? 65.0,
      usAqi: (currentAqi?['us_aqi'] as num?)?.toInt() ?? 110,
      condition: weatherCodeToCondition(
        (current?['weather_code'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Current US AQI at a point, used by the Live Map HUD.
  static Future<int?> fetchCurrentUsAqi(double lat, double lon) async {
    final json = await _getJson(
      Uri.parse(
        '$_aqiBase?latitude=$lat&longitude=$lon&current=european_aqi,pm2_5,pm10,us_aqi',
      ),
    );
    return ((json?['current'] as Map<String, dynamic>?)?['us_aqi'] as num?)
        ?.toInt();
  }

  /// WMO weather-code buckets, matching the Kotlin `when (code)` mapping.
  static String weatherCodeToCondition(int code) => switch (code) {
    0 => 'Clear Sky',
    1 || 2 || 3 => 'Partly Cloudy',
    45 || 48 => 'Foggy / Hazy',
    51 || 53 || 55 || 61 || 63 => 'Showers',
    _ => 'Cloudy',
  };

  /// Collapses hourly AQI readings into one average per calendar day, which is
  /// what the "Air Quality Trend (7 Days)" chart plots. Each point keeps its real
  /// date so the chart can label the actual weekdays rather than assuming
  /// Monday-Sunday.
  static List<DailyAqi> _dailyAverages(
    List<String>? times,
    List<dynamic>? values,
  ) {
    if (times == null || values == null || times.length != values.length) {
      return const [];
    }

    final sums = <String, double>{};
    final counts = <String, int>{};
    for (var i = 0; i < times.length; i++) {
      final value = (values[i] as num?)?.toDouble();
      if (value == null) continue;
      final day = times[i].split('T').first;
      sums[day] = (sums[day] ?? 0) + value;
      counts[day] = (counts[day] ?? 0) + 1;
    }

    final days = sums.keys.toList()..sort();
    final points = [
      for (final day in days)
        if (DateTime.tryParse(day) case final date?)
          DailyAqi(date: date, usAqi: sums[day]! / counts[day]!),
    ];
    // The request asks for seven past days plus today; keep the last seven.
    return points.length > 7 ? points.sublist(points.length - 7) : points;
  }

  static Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

/// What the Dashboard needs in one shot: current conditions plus the daily AQI
/// series behind the trend chart.
class DashboardTelemetry {
  const DashboardTelemetry({
    required this.temperatureC,
    required this.condition,
    required this.usAqi,
    required this.pm25,
    required this.dailyAqi,
  });

  final double? temperatureC;
  final String? condition;
  final int? usAqi;
  final double? pm25;
  final List<DailyAqi> dailyAqi;
}

/// One day's averaged US AQI, with the date it was measured on.
class DailyAqi {
  const DailyAqi({required this.date, required this.usAqi});

  final DateTime date;
  final double usAqi;
}
