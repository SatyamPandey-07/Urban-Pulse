import 'dart:async';

import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../services/data/wikipedia_client.dart';
import '../../services/groq_api_client.dart';
import '../runtime/agent_kind.dart';
import '../runtime/lenient_json.dart';
import '../runtime/llm_pool.dart';
import '../runtime/report.dart';
import '../tools/agent_tool.dart';
import '../tools/fetch_page_tool.dart';
import '../tools/web_search_tool.dart';
import '../travel_risk/travel_risk.dart';

enum KhojiSubject { hotel, hotspot }

/// What Khoji is asked to check.
class KhojiRequest {
  const KhojiRequest({
    required this.subject,
    required this.id,
    required this.name,
    required this.destination,
    this.claims = const [],
    this.needs = const {},
    this.pageUrl,
    this.wikiTitle,
    this.checkClosed = false,
  });

  final KhojiSubject subject;
  final String id;
  final String name;
  final String destination;

  /// Statements to check ("wheelchair accessible bathroom").
  final List<String> claims;
  final Set<AccessibilityNeed> needs;

  /// A listing page worth reading (a TripAdvisor hotel page).
  final String? pageUrl;
  final String? wikiTitle;

  /// Also find out whether the place has closed for good.
  final bool checkClosed;
}

/// What Khoji found.
class KhojiFinding {
  const KhojiFinding({
    this.claims = const [],
    this.reviews,
    this.access = const {},
    this.sources = const [],
    this.closed,
    this.methods = const [],
  });

  /// The requested claims, each with a verdict and the evidence behind it.
  final List<Claim> claims;

  /// Two or three guest reviews, usually the lower-rated ones.
  final Claim? reviews;

  /// What reviews and pages say about access needs.
  final Map<AccessibilityNeed, NeedSupport> access;
  final List<SourceRef> sources;

  /// True when a real source says the place has closed for good.
  final bool? closed;
  final List<String> methods;

  bool get isEmpty => claims.every((c) => c.verdict == Verdict.unverified) && reviews == null && access.isEmpty && closed != true;

  int get confirmed => claims.where((c) => c.verdict == Verdict.confirmed).length;
  int get contradicted => claims.where((c) => c.verdict == Verdict.contradicted).length;
}

/// Khoji, the verifier. It checks what other agents claim against what the web
/// says, and brings back guest reviews (the lower-rated ones, which carry the
/// problems), with the pages they came from.
///
/// Order of attack, cheapest honest option that works:
/// 1. the `web_search` chain (Tavily first) plus, for hotels, the listing page,
///    read by a light model;
/// 2. only when that finds nothing: a model that searches the web itself and
///    returns the pages it actually visited (heavy on the model's rate limit,
///    since every page it reads counts);
/// 3. simple rules over the snippets when no model can read them.
/// Alongside 1, for travellers with mobility needs, the Nugen-aligned
/// Travel-Risk model reads every snippet for step-free access, lifts, ramps,
/// toilets and stair counts, quoting the snippet word for word.
/// Nothing is ever taken on trust: a verdict or a quote only counts when it
/// points at a page that really came back from a search.
class Khoji {
  Khoji({
    required this.llm,
    required this.budget,
    this.search,
    this.fetchPage,
    this.wikipedia,
    this.travelRisk,
  });

  final AgentLlm llm;
  final ToolBudget budget;
  final WebSearchTool? search;
  final FetchPageTool? fetchPage;
  final WikipediaClient? wikipedia;

  /// Reads access facts from snippets; used only when it is the aligned model
  /// (the keyword rules add nothing over [_heuristic] here).
  final TravelRiskModel? travelRisk;

  static const _mobilityNeeds = {AccessibilityNeed.wheelchair, AccessibilityNeed.limitedMobility, AccessibilityNeed.elderlyCare};

  static const maxReviews = 3;
  static const _quoteMax = 220;

