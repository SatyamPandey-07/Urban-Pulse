import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:urbanpulse/agents/runtime/agent_kind.dart';
import 'package:urbanpulse/agents/tools/agent_tool.dart';
import 'package:urbanpulse/agents/tools/fetch_page_tool.dart';
import 'package:urbanpulse/agents/tools/tool_loop.dart';
import 'package:urbanpulse/agents/tools/web_search_tool.dart';
import 'package:urbanpulse/services/data/data_cache.dart';
import 'package:urbanpulse/services/data/wikipedia_client.dart';
import 'package:urbanpulse/services/groq_api_client.dart';

import 'fakes.dart';

http.Response jsonResp(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  // Without a charset the body is Latin-1 encoded, which cannot hold "…".
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('web_search chain', () {
    test('uses the first provider that has results, and remembers them', () async {
      final tavily = FakeSearchProvider('Tavily', results: [result('Hotel A', 'https://a.example')]);
      final compound = FakeSearchProvider('Groq search', results: [result('B', 'https://b.example')]);
      final tool = WebSearchTool(providers: [tavily, compound], budget: ToolBudget());

      final out = await tool.run({'query': 'hotels in Munnar'});
      expect(out.ok, isTrue);
      expect((out.data as List<SearchResult>).single.title, 'Hotel A');
      expect(out.text, contains('Hotel A — https://a.example'));
      expect(tool.lastProvider, 'Tavily');
      expect(compound.calls, 0);

      // The same query again costs nothing.
      await tool.run({'query': 'Hotels in Munnar'});
      expect(tavily.calls, 1);
    });

    test('falls through the chain when a provider fails or is unavailable', () async {
      final tavily = FakeSearchProvider('Tavily', results: null);
      final off = FakeSearchProvider('Groq search', available: false, results: [result('x', 'https://x.example')]);
      final wiki = FakeSearchProvider('Wikipedia', results: [result('Munnar', 'https://en.wikipedia.org/wiki/Munnar')]);
      final tool = WebSearchTool(providers: [tavily, off, wiki], budget: ToolBudget());
      final out = await tool.run({'query': 'Munnar'});
      expect(out.ok, isTrue);
      expect(tool.lastProvider, 'Wikipedia');
      expect(off.calls, 0);
    });

    test('reports a clean failure and refunds the budget when nothing answers', () async {
      final budget = ToolBudget(maxSearches: 1);
      final tool = WebSearchTool(providers: [FakeSearchProvider('T', results: null)], budget: budget);
      final out = await tool.run({'query': 'zzzz'});
      expect(out.ok, isFalse);
      expect(budget.searchesUsed, 0);
    });

    test('once the budget is spent only the free Wikipedia provider still runs', () async {
      final tavily = FakeSearchProvider('Tavily', results: [result('paid', 'https://p.example')]);
      final wiki = WikipediaSearchProvider(
        WikipediaClient(client: MockClient((_) async => jsonResp({'query': {'search': [{'pageid': 1, 'title': 'Munnar', 'snippet': 'x'}]}}))),
      );
      final budget = ToolBudget(maxSearches: 1);
      final tool = WebSearchTool(providers: [tavily, wiki], budget: budget);

      await tool.run({'query': 'first query'});
      expect(tavily.calls, 1);
      final second = await tool.run({'query': 'a different query'});
      expect(tavily.calls, 1, reason: 'no budget left for the paid provider');
      expect(second.ok, isTrue);
      expect((second.data as List<SearchResult>).single.provider, 'Wikipedia');
    });

    test('bad arguments are rejected, and queries are sanitised and capped', () async {
      final tavily = FakeSearchProvider('T', results: [result('a', 'https://a.example')]);
      final tool = WebSearchTool(providers: [tavily], budget: ToolBudget(), maxQueryLength: 20);
      expect((await tool.run({})).ok, isFalse);
      expect((await tool.run({'query': '   '})).ok, isFalse);
      expect((await tool.run({'query': 42})).ok, isFalse);

      await tool.run({'query': 'hotels\n\tin   Munnar \u0000 with a very long tail that keeps going'});
      expect(tavily.queries.single.length, lessThanOrEqualTo(20));
      expect(tavily.queries.single, isNot(contains('\n')));
      expect(tavily.queries.single, startsWith('hotels in Munnar'));
    });

    test('max_results is clamped', () async {
      final tavily = FakeSearchProvider('T', results: [result('a', 'https://a.example')]);
      final tool = WebSearchTool(providers: [tavily], budget: ToolBudget());
      final out = await tool.run({'query': 'q', 'max_results': 999});
      expect(out.ok, isTrue);
    });
  });

  group('Tavily provider', () {
    test('parses results and sends the key as a bearer token', () async {
      String? auth;
      Map<String, dynamic>? body;
      final p = TavilySearchProvider(
        keys: ['tvly-1'],
        client: MockClient((r) async {
          auth = r.headers['Authorization'];
          body = jsonDecode(r.body) as Map<String, dynamic>;
          return jsonResp({
            'results': [
              {'title': 'Accessible hotels in Munnar', 'url': 'https://t.example/1', 'content': 'A list…', 'score': 0.9},
              {'title': 'no url'},
            ],
          });
        }),
      );
      final r = (await p.search('wheelchair hotels Munnar', maxResults: 4))!;
      expect(auth, 'Bearer tvly-1');
      expect((body!['query'], body!['search_depth'], body!['max_results']), ('wheelchair hotels Munnar', 'basic', 4));
      expect(r, hasLength(1));
      expect((r.first.provider, r.first.score), ('Tavily', 0.9));
    });

    test('a key that is rate limited or out of credits is skipped for the session', () async {
      final used = <String>[];
      final p = TavilySearchProvider(
        keys: ['k1', 'k2'],
        client: MockClient((r) async {
          final key = r.headers['Authorization']!;
          used.add(key);
          if (key.endsWith('k1')) return http.Response('plan limit', 432);
          return jsonResp({'results': [{'title': 't', 'url': 'https://t.example', 'content': 'c'}]});
        }),
      );
      expect(await p.search('q'), hasLength(1), reason: 'retried on the second key');
      expect(used, ['Bearer k1', 'Bearer k2']);
      used.clear();
      await p.search('q2');
      expect(used, ['Bearer k2'], reason: 'k1 is not tried again');
    });

    test('with every key spent it is unavailable', () async {
      final p = TavilySearchProvider(keys: ['only'], client: MockClient((_) async => http.Response('bad key', 401)));
      expect(p.available, isTrue);
      expect(await p.search('q'), isNull);
      expect(p.available, isFalse);
      expect(TavilySearchProvider(keys: const []).available, isFalse);
    });

    test('extract returns page text by URL', () async {
      final p = TavilySearchProvider(
        keys: ['k'],
        client: MockClient((_) async => jsonResp({
          'results': [
            {'url': 'https://h.example/a', 'raw_content': 'Step-free entrance and lift.'},
          ],
        })),
      );
      final m = (await p.extract(['https://h.example/a']))!;
      expect(m['https://h.example/a'], contains('Step-free'));
    });
  });

  group('Groq compound search parsing', () {
    test('prefers the results Groq actually searched over the model’s own JSON', () {
      final r = GroqSuccess(
        '{"results":[{"title":"invented","url":"https://invented.example"}]}',
        'groq/compound',
        raw: {
          'choices': [
            {
              'message': {
                'executed_tools': [
                  {
                    'type': 'search',
                    'search_results': {
                      'results': [
                        {'title': 'Real page', 'url': 'https://real.example', 'content': 'text', 'score': 0.8},
                      ],
                    },
                  },
                ],
              },
            },
          ],
        },
      );
      final out = CompoundSearchProvider.parse(r, 5)!;
      expect(out.single.url, 'https://real.example');
      expect(out.single.provider, 'Groq search');
    });

    test('falls back to the model’s JSON, leniently parsed', () {
      final r = GroqSuccess(
        'Here:\n```json\n{"results":[{"title":"A","url":"https://a.example","snippet":"s"},{"title":"B","url":"https://b.example",}]}\n```',
        'groq/compound',
      );
      expect(CompoundSearchProvider.parse(r, 5)!.map((e) => e.title), ['A', 'B']);
      expect(CompoundSearchProvider.parse(const GroqSuccess('no idea', 'groq/compound'), 5), isNull);
    });

    test('respects the shared spend cap and asks the search tier', () async {
      final llm = ScriptedLlm(['{"results":[{"title":"A","url":"https://a.example","snippet":"s"}]}']);
      var allowed = true;
      final p = CompoundSearchProvider(llm: llm, canSpend: () => allowed);
      expect(await p.search('q'), hasLength(1));
      expect(llm.asked.single.tier.name, 'search');
      allowed = false;
      expect(await p.search('q'), isNull);
      expect(llm.asked, hasLength(1));
    });
  });

  group('fetch_page', () {
    test('blocks private, local and non-http addresses', () {
      for (final bad in [
        'http://localhost:3001/api',
        'http://127.0.0.1/x',
        'http://10.0.0.5/x',
        'http://192.168.1.1/',
        'http://172.20.0.1/',
        'http://169.254.169.254/latest/meta-data',
        'file:///etc/passwd',
        'ftp://example.com/x',
        'http://intranet/x',
        'http://[::1]/x',
        'javascript:alert(1)',
        'not a url',
      ]) {
        expect(FetchPageTool.safeUri(bad), isNull, reason: bad);
      }
      expect(FetchPageTool.safeUri('https://www.tripadvisor.com/Hotel_Review-g1-d2.html'), isNotNull);
      expect(FetchPageTool.safeUri('http://172.32.0.1/x'), isNotNull, reason: 'outside the 172.16/12 private range');
    });

    test('turns HTML into readable text', () {
      final text = FetchPageTool.htmlToText('''
<html><head><title>Sunrise &amp; Co Hotel</title><style>.x{}</style><script>var a=1;</script></head>
<body><nav>menu menu</nav><h1>Amenities</h1><ul><li>Free parking</li><li>Wheelchair&nbsp;accessible entrance</li></ul>
<p>Rated &#8220;great&#8221; by guests.</p><footer>copyright</footer></body></html>''');
      expect(text, startsWith('Sunrise & Co Hotel'));
      expect(text, contains('Free parking'));
      expect(text, contains('Wheelchair accessible entrance'));
      expect(text, isNot(contains('menu menu')));
      expect(text, isNot(contains('var a')));
      expect(text, isNot(contains('copyright')));
    });

    test('fetches directly, caches, and truncates for the model', () async {
      var calls = 0;
      final tool = FetchPageTool(
        budget: ToolBudget(),
        maxChars: 50,
        client: MockClient((_) async {
          calls++;
          return http.Response('<html><body><p>${'word ' * 100}</p></body></html>', 200);
        }),
      );
      final a = await tool.run({'url': 'https://h.example/a'});
      final b = await tool.run({'url': 'https://h.example/a'});
      expect(a.ok, isTrue);
      expect(a.text.length, lessThanOrEqualTo(51));
      expect((a.data as String).length, greaterThan(200), reason: 'the full text is kept for code');
      expect(b.ok, isTrue);
      expect(calls, 1);
      expect(a.sources.single.url, 'https://h.example/a');
    });

    test('prefers Tavily extract when a key is available, and falls back if it fails', () async {
      final calls = <String>[];
      final tavily = TavilySearchProvider(
        keys: ['k'],
        client: MockClient((r) async {
          calls.add('tavily');
          return jsonResp({'results': [{'url': 'https://h.example/a', 'raw_content': 'From Tavily extract'}]});
        }),
      );
      final tool = FetchPageTool(
        budget: ToolBudget(),
        tavily: tavily,
        client: MockClient((_) async {
          calls.add('direct');
          return http.Response('<p>Direct text</p>', 200);
        }),
      );
      final a = await tool.run({'url': 'https://h.example/a'});
      expect(a.text, 'From Tavily extract');
      expect(a.sources.single.source, 'Tavily extract');

      final noResult = TavilySearchProvider(keys: ['k'], client: MockClient((_) async => jsonResp({'results': []})));
      final tool2 = FetchPageTool(
        budget: ToolBudget(),
        tavily: noResult,
        client: MockClient((_) async => http.Response('<p>Direct text</p>', 200)),
      );
      expect((await tool2.run({'url': 'https://h.example/b'})).text, 'Direct text');
    });

    test('rejects unsafe URLs, failures and empty pages without throwing', () async {
      final tool = FetchPageTool(budget: ToolBudget(), client: MockClient((_) async => http.Response('', 404)));
      expect((await tool.run({'url': 'http://localhost/x'})).ok, isFalse);
      expect((await tool.run({})).ok, isFalse);
      expect((await tool.run({'url': 'https://h.example/missing'})).ok, isFalse);
      final empty = FetchPageTool(budget: ToolBudget(), client: MockClient((_) async => http.Response('<html><script>x</script></html>', 200)));
      expect((await empty.run({'url': 'https://h.example/empty'})).ok, isFalse);
    });
  });

  group('tool loop', () {
    late ToolRegistry registry;
    late FakeTool search;

    setUp(() {
      search = FakeTool(
        'web_search',
        ToolOutput(ok: true, text: '1. Hotel A — https://a.example\n   step-free', data: [result('Hotel A', 'https://a.example')]),
      );
      registry = ToolRegistry()..register(search);
    });

    test('the model asks for a tool, reads the result, then answers', () async {
      final llm = ScriptedLlm([
        '{"tool":"web_search","args":{"query":"accessible hotels Munnar"}}',
        '{"final":{"entities":[{"name":"Hotel A"}]}}',
      ]);
      final r = await ToolLoop(llm: llm, tools: registry).run(
        agent: AgentKind.atithi,
        system: 'You find hotels.',
        context: 'Munnar, wheelchair',
        allowedTools: ['web_search'],
      );
      expect(r.hasAnswer, isTrue);
      expect(r.finalJson!['entities'], [{'name': 'Hotel A'}]);
      expect(search.calls.single['query'], 'accessible hotels Munnar');
      expect(r.usedFallback, isFalse);
      // The second turn saw the tool result.
      expect(llm.asked[1].messages.last.content, contains('TOOL RESULT (web_search)'));
      expect(llm.asked[1].messages.last.content, contains('Hotel A'));
      // The prompt lists the tools it may use.
      expect(llm.asked.first.messages.first.content, contains('web_search(query: string)'));
    });

    test('it can answer without any tool call', () async {
      final llm = ScriptedLlm(['{"final":{"entities":[]}}']);
      final r = await ToolLoop(llm: llm, tools: registry).run(
        agent: AgentKind.bhatkanti, system: 's', context: 'c', allowedTools: ['web_search'],
      );
      expect(r.hasAnswer, isTrue);
      expect(search.calls, isEmpty);
    });

    test('never exceeds the call cap: at the cap the model is told to answer', () async {
      final llm = ScriptedLlm([
        '{"tool":"web_search","args":{"query":"one"}}',
        '{"tool":"web_search","args":{"query":"two"}}',
        '{"tool":"web_search","args":{"query":"three"}}',
        '{"final":{"done":true}}',
      ]);
      final r = await ToolLoop(llm: llm, tools: registry, maxCalls: 2).run(
        agent: AgentKind.atithi, system: 's', context: 'c', allowedTools: ['web_search'],
        fallbackCalls: [],
      );
      expect(search.calls.length, lessThanOrEqualTo(2));
      expect(r.calls.length, lessThanOrEqualTo(2));
    });

    test('a tool that is not on the allow-list is refused', () async {
      final other = FakeTool('fetch_page', const ToolOutput(ok: true, text: 'x'));
      registry.register(other);
      final llm = ScriptedLlm([
        '{"tool":"fetch_page","args":{"url":"https://a.example"}}',
        '{"tool":"delete_everything","args":{}}',
      ])..fallback = '{"final":{"from":"fallback"}}';
      final r = await ToolLoop(llm: llm, tools: registry).run(
        agent: AgentKind.atithi, system: 's', context: 'c', allowedTools: ['web_search'],
        fallbackCalls: [{'tool': 'web_search', 'args': {'query': 'fallback query'}}],
      );
      expect(other.calls, isEmpty, reason: 'fetch_page was not allowed');
      expect(r.usedFallback, isTrue);
      expect(search.calls.single['query'], 'fallback query');
      expect(r.finalJson, {'from': 'fallback'});
    });

    test('garbage from the model falls back to the deterministic queries', () async {
      final llm = ScriptedLlm(['I think you should visit Munnar!', 'still not json'])
        ..fallback = '{"final":{"entities":["A"]}}';
      final r = await ToolLoop(llm: llm, tools: registry).run(
        agent: AgentKind.bhatkanti, system: 's', context: 'c', allowedTools: ['web_search'],
        fallbackCalls: [{'tool': 'web_search', 'args': {'query': 'top sights'}}],
      );
      expect(r.usedFallback, isTrue);
      expect(r.calls.single.viaFallback, isTrue);
      expect(r.finalJson, {'entities': ['A']});
    });

    test('a dead model still leaves the raw tool data for the caller', () async {
      final llm = ScriptedLlm()..fallback = null; // every ask fails
      final r = await ToolLoop(llm: llm, tools: registry).run(
        agent: AgentKind.bhatkanti, system: 's', context: 'c', allowedTools: ['web_search'],
        fallbackCalls: [{'tool': 'web_search', 'args': {'query': 'top sights'}}],
      );
      expect(r.hasAnswer, isFalse);
      expect(r.usedFallback, isTrue);
      expect(r.dataOf<List<SearchResult>>().single.single.title, 'Hotel A');
    });

    test('with no model and no tool data it returns an error, never throws', () async {
      final llm = ScriptedLlm()..fallback = null;
      search.output = ToolOutput.failure('offline');
      final r = await ToolLoop(llm: llm, tools: registry).run(
        agent: AgentKind.atithi, system: 's', context: 'c', allowedTools: ['web_search'],
        fallbackCalls: [{'tool': 'web_search', 'args': {'query': 'q'}}],
      );
      expect(r.hasAnswer, isFalse);
      expect(r.error, isNotNull);
    });

    test('an invalid reply gets one nudge before the fallback', () async {
      final llm = ScriptedLlm([
        'oops',
        '{"tool":"web_search","args":{"query":"retry"}}',
        '{"final":{"ok":1}}',
      ]);
      final r = await ToolLoop(llm: llm, tools: registry).run(
        agent: AgentKind.atithi, system: 's', context: 'c', allowedTools: ['web_search'],
      );
      expect(r.finalJson, {'ok': 1});
      expect(r.usedFallback, isFalse);
      expect(llm.asked[1].messages.any((m) => m.content.contains('not a valid reply')), isTrue);
    });

    test('very long tool results are truncated before the model sees them', () async {
      search.output = ToolOutput(ok: true, text: 'x' * 20000, data: const []);
      final llm = ScriptedLlm(['{"tool":"web_search","args":{"query":"q"}}', '{"final":{}}']);
      await ToolLoop(llm: llm, tools: registry, maxObservationChars: 500).run(
        agent: AgentKind.atithi, system: 's', context: 'c', allowedTools: ['web_search'],
      );
      expect(llm.asked[1].messages.last.content.length, lessThan(700));
    });
  });

  group('tool budget', () {
    test('caps searches, fetches and paid searches independently, with refunds', () {
      final b = ToolBudget(maxSearches: 2, maxFetches: 1, maxLlmSearches: 1);
      expect([b.trySpendSearch(), b.trySpendSearch(), b.trySpendSearch()], [true, true, false]);
      b.refundSearch();
      expect(b.trySpendSearch(), isTrue);
      expect([b.trySpendFetch(), b.trySpendFetch()], [true, false]);
      expect([b.trySpendLlmSearch(), b.trySpendLlmSearch()], [true, false]);
    });
  });

  test('registry describes only the allowed tools', () {
    final reg = ToolRegistry()
      ..register(FakeTool('web_search', const ToolOutput(ok: true)))
      ..register(FakeTool('fetch_page', const ToolOutput(ok: true)));
    final d = reg.describe(['web_search']);
    expect(d, contains('web_search'));
    expect(d, isNot(contains('fetch_page')));
    expect(reg.describe(['nope']), isEmpty);
  });

  test('memory cache is shared between search calls', () async {
    final cache = MemoryCache();
    final p = FakeSearchProvider('T', results: [result('a', 'https://a.example')]);
    await WebSearchTool(providers: [p], budget: ToolBudget(), cache: cache).run({'query': 'shared'});
    await WebSearchTool(providers: [p], budget: ToolBudget(), cache: cache).run({'query': 'shared'});
    expect(p.calls, 1);
  });
}
