import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/data/data_cache.dart';
import '../../services/data/http_util.dart';
import '../../services/data/wikipedia_client.dart';
import '../../services/groq_api_client.dart';
import '../runtime/agent_kind.dart';
import '../runtime/lenient_json.dart';
import '../runtime/llm_pool.dart';
import '../runtime/report.dart';
import 'agent_tool.dart';

class SearchResult {
  const SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    this.score,
    this.provider = '',
  });

  final String title;
  final String url;
  final String snippet;
  final double? score;

  /// Which backend found it ("Tavily", "Groq search", "Wikipedia").
  final String provider;

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'snippet': snippet,
    'score': score,
    'provider': provider,
  };

  static SearchResult? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final url = j['url'] as String?;
    if (url == null || url.isEmpty) return null;
    return SearchResult(
      title: (j['title'] as String?)?.trim() ?? url,
      url: url,
      snippet: (j['snippet'] as String?) ?? (j['content'] as String?) ?? '',
      score: asDouble(j['score']),
      provider: j['provider'] as String? ?? '',
    );
  }
}

/// One backend of the search chain.
abstract interface class SearchProvider {
  String get name;

  /// Whether it can be used at all right now (has a key, has credits left…).
  bool get available;

  /// Results, or null on failure (so the chain moves on).
  Future<List<SearchResult>?> search(String query, {int maxResults});
}

/// Tavily: web search built for AI agents. Free plan: 1,000 credits a month
/// per key; a basic search costs 1. Several keys are used round-robin, and a key
/// that is rejected or out of credits is skipped for the session.
class TavilySearchProvider implements SearchProvider {
  TavilySearchProvider({required List<String> keys, http.Client? client})
    : _keys = List.of(keys),
      _client = client ?? http.Client();

  final List<String> _keys;
  final http.Client _client;
  final Set<int> _spent = {};
  int _next = 0;

  @override
  String get name => 'Tavily';

  @override
  bool get available => _keys.isNotEmpty && _spent.length < _keys.length;

  /// The next usable key, rotating, or null.
  int? _pickKey() {
    if (!available) return null;
    for (var i = 0; i < _keys.length; i++) {
      final idx = (_next + i) % _keys.length;
      if (!_spent.contains(idx)) {
        _next = idx + 1;
        return idx;
      }
    }
    return null;
  }

  @override
  Future<List<SearchResult>?> search(String query, {int maxResults = 6}) async {
    // At most one retry on another key.
    for (var attempt = 0; attempt < 2; attempt++) {
      final idx = _pickKey();
      if (idx == null) return null;
      final o = await httpPost(
        _client,
        Uri.parse('https://api.tavily.com/search'),
        headers: {
          'Authorization': 'Bearer ${_keys[idx]}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'query': query,
          'search_depth': 'basic',
          'max_results': maxResults,
          'include_answer': false,
          'include_raw_content': false,
        }),
        timeout: const Duration(seconds: 12),
      );
      if (o.ok) return parse(o.json);
      // Rejected, rate limited or out of plan credits: retire this key.
      if (o.status == 401 || o.status == 403 || o.status == 429 || o.status == 432 || o.status == 433) {
        _spent.add(idx);
        continue;
      }
      return null;
    }
    return null;
  }

  static List<SearchResult>? parse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final results = json['results'];
    if (results is! List) return null;
    return [
      for (final r in results)
        if (SearchResult.fromJson(r) case final s?)
          SearchResult(
            title: s.title,
            url: s.url,
            snippet: s.snippet,
            score: s.score,
            provider: 'Tavily',
          ),
    ];
  }

  /// Page text for [urls] through Tavily's extract endpoint (1 credit per 5
  /// URLs). Returns url -> text.
  Future<Map<String, String>?> extract(List<String> urls) async {
    final idx = _pickKey();
    if (idx == null || urls.isEmpty) return null;
    final o = await httpPost(
      _client,
      Uri.parse('https://api.tavily.com/extract'),
      headers: {
        'Authorization': 'Bearer ${_keys[idx]}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'urls': urls, 'extract_depth': 'basic'}),
      timeout: const Duration(seconds: 20),
    );
    if (!o.ok) {
      if (o.status == 401 || o.status == 403 || o.status == 429 || o.status == 432 || o.status == 433) {
        _spent.add(idx);
      }
      return null;
    }
    final m = o.map;
    final results = m?['results'];
    if (results is! List) return null;
    return {
      for (final r in results)
        if (r is Map<String, dynamic> && r['url'] is String && r['raw_content'] is String)
          r['url'] as String: r['raw_content'] as String,
    };
  }
}

/// `groq/compound`: a model with built-in web search. It uses the Groq keys we
/// already have, but is billed per tool use, so [ToolBudget.maxLlmSearches]
/// keeps it rare.
class CompoundSearchProvider implements SearchProvider {
  CompoundSearchProvider({
    required this.llm,
    this.agent = AgentKind.khoji,
    this.canSpend,
  });

  final AgentLlm llm;
  final AgentKind agent;

  /// Asked before each call so a shared [ToolBudget] can veto it.
  final bool Function()? canSpend;

  @override
  String get name => 'Groq search';

  @override
  bool get available => llm.isConfigured;

  @override
  Future<List<SearchResult>?> search(String query, {int maxResults = 6}) async {
    if (canSpend != null && !canSpend!()) return null;
    final r = await llm.ask(
      agent,
      [
        const GroqMessage(
          'system',
          'Use web search to answer. Then reply ONLY with JSON: '
              '{"results":[{"title":"...","url":"https://...","snippet":"one or two sentences from the page"}]} '
              'listing the most relevant pages (real URLs you actually found). No other text.',
        ),
        GroqMessage('user', query),
      ],
      tier: LlmTier.search,
      maxTokens: 1500,
      timeout: const Duration(seconds: 25),
    );
    if (r is! GroqSuccess) return null;
    return parse(r, maxResults);
  }