  Future<KhojiFinding> verify(KhojiRequest r, {bool Function()? isCancelled}) async {
    bool degraded() => isCancelled?.call() ?? false;
    final methods = <String>[];
    _Extraction? ex;
    var pool = <_Snippet>[];

    // 1. The search chain plus the listing page, read by a light model and,
    // for mobility needs, by the aligned Travel-Risk model.
    pool = await _gather(r, degraded);
    final risk = travelRisk;
    final readAccess = pool.isNotEmpty && risk != null && risk.isAligned && r.needs.any(_mobilityNeeds.contains) && !degraded();
    final accessRead = readAccess ? _viaTravelRisk(r, pool, risk) : Future.value(const <_AccessResult>[]);
    if (pool.isNotEmpty && llm.isConfigured && !degraded()) {
      final viaModel = await _viaSnippets(r, pool);
      if (viaModel != null && !viaModel.isEmpty) {
        ex = viaModel;
        methods.add(search?.lastProvider ?? 'Web search');
      }
    }
    final aligned = await accessRead;
    if (aligned.isNotEmpty) {
      final base = ex ?? _Extraction(sourceNames: {for (final s in pool) _norm(s.url): s.provider}, titles: {for (final s in pool) _norm(s.url): s.title});
      ex = _Extraction(
        claims: base.claims,
        reviews: base.reviews,
        access: [...base.access, ...aligned],
        closed: base.closed,
        titles: base.titles,
        sourceNames: base.sourceNames,
      );
      methods.add(risk!.label);
    }

    // 2. Nothing yet: the model that searches for itself.
    if ((ex == null || ex.isEmpty) && llm.isConfigured && !degraded() && budget.trySpendReviewSearch()) {
      final viaSearch = await _viaCompound(r);
      if (viaSearch != null && !viaSearch.isEmpty) {
        ex = viaSearch;
        methods.add('Groq search');
      }
    }

    // 3. Still nothing a model could read: the snippets that read like reviews.
    if ((ex == null || ex.isEmpty) && pool.isNotEmpty) {
      ex = _heuristic(r, pool);
      if (!ex.isEmpty) methods.add('Web search (unrated snippets)');
    }

    return _finding(r, ex ?? _Extraction(), methods);
  }

  // --- 1. compound ----------------------------------------------------------------

  Future<_Extraction?> _viaCompound(KhojiRequest r) async {
    final res = await llm.ask(
      AgentKind.khoji,
      [
        GroqMessage('system', _system(r, viaSnippets: false)),
        GroqMessage('user', _userPrompt(r)),
      ],
      tier: LlmTier.search,
      maxTokens: 2400,
      // A searching model opens pages before it answers.
      timeout: const Duration(seconds: 45),
    );
    if (res is! GroqSuccess) return null;
    final visited = _visitedUrls(res);
    final json = parseLenientObject(res.content);
    if (json == null) return null;
    return _extract(json, resolve: (item) {
      final url = item['url'];
      if (url is String && visited.contains(_norm(url))) return url;
      return null;
    }, visited: visited);
  }

