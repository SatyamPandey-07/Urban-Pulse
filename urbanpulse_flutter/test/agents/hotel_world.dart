import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/agents/atithi/hotel_finder.dart';
import 'package:urbanpulse/agents/tools/agent_tool.dart';
import 'package:urbanpulse/agents/tools/fetch_page_tool.dart';
import 'package:urbanpulse/agents/tools/web_search_tool.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/services/data/ai_estimator.dart';
import 'package:urbanpulse/services/data/data_cache.dart';
import 'package:urbanpulse/services/data/geoapify_client.dart';
import 'package:urbanpulse/services/data/location_key_resolver.dart';
import 'package:urbanpulse/services/data/overpass_client.dart';
import 'package:urbanpulse/services/data/xotelo_client.dart';

import 'scripted.dart';

const munnarCenter = LatLng(10.0889, 77.0595);
const bengaluruCenter = LatLng(12.9716, 77.5946);

/// One hotel as the scripted TripAdvisor / Xotelo answers describe it.
class WorldHotel {
  const WorldHotel(
    this.key,
    this.name, {
    this.rating = 4.2,
    this.reviews = 300,
    this.usdMin = 30,
    this.usdMax = 50,
    this.dLat = 0.004,
    this.dLng = 0.004,
    this.totalInr = 9000,
    this.pageText = 'Free parking, breakfast, restaurant.',
    this.type = 'Hotel',
  });

  final String key;
  final String name;
  final double rating;
  final int reviews;
  final double usdMin;
  final double usdMax;
  final double dLat;
  final double dLng;

  /// The cheapest OTA total for the whole stay, in rupees.
  final int totalInr;
  final String pageText;
  final String type;

  LatLng get where => LatLng(munnarCenter.latitude + dLat, munnarCenter.longitude + dLng);
}

/// Scripted answers from the outside world for hotel tests: Xotelo, Geoapify, Overpass and TripAdvisor
/// pages for Munnar, with switches to knock each service out.
class HotelWorld {
  HotelWorld({
    List<WorldHotel>? xotelo,
    this.geoapifyPlaces = const [],
    this.overpassPlaces = const [],
    this.locationKey = 'g100001',
    this.xoteloDown = false,
    this.geoapifyDown = false,
    this.overpassDown = false,
    this.tripAdvisorDown = false,
    this.ratesDown = false,
    this.heatmap,
  }) : hotels = xotelo ?? defaultHotels;

  static const defaultHotels = [
    WorldHotel('g100001-d1', 'Sunrise Heritage Homestay', rating: 4.6, reviews: 812, usdMin: 34, usdMax: 46, dLat: 0.002, dLng: 0.001, totalInr: 9600,
        pageText: 'Homestay. Free parking. Breakfast included. Ground floor rooms.'),
    WorldHotel('g100001-d2', 'Tea Valley Resort', rating: 4.3, reviews: 2100, usdMin: 95, usdMax: 130, dLat: 0.012, dLng: -0.006, totalInr: 24000, type: 'Resort',
        pageText: 'Swimming pool, spa, restaurant, elevator. Wheelchair accessible rooms available.'),
    WorldHotel('g100001-d3', 'Budget Inn Munnar', rating: 3.4, reviews: 150, usdMin: 14, usdMax: 22, dLat: -0.003, dLng: 0.006, totalInr: 4200,
        pageText: 'Basic rooms. Stairs only to reach the rooms. Free wifi.'),
    WorldHotel('g100001-d4', 'Misty Hills Cottages', rating: 4.5, reviews: 640, usdMin: 45, usdMax: 60, dLat: 0.02, dLng: 0.01, totalInr: 12500, type: 'Cottage',
        pageText: 'Eco-friendly solar-powered cottages, organic breakfast, parking.'),
    WorldHotel('g100001-d5', 'Grand Plaza Munnar', rating: 4.0, reviews: 1800, usdMin: 60, usdMax: 80, dLat: -0.008, dLng: -0.004, totalInr: 16800,
        pageText: 'Lift to all floors. Not wheelchair accessible in the older wing. Restaurant, bar/lounge.'),
    WorldHotel('g100001-d6', 'Cardamom Retreat', rating: 4.4, reviews: 390, usdMin: 50, usdMax: 70, dLat: 0.015, dLng: 0.02, totalInr: 14400,
        pageText: 'Ramp at the front entrance, accessible bathroom, hearing loop at reception.'),
  ];

  final List<WorldHotel> hotels;
  final List<Map<String, Object?>> geoapifyPlaces;
  final List<Map<String, Object?>> overpassPlaces;
  final String locationKey;
  bool xoteloDown;
  bool geoapifyDown;
  bool overpassDown;
  bool tripAdvisorDown;
  bool ratesDown;

  /// Xotelo heatmap for the query's check-out date, or null for none.
  Map<String, List<String>>? heatmap;