  /// Prefers the search results Groq attaches to the response over the model's
  /// own JSON, since those URLs were really visited. Public for tests.
  static List<SearchResult>? parse(GroqSuccess r, int maxResults) {
    final out = <SearchResult>[];
    final choices = r.raw?['choices'];
    if (choices is List && choices.isNotEmpty) {
      final message = (choices.first as Map<String, dynamic>)['message'];
      final tools = message is Map<String, dynamic> ? message['executed_tools'] : null;
      if (tools is List) {
        for (final t in tools) {
          final sr = t is Map<String, dynamic> ? t['search_results'] : null;
          final results = sr is Map<String, dynamic> ? sr['results'] : null;
          if (results is List) {
            for (final item in results) {
              if (SearchResult.fromJson(item) case final s?) {
                out.add(
                  SearchResult(
                    title: s.title,
                    url: s.url,
                    snippet: s.snippet,
                    score: s.score,
                    provider: 'Groq search',
                  ),
                );
              }
            }
          }
        }
      }
    }
    if (out.isEmpty) {
      final json = parseLenientJson(r.content);
      final list = json is Map<String, dynamic> ? json['results'] : json;
      if (list is List) {
        for (final item in list) {
          if (SearchResult.fromJson(item) case final s?) {
            out.add(
              SearchResult(title: s.title, url: s.url, snippet: s.snippet, provider: 'Groq search'),
            );
          }
        }
      }
    }
    if (out.isEmpty) return null;
    return out.take(maxResults).toList();
  }
}

/// Wikipedia article search: no key, always available, thin but reliable.
class WikipediaSearchProvider implements SearchProvider {
  WikipediaSearchProvider(this.wiki);

  final WikipediaClient wiki;

  @override
  String get name => 'Wikipedia';

  @override
  bool get available => true;

  @override
  Future<List<SearchResult>?> search(String query, {int maxResults = 6}) async {
    final pages = await wiki.search(query, limit: maxResults);
    if (pages == null) return null;
    return [
      for (final p in pages)
        SearchResult(
          title: p.title,
          url: 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(p.title.replaceAll(' ', '_'))}',
          snippet: p.extract ?? '',
          provider: 'Wikipedia',
        ),
    ];
  }
}

/// The shared `web_search` tool: tries each provider in order (Tavily, then
/// Groq compound, then Wikipedia), caches every query, and counts spend
/// against the plan's [ToolBudget].
class WebSearchTool extends AgentTool {
  WebSearchTool({
    required this.providers,
    required this.budget,
    DataCache? cache,
    this.maxQueryLength = 200,
  }) : _cache = cache ?? MemoryCache();

  final List<SearchProvider> providers;
  final ToolBudget budget;
  final DataCache _cache;
  final int maxQueryLength;

  /// Which provider answered the most recent uncached search (for the feed).
  String? lastProvider;

  @override
  String get name => 'web_search';

  @override
  String get description =>
      'Search the web for hotels, places, reviews or facts about an area. Returns titles, URLs and snippets.';

  @override
  String get argsHelp => 'query: string, max_results?: int';

  @override
  Future<ToolOutput> run(Map<String, Object?> args, {AgentKind? caller}) async {
    final raw = args['query'];
    if (raw is! String || raw.trim().isEmpty) return ToolOutput.failure('missing "query"');
    final query = sanitizeQuery(raw, maxQueryLength);
    final maxResults = (asInt(args['max_results']) ?? 6).clamp(1, 10);

    final hit = await _cache.get('websearch.${query.toLowerCase()}.$maxResults');
    if (hit != null) {
      final results = _decode(hit);
      if (results.isNotEmpty) return _output(results, cached: true);
    }

    final searchable = budget.trySpendSearch();
    for (final p in providers) {
      if (!p.available) continue;
      // The paid-per-use provider only runs while the plan's budget allows;
      // the free fallbacks always may.
      final isFree = p is WikipediaSearchProvider;
      if (!searchable && !isFree) continue;
      final results = await p.search(query, maxResults: maxResults);
      if (results != null && results.isNotEmpty) {
        lastProvider = p.name;
        await _cache.put(
          'websearch.${query.toLowerCase()}.$maxResults',
          jsonEncode([for (final r in results) r.toJson()]),
          ttl: const Duration(hours: 24),
        );
        return _output(results);
      }
    }
    if (searchable) budget.refundSearch();
    return ToolOutput.failure('no search provider returned results for "$query"');
  }

  ToolOutput _output(List<SearchResult> results, {bool cached = false}) {
    final buf = StringBuffer();
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      final snippet = r.snippet.length > 260 ? '${r.snippet.substring(0, 260)}…' : r.snippet;
      buf.writeln('${i + 1}. ${r.title} — ${r.url}\n   $snippet');
    }
    return ToolOutput(
      ok: true,
      text: buf.toString().trim(),
      data: results,
      sources: [
        for (final r in results)
          Provenance(source: r.provider.isEmpty ? 'web search' : r.provider, url: r.url, confidence: 0.6),
      ],
    );
  }

  static List<SearchResult> _decode(String json) {
    try {
      return [
        for (final j in jsonDecode(json) as List<dynamic>)
          if (SearchResult.fromJson(j) case final s?) s,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Collapses whitespace, strips control characters and caps the length.
  /// Queries come from a language model steered by user text, so they are
  /// treated as untrusted.
  static String sanitizeQuery(String q, int maxLength) {
    final cleaned = q
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.length <= maxLength ? cleaned : cleaned.substring(0, maxLength);
  }
}