  /// The pages the model's own searches returned, from the response's
  /// `executed_tools`: the only URLs it is allowed to cite.
  static Set<String> _visitedUrls(GroqSuccess r) {
    final out = <String>{};
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
              final url = item is Map<String, dynamic> ? item['url'] : null;
              if (url is String && url.isNotEmpty) out.add(_norm(url));
            }
          }
        }
      }
    }
    return out;
  }

  static String _norm(String url) => url.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();

  // --- 2. search chain ---------------------------------------------------------------

  Future<List<_Snippet>> _gather(KhojiRequest r, bool Function() degraded) async {
    final out = <_Snippet>[];
    final tool = search;
    if (tool != null) {
      final access = [for (final n in r.needs) if (n != AccessibilityNeed.none) n];
      final queries = [
        '"${r.name}" ${r.destination} reviews tripadvisor reddit',
        if (access.isNotEmpty)
          '"${r.name}" ${r.destination} ${access.contains(AccessibilityNeed.wheelchair) ? 'wheelchair' : 'elderly'} accessible review'
        else if (r.subject == KhojiSubject.hotel)
          '"${r.name}" ${r.destination} complaints problems review',
      ];
      final results = await Future.wait([
        for (final q in queries)
          tool.run({'query': q, 'max_results': 6, 'purpose': 'reviews'}, caller: AgentKind.khoji).catchError((_) => ToolOutput.failure('search failed')),
      ]);
      for (final o in results) {
        final data = o.data;
        if (!o.ok || data is! List) continue;
        for (final s in data.whereType<SearchResult>()) {
          if (out.any((x) => _norm(x.url) == _norm(s.url))) continue;
          if (s.snippet.trim().isEmpty) continue;
          out.add(_Snippet(out.length + 1, s.title, s.url, s.snippet, s.provider.isEmpty ? 'Web' : s.provider));
        }
      }
    }
    // The listing page holds reviews and amenities.
    final page = fetchPage;
    if (page != null && r.pageUrl != null && !degraded()) {
      try {
        final o = await page.run({'url': r.pageUrl}, caller: AgentKind.khoji);
        final text = o.data;
        if (o.ok && text is String && text.trim().isNotEmpty) {
          out.add(_Snippet(out.length + 1, '${r.name} listing', r.pageUrl!, _clip(text, 3500), 'TripAdvisor'));
        }
      } catch (_) {
        // the page is optional
      }
    }
    // Wikipedia for a place it knows.
    final wiki = wikipedia;
    if (wiki != null && r.wikiTitle != null && r.subject == KhojiSubject.hotspot) {
      try {
        final p = await wiki.summary(r.wikiTitle!);
        if (p?.extract != null && p!.extract!.isNotEmpty && p.url != null) {
          out.add(_Snippet(out.length + 1, p.title, p.url!, _clip(p.extract!, 700), 'Wikipedia'));
        }
      } catch (_) {
        // optional
      }
    }
    return out;
  }

  Future<_Extraction?> _viaSnippets(KhojiRequest r, List<_Snippet> pool) async {
    final numbered = StringBuffer();
    for (final s in pool) {
      numbered.writeln('[${s.index}] ${s.title} (${s.url})\n${_clip(s.text, 900)}\n');
    }
    final reply = await llm.askJson(
      AgentKind.khoji,
      system: _system(r, viaSnippets: true),
      user: '${_userPrompt(r)}\n\nSOURCES:\n$numbered',
      tier: LlmTier.light,
      temperature: 0.1,
      maxTokens: 1400,
      timeout: const Duration(seconds: 12),
    );
    final json = reply.map;
    if (json == null) return null;
    return _extract(json, resolve: (item) {
      final idx = item['sourceIndex'];
      final i = idx is num ? idx.toInt() : int.tryParse('$idx');
      for (final s in pool) {
        if (s.index == i) return s.url;
      }
      return null;
    }, visited: {for (final s in pool) _norm(s.url)}, titles: {for (final s in pool) _norm(s.url): s.title}, sourceNames: {for (final s in pool) _norm(s.url): s.provider});
  }

  /// The aligned model reads each review snippet (not encyclopedia text) for
  /// access facts. A fact only counts with a quote found in that snippet, and
  /// the snippet's own page is the source.
  Future<List<_AccessResult>> _viaTravelRisk(KhojiRequest r, List<_Snippet> pool, TravelRiskModel risk) async {
    final kind = r.subject == KhojiSubject.hotel ? 'hotel' : 'sight';
    final snippets = [for (final s in pool) if (s.provider != 'Wikipedia') s].take(6).toList();
    final facts = await Future.wait([
      for (final s in snippets)
        risk.accessClaims(place: r.name, kind: kind, city: r.destination, snippet: _clip(s.text, 900)).catchError((_) => const AccessFacts()),
    ]);
    final out = <_AccessResult>[];
    for (var i = 0; i < snippets.length; i++) {
      final f = facts[i];
      if (f.isEmpty || f.evidence.isEmpty) continue;
      final quote = _clip(f.evidence.take(2).join(' … '), _quoteMax);
      for (final need in r.needs.where(_mobilityNeeds.contains)) {
        final level = accessLevel(need, f, hotel: r.subject == KhojiSubject.hotel);
        if (level != null) out.add(_AccessResult(need, level, quote, snippets[i].url));
      }
    }
    return out;
  }

  /// What one snippet's access facts mean for one need, or null when they say
  /// nothing about it.
  static SupportLevel? accessLevel(AccessibilityNeed need, AccessFacts f, {required bool hotel}) {
    if (need == AccessibilityNeed.wheelchair) {
      if (f.stepFree == Tri.no) return SupportLevel.no;
      if (f.stepFree == Tri.yes) return f.accessibleToilet == Tri.no || (hotel && f.lift == Tri.no) ? SupportLevel.partial : SupportLevel.yes;
      if (f.ramp == Tri.yes) return SupportLevel.partial;
      if (hotel && f.lift == Tri.no) return SupportLevel.partial;
      if (f.accessibleToilet == Tri.yes) return SupportLevel.partial;
      return null;
    }
    // limited mobility and elderly care: steps matter by how many
    if (f.stepFree == Tri.yes) return SupportLevel.yes;
    if (f.stepFree == Tri.no) return (f.stairs ?? 0) >= 40 ? SupportLevel.no : SupportLevel.partial;
    if (hotel && f.lift == Tri.yes) return SupportLevel.yes;
    if (hotel && f.lift == Tri.no) return SupportLevel.partial;
    return null;
  }

  /// Without a model: the snippets that read like complaints are the reviews.
  _Extraction _heuristic(KhojiRequest r, List<_Snippet> pool) {
    final bad = RegExp(
      r"\b(dirty|rude|noisy|smell\w*|stairs|no (lift|elevator|ramp)|not (wheelchair )?accessible|overpriced|closed|crowded|queue\w*|scam|broken|poor|worst|disappoint\w*|unhygienic|cockroach\w*)\b",
      caseSensitive: false,
    );
    final reviews = <_Review>[];
    for (final s in pool) {
      if (s.provider == 'Wikipedia') continue;
      for (final sentence in s.text.split(RegExp(r'(?<=[.!?])\s+'))) {
        final t = sentence.trim();
        if (t.length < 25 || t.length > 260) continue;
        if (bad.hasMatch(t)) {
          reviews.add(_Review(quote: _clip(t, _quoteMax), rating: null, source: s.provider, url: s.url, title: s.title));
          break;
        }
      }
      if (reviews.length >= maxReviews) break;
    }
    return _Extraction(reviews: reviews, sourceNames: {for (final s in pool) _norm(s.url): s.provider}, titles: {for (final s in pool) _norm(s.url): s.title});
  }

  // --- parsing -----------------------------------------------------------------------

  String _system(KhojiRequest r, {required bool viaSnippets}) =>
      'You are Khoji, the verifier of a trip planner. You check claims about a ${r.subject == KhojiSubject.hotel ? 'hotel' : 'place'} '
      'against what real web pages say, and you report guest reviews honestly.\n'
      '${viaSnippets ? 'Use ONLY the numbered SOURCES given; cite them by "sourceIndex".' : 'Search the web: look for guest reviews on TripAdvisor, Google reviews pages, booking sites and travel forums such as Reddit, and open the pages you cite. Cite only pages you actually opened or found, by their exact "url".'}\n'
      'Reply with ONE JSON object:\n'
      '{"claims":[{"text":"<the claim, unchanged>","verdict":"confirmed|mixed|contradicted|unverified",'
      '"evidence":"one short sentence","${viaSnippets ? 'sourceIndex' : 'url'}":${viaSnippets ? '1' : '"https://..."'}}],'
      '"reviews":[{"quote":"a short quote or close paraphrase, under 200 characters","rating":2,"source":"site name",'
      '"${viaSnippets ? 'sourceIndex' : 'url'}":${viaSnippets ? '1' : '"https://..."'}}],'
      '"access":[{"need":"wheelchair|limitedMobility|visual|hearing|elderlyCare|serviceAnimal|cognitiveSensory",'
      '"level":"yes|partial|no","quote":"what a source says","${viaSnippets ? 'sourceIndex' : 'url'}":${viaSnippets ? '1' : '"https://..."'}}],'
      '"permanentlyClosed":false}\n'
      'Rules: prefer the LOWER-rated reviews (1 to 3 stars) and complaints, since they show the problems; give at most $maxReviews. '
      'When a review or page mentions steps, ramps, lifts, toilets or walking, report it under "access" with a short quote. '
      'Never invent a quote, a rating or a page. A verdict without a page is "unverified". '
      'Use empty arrays and permanentlyClosed null when you found nothing.';

  String _userPrompt(KhojiRequest r) {
    final b = StringBuffer('Name: ${r.name}\nPlace: ${r.destination}\n');
    if (r.claims.isNotEmpty) {
      b.writeln('Claims to check:');
      for (final c in r.claims) {
        b.writeln('- $c');
      }
    }
    final needs = [for (final n in r.needs) if (n != AccessibilityNeed.none) n.name];
    if (needs.isNotEmpty) b.writeln('Access needs that matter: ${needs.join(', ')}');
    if (r.checkClosed) b.writeln('Also say whether it has permanently closed.');
    return b.toString();
  }

  _Extraction _extract(
    Map<String, dynamic> json, {
    required String? Function(Map<String, dynamic> item) resolve,
    required Set<String> visited,
    Map<String, String> titles = const {},
    Map<String, String> sourceNames = const {},
  }) {
    List<Map<String, dynamic>> items(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e is Map<String, dynamic>) e,
    ];

    final claims = <_ClaimResult>[];
    for (final c in items(json['claims']).take(8)) {
      final text = (c['text'] as String?)?.trim();
      if (text == null || text.isEmpty) continue;
      var verdict = _verdict(c['verdict']);
      final url = resolve(c);
      // A verdict with no real page behind it is not a verdict.
      if (url == null && verdict != Verdict.unverified) verdict = Verdict.unverified;
      claims.add(_ClaimResult(text, verdict, (c['evidence'] as String?)?.trim(), url));
    }

    final reviews = <_Review>[];
    for (final rv in items(json['reviews'])) {
      final quote = (rv['quote'] as String?)?.replaceAll(RegExp(r'\s+'), ' ').trim();
      final url = resolve(rv);
      if (quote == null || quote.length < 12 || url == null) continue;
      final rating = rv['rating'] is num ? (rv['rating'] as num).toDouble() : null;
      reviews.add(
        _Review(
          quote: _clip(quote, _quoteMax),
          rating: rating != null && rating >= 1 && rating <= 5 ? rating : null,
          source: (rv['source'] as String?)?.trim().isNotEmpty == true ? (rv['source'] as String).trim() : (sourceNames[_norm(url)] ?? _host(url)),
          url: url,
          title: titles[_norm(url)] ?? _host(url),
        ),
      );
    }
    // The lower-rated first; unrated ones after.
    reviews.sort((a, b) => (a.rating ?? 6).compareTo(b.rating ?? 6));

    final access = <_AccessResult>[];
    for (final a in items(json['access']).take(8)) {
      final need = _need(a['need']);
      final level = _level(a['level']);
      final url = resolve(a);
      final quote = (a['quote'] as String?)?.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (need == null || level == null || url == null || quote == null || quote.length < 8) continue;
      access.add(_AccessResult(need, level, _clip(quote, _quoteMax), url));
    }

    final closedRaw = json['permanentlyClosed'];
    // Only believed with a page to point at; the claim list may carry it, so
    // require any resolved URL in the reply.
    final anyEvidence = claims.any((c) => c.url != null) || reviews.isNotEmpty;
    final closed = closedRaw == true && anyEvidence ? true : null;

    return _Extraction(
      claims: claims,
      reviews: reviews.take(maxReviews).toList(),
      access: access,
      closed: closed,
      titles: titles,
      sourceNames: sourceNames,
    );
  }

  static Verdict _verdict(Object? v) => switch ('$v'.toLowerCase().trim()) {
    'confirmed' => Verdict.confirmed,
    'mixed' => Verdict.mixed,
    'contradicted' => Verdict.contradicted,
    _ => Verdict.unverified,
  };

  static SupportLevel? _level(Object? v) => switch ('$v'.toLowerCase().trim()) {
    'yes' => SupportLevel.yes,
    'partial' => SupportLevel.partial,
    'no' => SupportLevel.no,
    _ => null,
  };

  static AccessibilityNeed? _need(Object? v) {
    for (final n in AccessibilityNeed.values) {
      if (n.name == '$v' && n != AccessibilityNeed.none) return n;
    }
    return null;
  }

  // --- output ------------------------------------------------------------------------

  KhojiFinding _finding(KhojiRequest r, _Extraction ex, List<String> methods) {
    final sources = <SourceRef>[];
    void addSource(String url, String title, String source, {String? snippet}) {
      if (sources.any((s) => _norm(s.url) == _norm(url))) return;
      sources.add(SourceRef(title: title, url: url, source: source, snippet: snippet));
    }

    String titleOf(String url) => ex.titles[_norm(url)] ?? _host(url);
    String nameOf(String url) => ex.sourceNames[_norm(url)] ?? _host(url);

    // Every requested claim gets a verdict, even if only "unverified".
    final claims = <Claim>[];
    for (final text in r.claims) {
      final hit = ex.claims.where((c) => _sameClaim(c.text, text)).firstOrNull;
      if (hit == null) {
        claims.add(Claim(text: text, confidence: 0.3));
        continue;
      }
      final refs = <SourceRef>[];
      if (hit.url != null) {
        final ref = SourceRef(title: titleOf(hit.url!), url: hit.url!, snippet: hit.evidence, source: nameOf(hit.url!));
        refs.add(ref);
        addSource(ref.url, ref.title, 'Khoji · ${ref.source}', snippet: hit.evidence);
      }
      claims.add(
        Claim(
          text: text,
          verdict: hit.verdict,
          sources: refs,
          confidence: switch (hit.verdict) {
            Verdict.confirmed => 0.8,
            Verdict.contradicted => 0.8,
            Verdict.mixed => 0.55,
            Verdict.unverified => 0.3,
          },
        ),
      );
    }

    Claim? reviews;
    if (ex.reviews.isNotEmpty) {
      final refs = <SourceRef>[];
      final quotes = <String>[];
      for (final rv in ex.reviews) {
        final stars = rv.rating == null ? '' : '★${rv.rating!.toStringAsFixed(rv.rating! % 1 == 0 ? 0 : 1)} · ';
        quotes.add('$stars“${rv.quote}” — ${rv.source}');
        if (!refs.any((x) => _norm(x.url) == _norm(rv.url))) refs.add(SourceRef(title: rv.title, url: rv.url, source: rv.source));
        addSource(rv.url, rv.title, 'Khoji · ${rv.source}');
      }
      reviews = Claim(text: Claim.reviewsLabel, verdict: Verdict.unverified, reviewQuotes: quotes, sources: refs, confidence: 0.6);
    }

    final access = <AccessibilityNeed, NeedSupport>{};
    for (final a in ex.access) {
      final next = NeedSupport(
        need: a.need,
        level: a.level,
        detail: 'A source says: “${a.quote}”',
        provenance: Provenance(source: 'Reviews and pages found by Khoji', url: a.url, confidence: 0.6),
      );
      final prev = access[a.need];
      access[a.need] = prev == null ? next : _worse(prev, next);
      addSource(a.url, titleOf(a.url), 'Khoji · ${nameOf(a.url)}', snippet: a.quote);
    }

    return KhojiFinding(claims: claims, reviews: reviews, access: access, sources: sources, closed: ex.closed, methods: methods);
  }

  /// Two readings of the same need from Khoji's own sources: the more worrying wins.
  static NeedSupport _worse(NeedSupport a, NeedSupport b) {
    int rank(SupportLevel l) => switch (l) {
      SupportLevel.no => 0,
      SupportLevel.partial => 1,
      SupportLevel.unknown => 2,
      SupportLevel.yes => 3,
    };
    return rank(a.level) <= rank(b.level) ? a : b;
  }

  static bool _sameClaim(String a, String b) {
    String n(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final x = n(a);
    final y = n(b);
    return x == y || (x.length > 12 && y.length > 12 && (x.contains(y) || y.contains(x)));
  }

  static String _host(String url) => Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? url;

  static String _clip(String s, int max) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= max ? t : '${t.substring(0, max - 1).trimRight()}…';
  }
}

class _Snippet {
  const _Snippet(this.index, this.title, this.url, this.text, this.provider);

  final int index;
  final String title;
  final String url;
  final String text;
  final String provider;
}

class _ClaimResult {
  const _ClaimResult(this.text, this.verdict, this.evidence, this.url);

  final String text;
  final Verdict verdict;
  final String? evidence;
  final String? url;
}

class _Review {
  const _Review({required this.quote, required this.rating, required this.source, required this.url, required this.title});

  final String quote;
  final double? rating;
  final String source;
  final String url;
  final String title;
}

class _AccessResult {
  const _AccessResult(this.need, this.level, this.quote, this.url);

  final AccessibilityNeed need;
  final SupportLevel level;
  final String quote;
  final String url;
}

class _Extraction {
  _Extraction({
    this.claims = const [],
    this.reviews = const [],
    this.access = const [],
    this.closed,
    this.titles = const {},
    this.sourceNames = const {},
  });

  final List<_ClaimResult> claims;
  final List<_Review> reviews;
  final List<_AccessResult> access;
  final bool? closed;
  final Map<String, String> titles;
  final Map<String, String> sourceNames;

  bool get isEmpty => claims.isEmpty && reviews.isEmpty && access.isEmpty && closed != true;
}