  /// Requests seen, by "host path".
  final Map<String, int> hits = {};

  int hitsFor(String fragment) => hits.entries.where((e) => e.key.contains(fragment)).fold(0, (a, e) => a + e.value);

  http.Client get client => MockClient((r) async {
    final tag = '${r.url.host}${r.url.path}';
    hits[tag] = (hits[tag] ?? 0) + 1;
    try {
      return _route(r);
    } catch (e) {
      return http.Response('{"error":"world error $e"}', 500);
    }
  });

  static http.Response _json(Object o, [int status = 200]) => http.Response(
    jsonEncode(o),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response _route(http.Request r) {
    final host = r.url.host;
    final path = r.url.path;

    if (host == 'data.xotelo.com') {
      if (xoteloDown) return http.Response('down', 503);
      if (path.endsWith('/list')) {
        final key = r.url.queryParameters['location_key'];
        if (key != locationKey) {
          // A different (wrong) place: Bengaluru hotels, as in the real mix-up.
          return _json({
            'error': null,
            'result': {
              'total_count': 500,
              'list': [
                for (var i = 0; i < 10; i++)
                  {
                    'name': 'Bengaluru Hotel $i',
                    'key': '$key-d$i',
                    'accommodation_type': 'Hotel',
                    'review_summary': {'rating': 4.0, 'count': 100},
                    'price_ranges': {'minimum': 40, 'maximum': 70},
                    'geo': {'latitude': bengaluruCenter.latitude + i * 0.01, 'longitude': bengaluruCenter.longitude},
                  },
              ],
            },
          });
        }
        return _json({
          'error': null,
          'result': {
            'total_count': hotels.length,
            'list': [
              for (final h in hotels)
                {
                  'name': h.name,
                  'key': h.key,
                  'accommodation_type': h.type,
                  'url': 'https://www.tripadvisor.com/Hotel_Review-${h.key}-Reviews-${h.name.replaceAll(' ', '_')}-Munnar.html',
                  'review_summary': {'rating': h.rating, 'count': h.reviews},
                  'price_ranges': {'minimum': h.usdMin, 'maximum': h.usdMax},
                  'geo': {'latitude': h.where.latitude, 'longitude': h.where.longitude},
                  'merchandising_labels': <String>[],
                },
            ],
          },
        });
      }
      if (path.endsWith('/rates')) {
        if (ratesDown) return _json({'error': {'status_code': 500, 'message': 'boom'}, 'result': null});
        final key = r.url.queryParameters['hotel_key'];
        final h = hotels.where((x) => x.key == key).firstOrNull;
        if (h == null) return _json({'error': null, 'result': {'rates': <Object>[]}});
        return _json({
          'error': null,
          'result': {
            'chk_in': r.url.queryParameters['chk_in'],
            'chk_out': r.url.queryParameters['chk_out'],
            'currency': 'INR',
            'rates': [
              {'code': 'BookingCom', 'name': 'Booking.com', 'rate': (h.totalInr * 1.1).round(), 'tax': null},
              {'code': 'Agoda', 'name': 'Agoda.com', 'rate': h.totalInr, 'tax': null},
            ],
          },
        });
      }
      if (path.endsWith('/heatmap')) {
        final hm = heatmap;
        if (hm == null) return _json({'error': {'status_code': 400, 'message': 'no data'}, 'result': null});
        return _json({
          'error': null,
          'result': {
            'chk_out': r.url.queryParameters['chk_out'],
            'heatmap': {
              'average_price_days': hm['average'] ?? <String>[],
              'cheap_price_days': hm['cheap'] ?? <String>[],
              'high_price_days': hm['high'] ?? <String>[],
            },
          },
        });
      }
    }

    if (host == 'api.geoapify.com') {
      if (geoapifyDown) return http.Response('down', 500);
      if (path.contains('/v2/places')) {
        final wheelchairOnly = r.url.queryParameters['conditions'] == 'wheelchair';
        final places = wheelchairOnly
            ? geoapifyPlaces.where((p) => ((p['datasource'] as Map?)?['raw'] as Map?)?['wheelchair'] == 'yes').toList()
            : geoapifyPlaces;
        return _json({
          'features': [
            for (final p in places)
              {
                'type': 'Feature',
                'properties': {
                  'name': p['name'],
                  'formatted': '${p['name']}, Munnar',
                  'lat': p['lat'],
                  'lon': p['lon'],
                  'place_id': p['id'],
                  'categories': ['accommodation', 'accommodation.hotel'],
                  'datasource': p['datasource'] ?? {'raw': <String, Object>{}},
                },
              },
          ],
        });
      }
      if (path.contains('/geocode/search')) {
        final text = r.url.queryParameters['text'] ?? '';
        final p = geoapifyPlaces.where((x) => text.toLowerCase().contains('${x['name']}'.toLowerCase())).firstOrNull;
        return _json({
          'results': [
            if (p != null) {'formatted': p['name'], 'lat': p['lat'], 'lon': p['lon']},
          ],
        });
      }
    }

    if (host.contains('overpass')) {
      if (overpassDown) return http.Response('down', 504);
      final query = r.bodyFields['data'] ?? '';
      final byName = RegExp(r'"name"~"\^(.*?)\$",i').firstMatch(query)?.group(1);
      final matches = byName == null
          ? overpassPlaces
          : overpassPlaces.where((p) => (p['tags'] as Map)['name'].toString().toLowerCase().contains(byName.replaceAll(r'\\', '').toLowerCase())).toList();
      return _json({'elements': matches});
    }

    if (host == 'api.tavily.com') {
      if (path == '/search') {
        return _json({
          'results': [
            {
              'title': 'Munnar hotels',
              'url': 'https://www.tripadvisor.com/Hotels-$locationKey-Munnar-Hotels.html',
              'content': 'Best hotels in Munnar',
              'score': 0.9,
            },
          ],
        });
      }
      return http.Response('nope', 404);
    }

    if (host.contains('tripadvisor')) {
      if (tripAdvisorDown) return http.Response('blocked', 403);
      final h = hotels.where((x) => r.url.path.contains(x.key)).firstOrNull;
      if (h == null) return http.Response('not found', 404);
      return http.Response(
        '<html><head><title>${h.name} - TripAdvisor</title></head><body><h1>${h.name}</h1><h2>Amenities</h2><p>${h.pageText}</p></body></html>',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }

    return http.Response('unrouted ${r.url}', 404);
  }
}

/// Everything a [HotelFinder] needs, built around a [HotelWorld].
class FinderRig {
  FinderRig(this.world, {ScriptedLlm? llm, List<SearchResult>? searchResults, this.withGeoapify = true, this.webLoop = false})
    : llm = llm ?? ScriptedLlm() {
    final cache = MemoryCache();
    final client = world.client;
    final xotelo = XoteloClient(client: client, cache: cache);
    final geoapify = withGeoapify ? GeoapifyClient(apiKey: 'K', client: client, cache: cache) : null;
    final overpass = OverpassClient(client: client, cache: cache);
    budget = ToolBudget();
    final providers = <SearchProvider>[
      ScriptedSearchProvider('T', results: searchResults ?? [result('Munnar hotels', 'https://www.tripadvisor.com/Hotels-g100001-Munnar-Hotels.html')]),
    ];
    search = WebSearchTool(providers: providers, budget: budget, cache: cache);
    fetch = FetchPageTool(budget: budget, client: client, cache: cache);
    registry = ToolRegistry()..register(search)..register(fetch);
    resolver = LocationKeyResolver(
      xotelo: xotelo,
      geocode: (_) async => munnarCenter,
      search: search,
      cache: cache,
    );
    finder = HotelFinder(
      resolver: resolver,
      xotelo: xotelo,
      overpass: overpass,
      geoapify: geoapify,
      tools: webLoop ? registry : null,
      llm: webLoop ? this.llm : null,
      estimator: AiEstimator(this.llm),
      fetchPage: fetch,
    );
  }

  final HotelWorld world;
  final ScriptedLlm llm;
  final bool withGeoapify;
  final bool webLoop;
  late final ToolBudget budget;
  late final WebSearchTool search;
  late final FetchPageTool fetch;
  late final ToolRegistry registry;
  late final LocationKeyResolver resolver;
  late final HotelFinder finder;
}

HotelQuery munnarQuery({
  Set<AccessibilityNeed> needs = const {},
  int? cap,
  int rooms = 1,
  int adults = 2,
  int nights = 3,
  double radiusKm = 10,
  bool preferEco = false,
}) => HotelQuery(
  destination: 'Munnar',
  center: munnarCenter,
  checkIn: DateTime(2026, 10, 10),
  checkOut: DateTime(2026, 10, 10 + nights),
  rooms: rooms,
  adults: adults,
  needs: needs,
  nightlyCapInr: cap,
  radiusKm: radiusKm,
  preferEco: preferEco,
);

/// Geoapify/OSM places for the tests.
Map<String, Object?> geoPlace(String id, String name, double dLat, double dLng, {Map<String, Object> tags = const {}}) => {
  'id': id,
  'name': name,
  'lat': munnarCenter.latitude + dLat,
  'lon': munnarCenter.longitude + dLng,
  'datasource': {'raw': tags},
};

Map<String, Object?> osmNode(int id, String name, double dLat, double dLng, {Map<String, Object> tags = const {}}) => {
  'type': 'node',
  'id': id,
  'lat': munnarCenter.latitude + dLat,
  'lon': munnarCenter.longitude + dLng,
  'tags': {'name': name, 'tourism': 'hotel', ...tags},
};
