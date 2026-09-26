import 'package:http/http.dart' as http;

import 'data_cache.dart';
import 'http_util.dart';

/// Approximate exchange rates. Xotelo's `/list` reports prices in USD only
/// (it rejects other currencies), while `/rates` can return INR. The list
/// prices are therefore converted approximately and always shown as estimates;
/// shortlisted hotels get exact INR totals from `/rates`.
abstract final class Fx {
  static double usdToInr = 88;

  static int inr(num usd) => (usd * usdToInr).round();
}

/// A hotel from Xotelo's `/list` (TripAdvisor data).
class XoteloHotel {
  const XoteloHotel({
    required this.name,
    required this.key,
    required this.type,
    this.url,
    this.rating,
    this.reviewCount,
    this.priceMinUsd,
    this.priceMaxUsd,
    this.lat,
    this.lng,
    this.image,
    this.labels = const [],
  });

  final String name;

  /// TripAdvisor hotel key, e.g. `g293916-d305228`.
  final String key;
  final String type;
  final String? url;
  final double? rating;
  final int? reviewCount;
  final double? priceMinUsd;
  final double? priceMaxUsd;
  final double? lat;
  final double? lng;
  final String? image;
  final List<String> labels;

  bool get hasLocation => lat != null && lng != null;

  /// Approximate nightly range in rupees, from the USD list prices.
  (int, int)? get approxNightlyInr {
    final lo = priceMinUsd;
    final hi = priceMaxUsd;
    if (lo == null && hi == null) return null;
    return (Fx.inr(lo ?? hi!), Fx.inr(hi ?? lo!));
  }

  static XoteloHotel? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final name = raw['name'] as String?;
    final key = raw['key'] as String?;
    if (name == null || key == null) return null;
    final geo = raw['geo'] as Map<String, dynamic>?;
    final review = raw['review_summary'] as Map<String, dynamic>?;
    final price = raw['price_ranges'] as Map<String, dynamic>?;
    return XoteloHotel(
      name: name,
      key: key,
      type: raw['accommodation_type'] as String? ?? 'Hotel',
      url: raw['url'] as String?,
      rating: asDouble(review?['rating']),
      reviewCount: asInt(review?['count']),
      priceMinUsd: asDouble(price?['minimum']),
      priceMaxUsd: asDouble(price?['maximum']),
      lat: asDouble(geo?['latitude']),
      lng: asDouble(geo?['longitude']),
      image: raw['image'] as String?,
      labels: [
        for (final l in (raw['merchandising_labels'] as List<dynamic>? ?? const []))
          if (l is String) l,
      ],
    );
  }
}

class XoteloList {
  const XoteloList({required this.total, required this.hotels});

  final int total;
  final List<XoteloHotel> hotels;
}

/// One online travel agency's total for the stay.
class XoteloRate {
  const XoteloRate({required this.code, required this.name, required this.rate, this.tax});

  final String code;
  final String name;

  /// Total for the whole stay, in the requested currency.
  final int rate;
  final int? tax;
}

class XoteloRates {
  const XoteloRates({
    required this.checkIn,
    required this.checkOut,
    required this.currency,
    required this.rates,
  });

  final String checkIn;
  final String checkOut;
  final String currency;
  final List<XoteloRate> rates;

  XoteloRate? get cheapest {
    if (rates.isEmpty) return null;
    return rates.reduce((a, b) => a.rate <= b.rate ? a : b);
  }
}

/// Which dates are cheap, average or expensive around the check-out date.
class XoteloHeatmap {
  const XoteloHeatmap({
    required this.average,
    required this.cheap,
    required this.high,
  });

  final List<String> average;
  final List<String> cheap;
  final List<String> high;

  /// "cheap" | "average" | "high" for an ISO date, or null when unknown.
  String? bandFor(String isoDate) {
    if (cheap.contains(isoDate)) return 'cheap';
    if (average.contains(isoDate)) return 'average';
    if (high.contains(isoDate)) return 'high';
    return null;
  }
}

/// A place or hotel matched by Xotelo's `/search` (RapidAPI only).
class XoteloPlace {
  const XoteloPlace({required this.name, required this.key, this.isHotel = false, this.lat, this.lng, this.detail});

  final String name;

  /// A TripAdvisor `location_key` (e.g. `g293916`) or a hotel key.
  final String key;
  final bool isHotel;
  final double? lat;
  final double? lng;
  final String? detail;
}

/// Xotelo Hotel Prices API (https://data.xotelo.com/api). `/list`, `/rates`
/// and `/heatmap` need no key; `/search` is served through RapidAPI and needs
/// [rapidApiKey]. Every call is cached and returns null on any failure.
class XoteloClient {
  XoteloClient({
    http.Client? client,
    DataCache? cache,
    this.rapidApiKey,
    this.base = 'https://data.xotelo.com/api',
  }) : _client = client ?? http.Client(),
       _cache = cache ?? MemoryCache();

  static const rapidApiHost = 'xotelo-hotel-prices.p.rapidapi.com';

  final http.Client _client;
  final DataCache _cache;
  final String? rapidApiKey;
  final String base;

  bool get canSearch => (rapidApiKey ?? '').isNotEmpty;

