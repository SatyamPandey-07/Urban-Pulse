import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbanpulse/services/data/data_cache.dart';
import 'package:urbanpulse/services/data/forecast_client.dart';
import 'package:urbanpulse/services/data/geoapify_client.dart';
import 'package:urbanpulse/services/data/http_util.dart';
import 'package:urbanpulse/services/data/overpass_client.dart';
import 'package:urbanpulse/services/data/wikipedia_client.dart';
import 'package:urbanpulse/services/data/xotelo_client.dart';

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status);

/// Real Xotelo `/list` output recorded from data.xotelo.com (Bangkok).
const xoteloListFixture = {
  'error': null,
  'result': {
    'total_count': 6742,
    'limit': 2,
    'offset': 0,
    'list': [
      {
        'name': 'Eastin Grand Hotel Phayathai',
        'key': 'g293916-d25794929',
        'accommodation_type': 'Hotel',
        'url': 'https://www.tripadvisor.com/Hotel_Review-g293916-d25794929-Reviews-Eastin_Grand_Hotel_Phayathai-Bangkok.html',
        'review_summary': {'rating': 4.9, 'count': 1541},
        'price_ranges': {'maximum': 228, 'minimum': 158},
        'geo': {'latitude': 13.756689, 'longitude': 100.533066},
        'image': 'https://example.com/pool.jpg',
        'mentions': [],
        'merchandising_labels': ['All inclusive'],
      },
      {
        'name': 'Baiyoke Sky Hotel',
        'key': 'g293916-d305228',
        'accommodation_type': 'Hotel',
        'review_summary': {'rating': 3.6, 'count': 6844},
        'price_ranges': {'maximum': 95, 'minimum': 58},
        'geo': {'latitude': 13.754147, 'longitude': 100.54038},
        'merchandising_labels': [],
      },
      {'name': 'No key so skipped'},
    ],
  },
  'timestamp': 1790429300387,
};

