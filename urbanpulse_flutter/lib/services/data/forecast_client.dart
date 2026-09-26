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
  /// Rain heavy enough to spoil an outdoor visit: 8 mm or more, a 70% chance,
  /// or a WMO code for moderate-to-heavy rain, heavy showers or thunder.
  /// Drizzle, slight rain and slight showers (51-61, 80) do not count.
  bool get isRainy =>
      (rainMm ?? 0) >= 8 || (rainProbability ?? 0) >= 70 || (weatherCode != null && _heavyRainCodes.contains(weatherCode));

  static const _heavyRainCodes = {63, 65, 66, 67, 81, 82, 95, 96, 99};

  bool get isHot => (tempMaxC ?? 0) >= 37;

  String get summary {
    final parts = <String>[
      if (tempMaxC != null) '${tempMaxC!.round()}°C',
      if (rainProbability != null) '$rainProbability% rain',
      if (rainMm != null && rainMm! > 0) '${rainMm!.toStringAsFixed(0)} mm',
    ];
    if (parts.isEmpty) return 'no data';
    return isForecast ? parts.join(', ') : 'typically ${parts.join(', ')}';
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

  /// The forecast for the days it covers and, for the rest, what the same dates
  /// were like in the last few years (marked `isForecast: false`). Empty only
  /// if neither is available.
  Future<List<DayForecast>> outlook(double lat, double lon, DateTime start, DateTime end, {DateTime? today}) async {
    final t0 = today ?? DateTime.now();
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    final forecast = await daily(lat, lon, start, end, today: t0);
    final have = {for (final f in forecast) f.date};
    final missing = <DateTime>[];
    for (var d = s; !d.isAfter(e); d = d.add(const Duration(days: 1))) {
      if (!have.contains(_iso(d))) missing.add(d);
    }
    if (missing.isEmpty) return forecast;
    List<DayForecast> seasonalDays;
    try {
      seasonalDays = await seasonal(lat, lon, missing, today: t0);
    } catch (_) {
      seasonalDays = const [];
    }
    return [...forecast, ...seasonalDays]..sort((a, b) => a.date.compareTo(b.date));
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Typical weather for [days] from the same calendar dates in the previous
  /// [years] years, averaged. A guide to the season, not a forecast.
  Future<List<DayForecast>> seasonal(double lat, double lon, List<DateTime> days, {DateTime? today, int years = 3}) async {
    if (days.isEmpty) return const [];
    final t0 = today ?? DateTime.now();
    final first = days.first;
    final last = days.last;
    // A year back for the first date, the same span each earlier year.
    final perYear = <List<DayForecast>>[];
    for (var back = 1; back <= years; back++) {
      final a = DateTime(first.year - back, first.month, first.day);
      final b = DateTime(last.year - back, last.month, last.day);
      // The archive lags a few days behind today.
      final newest = DateTime(t0.year, t0.month, t0.day).subtract(const Duration(days: 6));
      if (b.isAfter(newest)) continue;
      if (b.isBefore(a)) continue;
      final json = await _cache.rememberJson(
        'archive.${lat.toStringAsFixed(2)}.${lon.toStringAsFixed(2)}.${_iso(a)}.${_iso(b)}',
        () async {
          final o = await httpGet(
            _client,
            Uri.https('archive-api.open-meteo.com', '/v1/archive', {
              'latitude': '$lat',
              'longitude': '$lon',
              'daily': 'temperature_2m_max,temperature_2m_min,precipitation_sum',
              'timezone': 'auto',
              'start_date': _iso(a),
              'end_date': _iso(b),
            }),
          );
          return o.map?['daily'];
        },
        ttl: const Duration(days: 30),
      );
      final parsed = parse(json);
      if (parsed.isNotEmpty) perYear.add(parsed);
    }
    if (perYear.isEmpty) return const [];

    final out = <DayForecast>[];
    for (var i = 0; i < days.length; i++) {
      final samples = [for (final y in perYear) if (i < y.length) y[i]];
      if (samples.isEmpty) continue;
      double? mean(Iterable<double?> v) {
        final xs = [for (final x in v) if (x != null) x];
        return xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;
      }

      final rainMm = mean(samples.map((d) => d.rainMm));
      final wet = samples.where((d) => (d.rainMm ?? 0) >= 5).length;
      out.add(
        DayForecast(
          date: _iso(days[i]),
          tempMaxC: mean(samples.map((d) => d.tempMaxC)),
          tempMinC: mean(samples.map((d) => d.tempMinC)),
          rainMm: rainMm,
          rainProbability: (wet * 100 / samples.length).round(),
          // A stand-in for the WMO code so "rainy" reads consistently.
          weatherCode: (rainMm ?? 0) >= 8 ? 63 : ((rainMm ?? 0) >= 2 ? 51 : 1),
          isForecast: false,
        ),
      );
    }
    return out;
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
