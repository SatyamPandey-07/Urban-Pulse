import 'package:http/http.dart' as http;

import 'data_cache.dart';
import 'http_util.dart';

/// One day of weather for the route optimizer.
class DayForecast {
  const DayForecast({
    required this.date,
    this.tempMaxC,
    this.tempMinC,
    this.rainMm,
    this.rainProbability,
    this.weatherCode,
    this.isForecast = true,
  });

  /// ISO date, `2026-10-12`.
  final String date;
  final double? tempMaxC;
  final double? tempMinC;
  final double? rainMm;

  /// 0-100.
  final int? rainProbability;

  /// WMO weather code.
  final int? weatherCode;

  /// False for a climatological guess rather than a real forecast.
  final bool isForecast;

  /// Heavy enough rain that outdoor plans should be reconsidered.
  bool get isRainy =>
      (rainMm ?? 0) >= 8 || (rainProbability ?? 0) >= 70 || (weatherCode != null && weatherCode! >= 61 && weatherCode! <= 99);

  bool get isHot => (tempMaxC ?? 0) >= 37;

  String get summary {
    final parts = <String>[
      if (tempMaxC != null) '${tempMaxC!.round()}°C',
      if (rainProbability != null) '$rainProbability% rain',
      if (rainMm != null && rainMm! > 0) '${rainMm!.toStringAsFixed(0)} mm',
    ];
    return parts.isEmpty ? 'no data' : parts.join(', ');
  }
}

/// Open-Meteo daily forecast (free, no key). Forecasts reach about 16 days
/// ahead; beyond that [daily] returns an empty list and Raah falls back to a
/// labelled seasonal estimate.
class ForecastClient {
  ForecastClient({http.Client? client, DataCache? cache})
    : _client = client ?? http.Client(),
      _cache = cache ?? MemoryCache();

  static const horizonDays = 16;

  final http.Client _client;
  final DataCache _cache;

  Future<List<DayForecast>> daily(double lat, double lon, DateTime start, DateTime end, {DateTime? today}) async {
    final t0 = today ?? DateTime.now();
    final first = DateTime(t0.year, t0.month, t0.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    // Only the part of the trip inside the forecast window can be answered.
    final limit = first.add(const Duration(days: horizonDays - 1));
    if (s.isAfter(limit)) return const [];
    final from = s.isBefore(first) ? first : s;
    final to = e.isAfter(limit) ? limit : e;
    if (to.isBefore(from)) return const [];

    String iso(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final json = await _cache.rememberJson(
      'forecast.${lat.toStringAsFixed(2)}.${lon.toStringAsFixed(2)}.${iso(from)}.${iso(to)}',
      () async {
        final o = await httpGet(
          _client,
          Uri.https('api.open-meteo.com', '/v1/forecast', {
            'latitude': '$lat',
            'longitude': '$lon',
            'daily': 'temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,weathercode',
            'timezone': 'auto',
            'start_date': iso(from),
            'end_date': iso(to),
          }),
        );
        return o.map?['daily'];
      },
      ttl: const Duration(hours: 3),
    );
    return parse(json);
  }

  static List<DayForecast> parse(Object? daily) {
    if (daily is! Map<String, dynamic>) return const [];
    final times = daily['time'];
    if (times is! List) return const [];
    List<dynamic> col(String k) => (daily[k] as List<dynamic>?) ?? const [];
    final tMax = col('temperature_2m_max');
    final tMin = col('temperature_2m_min');
    final rain = col('precipitation_sum');
    final prob = col('precipitation_probability_max');
    final code = col('weathercode');
    T? at<T>(List<dynamic> l, int i) => i < l.length ? l[i] as T? : null;
    return [
      for (var i = 0; i < times.length; i++)
        DayForecast(
          date: '${times[i]}',
          tempMaxC: asDouble(at<Object>(tMax, i)),
          tempMinC: asDouble(at<Object>(tMin, i)),
          rainMm: asDouble(at<Object>(rain, i)),
          rainProbability: asInt(at<Object>(prob, i)),
          weatherCode: asInt(at<Object>(code, i)),
        ),
    ];
  }
}