void main() {
  group('http helpers', () {
    test('httpGet never throws and reports failures as values', () async {
      final boom = MockClient((_) async => throw Exception('socket'));
      final o = await httpGet(boom, Uri.parse('https://example.com'));
      expect(o.ok, isFalse);
      expect(o.error, contains('network'));
    });

    test('sends an identifying User-Agent', () async {
      String? ua;
      final c = MockClient((r) async {
        ua = r.headers['User-Agent'];
        return http.Response('{}', 200);
      });
      await httpGet(c, Uri.parse('https://example.com'));
      expect(ua, kUserAgent);
    });

    test('haversine: Pune to Mumbai is about 120 km', () {
      expect(haversineKm(18.52, 73.86, 19.076, 72.878), closeTo(120, 8));
    });
  });

  group('cache', () {
    test('memory cache expires', () async {
      var now = DateTime(2026);
      final c = MemoryCache(now: () => now);
      await c.put('k', 'v', ttl: const Duration(hours: 1));
      expect(await c.get('k'), 'v');
      now = now.add(const Duration(hours: 2));
      expect(await c.get('k'), isNull);
    });

    test('prefs cache persists, expires and caps its size', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026);
      final c = PrefsCache(prefs, now: () => now, maxEntries: 3);

      await c.put('a', '1', ttl: const Duration(hours: 1));
      expect(await PrefsCache(prefs, now: () => now).get('a'), '1', reason: 'survives a new instance');
      now = now.add(const Duration(hours: 2));
      expect(await c.get('a'), isNull);

      for (var i = 0; i < 6; i++) {
        await c.put('k$i', '$i', ttl: Duration(hours: 10 + i));
      }
      final left = prefs.getKeys().where((k) => k.startsWith('yatri.cache.')).length;
      expect(left, 3);
      expect(await c.get('k5'), '5', reason: 'the longest-lived entries are kept');
    });

    test('rememberJson caches successes but never failures', () async {
      final c = MemoryCache();
      var calls = 0;
      Future<Object?> fetch() async {
        calls++;
        return calls == 1 ? null : {'ok': true};
      }

      expect(await c.rememberJson('x', fetch), isNull);
      expect(await c.rememberJson('x', fetch), {'ok': true});
      expect(await c.rememberJson('x', fetch), {'ok': true});
      expect(calls, 2, reason: 'the failure was not cached, the success was');
    });
  });

  group('Xotelo', () {
    test('parses a real /list response', () {
      final list = XoteloClient.parseList(xoteloListFixture['result'])!;
      expect(list.total, 6742);
      expect(list.hotels, hasLength(2), reason: 'the entry with no key is dropped');
      final h = list.hotels.first;
      expect(h.name, 'Eastin Grand Hotel Phayathai');
      expect(h.key, 'g293916-d25794929');
      expect((h.rating, h.reviewCount), (4.9, 1541));
      expect((h.lat, h.lng), (13.756689, 100.533066));
      expect(h.labels, ['All inclusive']);
      expect((h.priceMinUsd, h.priceMaxUsd), (158, 228));
      expect(h.approxNightlyInr, (Fx.inr(158), Fx.inr(228)));
    });

    test('list is fetched once and then served from cache', () async {
      var calls = 0;
      Uri? seen;
      final client = XoteloClient(
        client: MockClient((r) async {
          calls++;
          seen = r.url;
          return json(xoteloListFixture);
        }),
      );
      final a = await client.list('g293916', limit: 2);
      final b = await client.list('g293916', limit: 2);
      expect(a!.hotels, hasLength(2));
      expect(b!.hotels, hasLength(2));
      expect(calls, 1);
      expect(seen!.queryParameters['location_key'], 'g293916');
    });

    test('an API error is null and is not cached', () async {
      var calls = 0;
      final client = XoteloClient(
        client: MockClient((r) async {
          calls++;
          return json({'error': {'status_code': 400, 'message': 'currency is invalid'}, 'result': null});
        }),
      );
      expect(await client.list('g1'), isNull);
      expect(await client.list('g1'), isNull);
      expect(calls, 2);
    });

    test('parses real per-OTA rates and picks the cheapest', () {
      final rates = XoteloClient.parseRates({
        'chk_in': '2026-10-10',
        'chk_out': '2026-10-12',
        'currency': 'INR',
        'rates': [
          {'code': 'BookingCom', 'name': 'Booking.com', 'rate': 9028, 'tax': null},
          {'code': 'Agoda', 'name': 'Agoda.com', 'rate': 7319, 'tax': null},
          {'code': 'Broken', 'name': 'no rate'},
        ],
      })!;
      expect(rates.rates, hasLength(2));
      expect(rates.cheapest!.name, 'Agoda.com');
      expect(rates.cheapest!.rate, 7319);
      expect(rates.currency, 'INR');
    });

    test('rates and heatmap use the documented parameters', () async {
      final urls = <Uri>[];
      final client = XoteloClient(
        client: MockClient((r) async {
          urls.add(r.url);
          if (r.url.path.endsWith('/rates')) {
            return json({'error': null, 'result': {'chk_in': 'a', 'chk_out': 'b', 'currency': 'INR', 'rates': []}});
          }
          return json({'error': null, 'result': {'chk_out': 'x', 'heatmap': {'average_price_days': ['2026-10-01'], 'cheap_price_days': ['2026-10-02'], 'high_price_days': ['2026-10-03']}}});
        }),
      );
      await client.rates('g1-d2', checkIn: '2026-10-10', checkOut: '2026-10-12', rooms: 2, adults: 4);
      final hm = await client.heatmap('g1-d2', checkOut: '2026-10-12');
      final q = urls.first.queryParameters;
      expect((q['hotel_key'], q['chk_in'], q['chk_out'], q['rooms'], q['adults'], q['currency']), ('g1-d2', '2026-10-10', '2026-10-12', '2', '4', 'INR'));
      expect(hm!.bandFor('2026-10-02'), 'cheap');
      expect(hm.bandFor('2026-10-03'), 'high');
      expect(hm.bandFor('2026-10-01'), 'average');
      expect(hm.bandFor('2030-01-01'), isNull);
    });

    test('search needs a RapidAPI key and sends the right headers', () async {
      expect(await XoteloClient(client: MockClient((_) async => json({}))).search('Munnar'), isNull);

      Map<String, String>? headers;
      final client = XoteloClient(
        rapidApiKey: 'secret',
        client: MockClient((r) async {
          headers = r.headers;
          return json({
            'error': null,
            'result': {
              'list': [
                {'name': 'Munnar', 'location_key': 'g297628x', 'place_type': 'City', 'geo': {'latitude': 10.09, 'longitude': 77.06}},
                {'name': 'Hotel X', 'hotel_key': 'g1-d2'},
                {'name': 'no key'},
              ],
            },
          });
        }),
      );
      final places = await client.search('Munnar');
      expect(headers!['x-rapidapi-key'], 'secret');
      expect(headers!['x-rapidapi-host'], XoteloClient.rapidApiHost);
      expect(places, hasLength(2));
      expect(places!.first.key, 'g297628x');
      expect(places.first.lat, 10.09);
      expect(places.last.isHotel, isTrue);
    });
  });

  group('Geoapify', () {
    final feature = {
      'type': 'Feature',
      'properties': {
        'name': 'Hotel Sunrise',
        'formatted': 'Hotel Sunrise, Munnar, Kerala, India',
        'lat': 10.09,
        'lon': 77.06,
        'categories': ['accommodation', 'accommodation.hotel'],
        'place_id': 'abc123',
        'website': 'https://sunrise.example',
        'contact': {'phone': '+91 484 1234'},
        'opening_hours': '24/7',
        'distance': 420,
        'datasource': {
          'sourcename': 'openstreetmap',
          'raw': {'wheelchair': 'limited', 'tactile_paving': 'yes', 'stars': '3'},
        },
      },
    };

    test('parses a place with its raw OSM accessibility tags', () {
      final p = GeoPlace.fromFeature(feature)!;
      expect((p.name, p.lat, p.lon, p.id), ('Hotel Sunrise', 10.09, 77.06, 'abc123'));
      expect(p.wheelchair, 'limited');
      expect(p.tags['tactile_paving'], 'yes');
      expect(p.phone, '+91 484 1234');
      expect(p.distanceM, 420);
      expect(p.categories, contains('accommodation.hotel'));
    });

    test('unnamed or coordinate-less features are dropped', () {
      expect(GeoapifyClient.parseFeatures([feature, {'properties': {'lat': 1, 'lon': 2}}, 'junk']), hasLength(1));
      expect(GeoapifyClient.parseFeatures('nope'), isNull);
    });

    test('without a key it does nothing', () async {
      final c = GeoapifyClient(apiKey: '', client: MockClient((_) async => throw StateError('must not call')));
      expect(await c.places(categories: GeoapifyClient.hotelCategories, lat: 1, lon: 2), isNull);
      expect(await c.geocode('Munnar'), isNull);
    });

    test('places builds the circle filter, bias and wheelchair condition', () async {
      Uri? url;
      final c = GeoapifyClient(
        apiKey: 'K',
        client: MockClient((r) async {
          url = r.url;
          return json({'features': [feature]});
        }),
      );
      final r = await c.places(
        categories: GeoapifyClient.hotelCategories,
        lat: 10.09,
        lon: 77.06,
        radiusM: 5000,
        wheelchairOnly: true,
      );
      expect(r, hasLength(1));
      expect(url!.queryParameters['filter'], 'circle:77.06,10.09,5000');
      expect(url!.queryParameters['bias'], 'proximity:77.06,10.09');
      expect(url!.queryParameters['conditions'], 'wheelchair');
      expect(url!.queryParameters['apiKey'], 'K');
    });

    test('geocode returns ranked candidates for did-you-mean', () async {
      final c = GeoapifyClient(
        apiKey: 'K',
        client: MockClient((_) async => json({
          'results': [
            {'formatted': 'Munnar, Kerala, India', 'lat': 10.0889, 'lon': 77.0595, 'city': 'Munnar', 'state': 'Kerala', 'country': 'India', 'result_type': 'city', 'rank': {'confidence': 0.9}},
            {'formatted': 'no coords'},
          ],
        })),
      );
      final r = (await c.geocode('munar'))!;
      expect(r, hasLength(1));
      expect((r.first.city, r.first.state, r.first.confidence), ('Munnar', 'Kerala', 0.9));
    });
  });

  group('Overpass', () {
    test('escapes user text for the regex inside a query', () {
      expect(OverpassClient.escapeRegex('Taj Mahal'), 'Taj Mahal');
      expect(OverpassClient.escapeRegex('A.B (old)'), r'A\\.B \\(old\\)');
      expect(OverpassClient.escapeRegex('say "hi"'), r'say \"hi\"');
      expect(OverpassClient.escapeRegex('a\nb'), 'a b');
    });

    test('builds a bounded query that returns centres and tags', () {
      final q = OverpassClient.buildQuery('(nwr["tourism"="hotel"](around:1000,1,2););', 50);
      expect(q, startsWith('[out:json][timeout:20];'));
      expect(q, endsWith('out center tags 50;'));
    });

    test('parses nodes and ways (with centres), dropping unnamed ones', () {
      final places = OverpassClient.parse([
        {'type': 'node', 'id': 1, 'lat': 10.1, 'lon': 77.1, 'tags': {'name': 'Fort', 'wheelchair': 'yes', 'opening_hours': 'Mo-Su 09:00-17:00'}},
        {'type': 'way', 'id': 2, 'center': {'lat': 10.2, 'lon': 77.2}, 'tags': {'name': 'Palace', 'website': 'https://p.example'}},
        {'type': 'node', 'id': 3, 'lat': 1, 'lon': 2, 'tags': {'tourism': 'hotel'}},
        {'type': 'node', 'id': 4, 'tags': {'name': 'No position'}},
      ])!;
      expect(places.map((p) => p.name), ['Fort', 'Palace']);
      expect(places.first.id, 'node/1');
      expect(places.first.wheelchair, 'yes');
      expect(places.first.openingHours, 'Mo-Su 09:00-17:00');
      expect((places.last.lat, places.last.lon), (10.2, 77.2));
    });

    test('falls back to the mirror when the first server is busy', () async {
      final hosts = <String>[];
      final c = OverpassClient(
        client: MockClient((r) async {
          hosts.add(r.url.host);
          if (hosts.length == 1) return http.Response('Too Many Requests', 429);
          return json({'elements': [{'type': 'node', 'id': 1, 'lat': 1, 'lon': 2, 'tags': {'name': 'A'}}]});
        }),
      );
      final r = await c.hotelsAround(10, 77);
      expect(r, hasLength(1));
      expect(hosts, ['overpass-api.de', 'overpass.kumi.systems']);
    });

    test('identical concurrent requests share one call, and repeats hit the cache', () async {
      var calls = 0;
      final c = OverpassClient(
        client: MockClient((r) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return json({'elements': [{'type': 'node', 'id': 1, 'lat': 1, 'lon': 2, 'tags': {'name': 'A'}}]});
        }),
      );
      final results = await Future.wait([c.attractionsAround(10, 77), c.attractionsAround(10, 77)]);
      expect(results.every((r) => r!.length == 1), isTrue);
      expect(calls, 1);
      await c.attractionsAround(10, 77);
      expect(calls, 1);
    });

    test('total failure is null, not an exception', () async {
      final c = OverpassClient(client: MockClient((_) async => throw Exception('down')));
      expect(await c.hotelsAround(1, 2), isNull);
    });
  });

  group('Wikipedia', () {
    test('parses geosearch and search results', () async {
      final c = WikipediaClient(
        client: MockClient((r) async {
          if (r.url.queryParameters['list'] == 'geosearch') {
            return json({'query': {'geosearch': [{'pageid': 1, 'title': 'Eravikulam National Park', 'lat': 10.2, 'lon': 77.0, 'dist': 1200.5}]}});
          }
          return json({'query': {'search': [{'pageid': 2, 'title': 'Munnar', 'snippet': 'hill <span class="x">station</span> in Kerala'}]}});
        }),
      );
      final near = (await c.geosearch(10.09, 77.06))!;
      expect((near.first.title, near.first.distanceM), ('Eravikulam National Park', 1200.5));
      final found = (await c.search('Munnar'))!;
      expect(found.first.extract, 'hill station in Kerala');
    });

    test('clamps the radius to Wikipedia’s maximum', () async {
      Uri? url;
      final c = WikipediaClient(client: MockClient((r) async {
        url = r.url;
        return json({'query': {'geosearch': []}});
      }));
      await c.geosearch(1, 2, radiusM: 50000);
      expect(url!.queryParameters['gsradius'], '10000');
    });

    test('summary carries coordinates and a page URL', () async {
      final c = WikipediaClient(client: MockClient((_) async => json({
        'title': 'Munnar',
        'extract': 'Munnar is a town in Kerala.',
        'coordinates': {'lat': 10.0889, 'lon': 77.0595},
        'content_urls': {'desktop': {'page': 'https://en.wikipedia.org/wiki/Munnar'}},
      })));
      final s = (await c.summary('Munnar'))!;
      expect((s.lat, s.url), (10.0889, 'https://en.wikipedia.org/wiki/Munnar'));
    });
  });

  group('forecast', () {
    final daily = {
      'time': ['2026-10-10', '2026-10-11', '2026-10-12'],
      'temperature_2m_max': [31.2, 29, 38.5],
      'temperature_2m_min': [20, 19, 24],
      'precipitation_sum': [0.0, 22.4, 1],
      'precipitation_probability_max': [10, 90, 20],
      'weathercode': [1, 63, 2],
    };

    test('parses days and classifies rain and heat', () {
      final days = ForecastClient.parse(daily);
      expect(days, hasLength(3));
      expect(days[0].isRainy, isFalse);
      expect(days[1].isRainy, isTrue);
      expect(days[2].isHot, isTrue);
      expect(days[1].summary, contains('90% rain'));
    });

    test('dates beyond the 16-day horizon return nothing without calling out', () async {
      final c = ForecastClient(client: MockClient((_) async => throw StateError('must not call')));
      final r = await c.daily(10, 77, DateTime(2026, 12, 1), DateTime(2026, 12, 5), today: DateTime(2026, 10, 1));
      expect(r, isEmpty);
    });

    test('a trip that runs past the horizon only asks for the covered days', () async {
      Uri? url;
      final c = ForecastClient(client: MockClient((r) async {
        url = r.url;
        return json({'daily': daily});
      }));
      await c.daily(10, 77, DateTime(2026, 10, 14), DateTime(2026, 11, 20), today: DateTime(2026, 10, 1));
      expect(url!.queryParameters['start_date'], '2026-10-14');
      expect(url!.queryParameters['end_date'], '2026-10-16');
    });

    test('a failed call is an empty list', () async {
      final c = ForecastClient(client: MockClient((_) async => http.Response('nope', 500)));
      expect(await c.daily(10, 77, DateTime(2026, 10, 3), DateTime(2026, 10, 4), today: DateTime(2026, 10, 1)), isEmpty);
    });
  });
}
