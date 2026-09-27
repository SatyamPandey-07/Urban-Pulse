import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/agents/tools/agent_tool.dart';
import 'package:urbanpulse/agents/tools/web_search_tool.dart';
import 'package:urbanpulse/services/data/data_cache.dart';
import 'package:urbanpulse/services/data/location_key_resolver.dart';
import 'package:urbanpulse/services/data/xotelo_client.dart';

import '../agents/scripted.dart';

const munnar = LatLng(10.0889, 77.0595);
const bengaluru = LatLng(12.9716, 77.5946);

/// Hotels of one TripAdvisor location, as Xotelo's /list returns them.
Map<String, dynamic> hotelsAround(LatLng c, int n, {String prefix = 'g1'}) => {
  'error': null,
  'result': {
    'total_count': 100,
    'list': [
      for (var i = 0; i < n; i++)
        {
          'name': 'Hotel $i',
          'key': '$prefix-d$i',
          'accommodation_type': 'Hotel',
          'review_summary': {'rating': 4.0, 'count': 100},
          'price_ranges': {'minimum': 30, 'maximum': 60},
          'geo': {'latitude': c.latitude + i * 0.005, 'longitude': c.longitude + i * 0.005},
        },
    ],
  },
};

/// Xotelo serving a different set of hotels per location key.
XoteloClient scriptedXotelo(Map<String, LatLng> places, {int hotels = 10, List<String>? calls, String? rapidKey, Map<String, dynamic> Function(String key)? searchResult}) {
  return XoteloClient(
    rapidApiKey: rapidKey,
    cache: MemoryCache(),
    client: MockClient((r) async {
      if (r.url.path.endsWith('/list')) {
        final key = r.url.queryParameters['location_key']!;
        calls?.add(key);
        final c = places[key];
        if (c == null) return http.Response(jsonEncode({'error': {'status_code': 404, 'message': 'unknown location'}, 'result': null}), 200);
        return http.Response(jsonEncode(hotelsAround(c, hotels, prefix: key)), 200);
      }
      if (r.url.path.endsWith('/search') && searchResult != null) {
        return http.Response(jsonEncode(searchResult(r.url.queryParameters['query']!)), 200);
      }
      return http.Response('{}', 404);
    }),
  );
}

LocationKeyResolver resolver(
  XoteloClient xotelo, {
  LatLng? geocoded = munnar,
  ScriptedLlm? llm,
  WebSearchTool? search,
  DataCache? cache,
}) => LocationKeyResolver(
  xotelo: xotelo,
  geocode: (place) async => geocoded,
  llm: llm,
  search: search,
  cache: cache,
);

WebSearchTool webWith(List<SearchResult> results) =>
    WebSearchTool(providers: [ScriptedSearchProvider('T', results: results)], budget: ToolBudget());