  /// Hotels in a TripAdvisor location, best value first.
  Future<XoteloList?> list(
    String locationKey, {
    int limit = 30,
    int offset = 0,
    String sort = 'best_value',
  }) async {
    final json = await _cache.rememberJson(
      'xotelo.list.$locationKey.$limit.$offset.$sort',
      () async {
        final o = await httpGet(
          _client,
          Uri.parse('$base/list').replace(queryParameters: {
            'location_key': locationKey,
            'limit': '$limit',
            'offset': '$offset',
            'sort': sort,
          }),
        );
        return _result(o);
      },
      ttl: const Duration(hours: 24),
    );
    return parseList(json);
  }

  static XoteloList? parseList(Object? result) {
    if (result is! Map<String, dynamic>) return null;
    final list = result['list'];
    if (list is! List) return null;
    final hotels = [
      for (final h in list)
        if (XoteloHotel.fromJson(h) case final hotel?) hotel,
    ];
    return XoteloList(total: asInt(result['total_count']) ?? hotels.length, hotels: hotels);
  }

  /// Live per-OTA totals for a stay (real prices; [currency] defaults to INR).
  Future<XoteloRates?> rates(
    String hotelKey, {
    required String checkIn,
    required String checkOut,
    int rooms = 1,
    int adults = 2,
    String currency = 'INR',
  }) async {
    final json = await _cache.rememberJson(
      'xotelo.rates.$hotelKey.$checkIn.$checkOut.$rooms.$adults.$currency',
      () async {
        final o = await httpGet(
          _client,
          Uri.parse('$base/rates').replace(queryParameters: {
            'hotel_key': hotelKey,
            'chk_in': checkIn,
            'chk_out': checkOut,
            'rooms': '$rooms',
            'adults': '$adults',
            'currency': currency,
          }),
        );
        return _result(o);
      },
      ttl: const Duration(hours: 1),
    );
    return parseRates(json);
  }

  static XoteloRates? parseRates(Object? result) {
    if (result is! Map<String, dynamic>) return null;
    final rates = result['rates'];
    if (rates is! List) return null;
    return XoteloRates(
      checkIn: result['chk_in'] as String? ?? '',
      checkOut: result['chk_out'] as String? ?? '',
      currency: result['currency'] as String? ?? 'INR',
      rates: [
        for (final r in rates)
          if (r is Map<String, dynamic> && asInt(r['rate']) != null)
            XoteloRate(
              code: r['code'] as String? ?? '',
              name: r['name'] as String? ?? (r['code'] as String? ?? 'OTA'),
              rate: asInt(r['rate'])!,
              tax: asInt(r['tax']),
            ),
      ],
    );
  }

  /// Cheap / average / high-price dates around [checkOut].
  Future<XoteloHeatmap?> heatmap(String hotelKey, {required String checkOut}) async {
    final json = await _cache.rememberJson(
      'xotelo.heatmap.$hotelKey.$checkOut',
      () async {
        final o = await httpGet(
          _client,
          Uri.parse('$base/heatmap').replace(queryParameters: {
            'hotel_key': hotelKey,
            'chk_out': checkOut,
          }),
        );
        return _result(o);
      },
      ttl: const Duration(hours: 6),
    );
    return parseHeatmap(json);
  }

  static XoteloHeatmap? parseHeatmap(Object? result) {
    if (result is! Map<String, dynamic>) return null;
    final h = result['heatmap'];
    if (h is! Map<String, dynamic>) return null;
    List<String> days(String k) => [
      for (final d in (h[k] as List<dynamic>? ?? const []))
        if (d is String) d,
    ];
    return XoteloHeatmap(
      average: days('average_price_days'),
      cheap: days('cheap_price_days'),
      high: days('high_price_days'),
    );
  }

  /// City or hotel name -> TripAdvisor key. Needs [rapidApiKey]; without one it
  /// returns null and the caller uses another resolver.
  Future<List<XoteloPlace>?> search(String query) async {
    if (!canSearch || query.trim().isEmpty) return null;
    final json = await _cache.rememberJson(
      'xotelo.search.${query.trim().toLowerCase()}',
      () async {
        final o = await httpGet(
          _client,
          Uri.https(rapidApiHost, '/api/search', {'query': query.trim()}),
          headers: {'x-rapidapi-key': rapidApiKey!, 'x-rapidapi-host': rapidApiHost},
        );
        return _result(o);
      },
      ttl: const Duration(days: 7),
    );
    return parseSearch(json);
  }

  /// Tolerant: the shape of `/search` is only reachable with a key, so accept
  /// the field names it is documented to use and a few near variants.
  static List<XoteloPlace>? parseSearch(Object? result) {
    if (result is! Map<String, dynamic>) return null;
    final list = result['list'] ?? result['results'] ?? result['places'];
    if (list is! List) return null;
    final out = <XoteloPlace>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final key = (item['location_key'] ?? item['hotel_key'] ?? item['key']) as String?;
      final name = (item['name'] ?? item['short_place_name'] ?? item['title']) as String?;
      if (key == null || name == null) continue;
      final geo = item['geo'] as Map<String, dynamic>?;
      out.add(
        XoteloPlace(
          name: name,
          key: key,
          isHotel: item.containsKey('hotel_key') || key.contains('-d'),
          lat: asDouble(geo?['latitude'] ?? item['latitude']),
          lng: asDouble(geo?['longitude'] ?? item['longitude']),
          detail: (item['place_type'] ?? item['detail'] ?? item['secondary_text']) as String?,
        ),
      );
    }
    return out;
  }

  /// The `result` of a successful call, else null (so failures are not cached).
  static Object? _result(HttpOutcome o) {
    final m = o.map;
    if (m == null) return null;
    if (m['error'] != null) return null;
    return m['result'];
  }
}