void main() {
  group('extracting keys from text', () {
    test('reads TripAdvisor URLs', () {
      expect(
        LocationKeyResolver.extractKeys('https://www.tripadvisor.com/Hotels-g297628-Munnar_Idukki_District_Kerala-Hotels.html'),
        ['g297628'],
      );
      expect(
        LocationKeyResolver.extractKeys('https://www.tripadvisor.com/Hotel_Review-g293916-d305228-Reviews-Baiyoke_Sky-Bangkok.html'),
        ['g293916'],
      );
      expect(LocationKeyResolver.extractKeys('see g12345 and also g98765, g12345 again'), ['g12345', 'g98765']);
    });

    test('ignores things that only look like keys', () {
      expect(LocationKeyResolver.extractKeys('https://example.com/page-tag12'), isEmpty);
      expect(LocationKeyResolver.extractKeys('good luck'), isEmpty);
      expect(LocationKeyResolver.extractKeys('g12'), isEmpty, reason: 'too short');
      expect(LocationKeyResolver.extractKeys(''), isEmpty);
    });
  });

  group('validation', () {
    test('a key whose hotels are near the destination is accepted', () async {
      final r = await resolver(
        scriptedXotelo({'g100': munnar}),
        search: webWith([result('Munnar hotels', 'https://www.tripadvisor.com/Hotels-g100-Munnar-Hotels.html')]),
      ).resolve('Munnar');
      expect(r!.key, 'g100');
      expect(r.source, 'web search');
      expect(r.checkedHotels, 10);
      expect(r.nearHotels, 10);
      expect(r.center, munnar);
    });

    test('the Munnar-vs-Bengaluru mistake is caught: a wrong key is rejected', () async {
      // The web page pointed at a key that actually lists Bengaluru hotels.
      final r = await resolver(
        scriptedXotelo({'g297628': bengaluru}),
        search: webWith([result('Munnar', 'https://www.tripadvisor.com/Hotels-g297628-Munnar-Hotels.html')]),
      ).resolve('Munnar');
      expect(r, isNull);
    });

    test('the first VALID candidate wins, even if an earlier one is wrong', () async {
      final r = await resolver(
        scriptedXotelo({'g111': bengaluru, 'g222': munnar}),
        search: webWith([
          result('wrong first', 'https://www.tripadvisor.com/Hotels-g111-Somewhere-Hotels.html'),
          result('right second', 'https://www.tripadvisor.com/Hotels-g222-Munnar-Hotels.html'),
        ]),
      ).resolve('Munnar');
      expect(r!.key, 'g222');
    });

    test('too few hotels with coordinates means the key is not believed', () async {
      final r = await resolver(
        scriptedXotelo({'g100': munnar}, hotels: 2),
        search: webWith([result('Munnar', 'https://www.tripadvisor.com/Hotels-g100-Munnar-Hotels.html')]),
      ).resolve('Munnar');
      expect(r, isNull);
    });

    test('only TripAdvisor URLs are trusted for keys', () async {
      final calls = <String>[];
      final r = await resolver(
        scriptedXotelo({'g100': munnar}, calls: calls),
        search: webWith([result('Some blog', 'https://blog.example/munnar-g100-guide')]),
      ).resolve('Munnar');
      expect(r, isNull);
      expect(calls, isEmpty, reason: 'nothing to validate');
    });
  });

  group('sources of candidates', () {
    test('Xotelo search is used when a RapidAPI key is set', () async {
      final r = await resolver(
        scriptedXotelo(
          {'g100': munnar},
          rapidKey: 'k',
          searchResult: (q) => {
            'error': null,
            'result': {
              'list': [
                {'name': 'Some hotel', 'hotel_key': 'g100-d5'},
                {'name': 'Munnar', 'location_key': 'g100', 'place_type': 'City'},
              ],
            },
          },
        ),
      ).resolve('Munnar');
      expect(r!.key, 'g100');
      expect(r.source, 'xotelo search');
    });

    test('the model is only asked when the other sources find nothing valid', () async {
      final llm = ScriptedLlm(['{"keys": ["g100", "bogus", "g999999"]}']);
      final r = await resolver(scriptedXotelo({'g100': munnar}), llm: llm).resolve('Munnar');
      expect(r!.key, 'g100');
      expect(r.source, 'ai guess');
      expect(llm.asked, hasLength(1));

      // With a valid web candidate the model is never consulted.
      final llm2 = ScriptedLlm();
      await resolver(
        scriptedXotelo({'g100': munnar}),
        llm: llm2,
        search: webWith([result('Munnar', 'https://www.tripadvisor.com/Hotels-g100-Munnar-Hotels.html')]),
      ).resolve('Munnar');
      expect(llm2.asked, isEmpty);
    });

    test('a hallucinated key is validated like any other', () async {
      final llm = ScriptedLlm(['{"keys": ["g297628"]}']);
      final r = await resolver(scriptedXotelo({'g297628': bengaluru}), llm: llm).resolve('Munnar');
      expect(r, isNull);
    });

    test('junk from the model is ignored', () async {
      for (final junk in ['not json', '{"keys": "g100"}', '{"keys": [1, null, {"a": 1}]}', '{}']) {
        final r = await resolver(scriptedXotelo({'g100': munnar}), llm: ScriptedLlm([junk])).resolve('Munnar');
        expect(r, isNull, reason: junk);
      }
    });
  });

  group('caching and edge cases', () {
    test('a resolved key is cached and not re-validated', () async {
      final calls = <String>[];
      final cache = MemoryCache();
      final res = resolver(
        scriptedXotelo({'g100': munnar}, calls: calls),
        search: webWith([result('Munnar', 'https://www.tripadvisor.com/Hotels-g100-Munnar-Hotels.html')]),
        cache: cache,
      );
      final first = await res.resolve('Munnar');
      final callsAfterFirst = calls.length;
      final second = await res.resolve('  munnar ');
      expect(second!.key, first!.key);
      expect(second.source, 'cache');
      expect(calls.length, callsAfterFirst);
    });

    test('a failure is remembered briefly so credits are not spent again', () async {
      var searches = 0;
      final tool = WebSearchTool(
        providers: [ScriptedSearchProviderCounting(() => searches++)],
        budget: ToolBudget(),
      );
      final res = resolver(scriptedXotelo(const {}), search: tool);
      expect(await res.resolve('Atlantis'), isNull);
      final before = searches;
      expect(await res.resolve('Atlantis'), isNull);
      expect(searches, before);
    });

    test('an unknown place or blank name resolves to nothing without any calls', () async {
      final calls = <String>[];
      final res = resolver(scriptedXotelo({'g100': munnar}, calls: calls), geocoded: null);
      expect(await res.resolve('Nowhereville'), isNull);
      expect(await res.resolve('   '), isNull);
      expect(calls, isEmpty);
    });

    test('a supplied centre is used instead of geocoding', () async {
      var geocoded = false;
      final res = LocationKeyResolver(
        xotelo: scriptedXotelo({'g100': munnar}),
        geocode: (_) async {
          geocoded = true;
          return null;
        },
        search: webWith([result('Munnar', 'https://www.tripadvisor.com/Hotels-g100-Munnar-Hotels.html')]),
      );
      expect((await res.resolve('Munnar', center: munnar))!.key, 'g100');
      expect(geocoded, isFalse);
    });

    test('the resolved location round-trips through JSON', () {
      const r = ResolvedLocation(key: 'g1', center: munnar, source: 'web search', checkedHotels: 9, nearHotels: 8);
      final copy = ResolvedLocation.fromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect((copy.key, copy.center, copy.nearHotels), ('g1', munnar, 8));
      expect(ResolvedLocation.fromJson('nope'), isNull);
      expect(ResolvedLocation.fromJson({'key': 'g1'}), isNull);
    });
  });
}

/// A provider that counts its calls and never has results.
class ScriptedSearchProviderCounting extends ScriptedSearchProvider {
  ScriptedSearchProviderCounting(this.onCall) : super('T', results: null);

  final void Function() onCall;

  @override
  Future<List<SearchResult>?> search(String query, {int maxResults = 6}) {
    onCall();
    return super.search(query, maxResults: maxResults);
  }
}
