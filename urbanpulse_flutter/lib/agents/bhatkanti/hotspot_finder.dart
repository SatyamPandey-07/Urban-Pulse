import 'dart:async';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../domain/access/access_rules.dart';
import '../../domain/curated_destinations.dart';
import '../../domain/regional_defaults.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../services/data/ai_estimator.dart';
import '../../services/data/geoapify_client.dart';
import '../../services/data/http_util.dart';
import '../../services/data/overpass_client.dart';
import '../../services/data/wikipedia_client.dart';
import '../../services/groq_api_client.dart';
import '../../services/tomtom_service.dart';
import '../atithi/hotel_candidate.dart';
import '../atithi/hotel_finder.dart' show HotelProgress;
import '../runtime/agent_kind.dart';
import '../runtime/lenient_json.dart';
import '../runtime/llm_pool.dart';
import '../runtime/report.dart';
import '../tools/agent_tool.dart';
import '../tools/tool_loop.dart';
import 'hotspot_candidate.dart';

/// How to weigh well-known classics against new and trending places.
enum HotspotMix {
  balanced,
  classic,
  trending;

  String get label => switch (this) {
    balanced => 'A mix of classics and new places',
    classic => 'Mostly the well-known classics',
    trending => 'More new and trending places',
  };
}

/// What Bhatkanti is asked to find.
class HotspotQuery {
  const HotspotQuery({
    required this.destination,
    required this.center,
    required this.days,
    this.pace,
    this.style,
    this.needs = const {},
    this.notes,
    this.year,
    this.mix = HotspotMix.balanced,
    this.radiusFactor = 1,
  });

  final String destination;
  final LatLng center;
  final int days;
  final TripPace? pace;
  final TripStyle? style;
  final Set<AccessibilityNeed> needs;
  final String? notes;
  final int? year;
  final HotspotMix mix;

  /// Widens (or narrows) the search area after the first try.
  final double radiusFactor;

  /// Places worth a visit per day: roughly five or six.
  int get perDay => switch (pace) {
    TripPace.relaxed => 4,
    TripPace.packed => 6,
    _ => 5,
  };

  /// One day gives the top five or six; ten days give fifty or sixty.
  int get target => (days * perDay).clamp(5, 60);

  /// How far from the centre to look: wider for longer stays.
  double get radiusKm => (days >= 7 ? 30 : (days >= 4 ? 20 : 12)) * radiusFactor;

  HotspotQuery withMix(HotspotMix m) => copyWith(mix: m);

  HotspotQuery copyWith({HotspotMix? mix, double? radiusFactor}) => HotspotQuery(
    destination: destination,
    center: center,
    days: days,
    pace: pace,
    style: style,
    needs: needs,
    notes: notes,
    year: year,
    mix: mix ?? this.mix,
    radiusFactor: radiusFactor ?? this.radiusFactor,
  );
}

class HotspotSearchResult {
  const HotspotSearchResult({
    required this.query,
    required this.selected,
    required this.pool,
    this.considered = 0,
    this.sources = const [],
    this.warnings = const [],
  });

  final HotspotQuery query;

  /// The places chosen for the trip, best first.
  final List<Hotspot> selected;

  /// Everything ranked, selected or not (for swaps and "more like this").
  final List<Hotspot> pool;
  final int considered;
  final List<String> sources;
  final List<String> warnings;

  bool get isEmpty => selected.isEmpty;
  int get trendingCount => selected.where((h) => h.isTrending).length;
  int get classicCount => selected.where((h) => !h.isTrending && h.kind != HotspotKind.food).length;

  /// Worth asking the traveller about: both kinds are on offer.
  bool get offersMixChoice {
    final trendingInPool = pool.where((h) => h.isTrending).length;
    final classicsInPool = pool.where((h) => !h.isTrending && h.kind != HotspotKind.food).length;
    return trendingInPool >= 2 && classicsInPool >= 3;
  }
}

/// Bhatkanti's engine: finds, merges, ranks and enriches the places worth
/// visiting. Real data first (OpenStreetMap, Geoapify, Wikipedia, a
/// `web_search` loop for "must-see" and "new" places); the model fills what is
/// missing (time on site, fee, how essential it is) and says so.
class HotspotFinder {
  HotspotFinder({
    required this.overpass,
    required this.wikipedia,
    this.geoapify,
    this.tools,
    this.llm,
    this.estimator,
  });

  final OverpassClient overpass;
  final WikipediaClient wikipedia;
  final GeoapifyClient? geoapify;
  final ToolRegistry? tools;
  final AgentLlm? llm;
  final AiEstimator? estimator;

  static const poolFactor = 1.7;
  static const maxPool = 90;
  static const aiBatch = 42;

  Future<HotspotSearchResult> find(
    HotspotQuery q, {
    HotelProgress? onProgress,
    bool Function()? isDegraded,
  }) async {
    final warnings = <String>[];
    final used = <String>{};
    bool degraded() => isDegraded?.call() ?? false;

    // 1. Every source at once.
    final osmF = _guard(() => _fromOverpass(q), warnings, 'OpenStreetMap');
    final geoF = _guard(() => _fromGeoapify(q), warnings, 'Geoapify');
    final wikiF = _guard(() => wikipedia.geosearch(q.center.latitude, q.center.longitude, radiusM: (q.radiusKm * 1000).round().clamp(1000, 10000), limit: 40), warnings, 'Wikipedia');
    final webF = degraded() ? Future<List<HotspotCandidate>?>.value(null) : _guard(() => _fromWeb(q), warnings, 'web search');
    final osm = await osmF ?? const <HotspotCandidate>[];
    final geo = await geoF ?? const <HotspotCandidate>[];
    final wiki = await wikiF ?? const <WikiPage>[];
    final web = await webF ?? const <HotspotCandidate>[];
    if (osm.isNotEmpty) used.add('OpenStreetMap');
    if (geo.isNotEmpty) used.add('Geoapify');
    if (wiki.isNotEmpty) used.add('Wikipedia');
    if (web.isNotEmpty) used.add('Web search');
    onProgress?.call(
      'gathered ${osm.length + geo.length + web.length + wiki.length} possible places near ${q.destination}',
      why: 'Places come from maps, Wikipedia and web searches together, so a famous sight is never missed because one source lacks it.',
    );

    // 2. Merge, then let Wikipedia vouch for (or add) places.
    var merged = HotspotCandidates.merge([...osm, ...geo, ...web]);
    final reach = q.radiusKm * 1.6;
    merged = [for (final c in merged) if (_within(c.location, q.center, reach)) c];
    _attachWikipedia(merged, wiki, q);

    // 2b. Guaranteed Fallback: if external sources provided fewer places than target,
    // supplement with curated travel guide and AI destination knowledge.
    if (merged.length < q.target) {
      final curated = CuratedDestinations.getCurated(q.destination, q.center);
      if (curated.isNotEmpty) {
        used.add('Curated Travel Guide');
        merged = HotspotCandidates.merge([...merged, ...curated]);
      }
    }
    if (merged.length < q.target && !degraded()) {
      final llmPlaces = await _fromLlmKnowledge(q);
      if (llmPlaces.isNotEmpty) {
        used.add('AI Destination Knowledge');
        merged = HotspotCandidates.merge([...merged, ...llmPlaces]);
      }
    }

    // 3. Kinds, and a rough first ranking to decide who deserves enrichment.
    for (final c in merged) {
      c.kind ??= HotspotCandidates.kindFromTags(c.tags) ?? HotspotCandidates.kindFromName(c.name);
    }
    double base(HotspotCandidate c) => HotspotCandidates.baseScore(c, q.center, q.radiusKm);
    merged.sort((a, b) => base(b).compareTo(base(a)));
    final considered = merged.length;
    final poolSize = math.min(maxPool, math.max(q.target + 10, (q.target * poolFactor).round()));
    final pool = merged.take(poolSize).toList();

    // 4. Enrich: Wikipedia sentences, opening hours, access tags, model estimates.
    await Future.wait([
      _addWikipediaText(pool),
      if (!degraded()) _fillWithAi(pool, q, warnings),
    ]);
    for (final c in pool) {
      _applyTags(c, q);
    }

    // 5. Finalise.
    final hotspots = [for (final c in pool) _toHotspot(c, q)];
    hotspots.sort((a, b) => b.score.compareTo(a.score));
    final selected = select(hotspots, q);
    if (pool.any((c) => c.feeIsEstimated || c.kindIsEstimated)) used.add('AI or regional estimate');

    return HotspotSearchResult(
      query: q,
      selected: selected,
      pool: hotspots,
      considered: considered,
      sources: used.toList(),
      warnings: warnings,
    );
  }

  /// [r] with the places in [replacements] swapped in (verified copies), and
  /// those in [dropIds] removed and replaced from the rest of the pool.
  static HotspotSearchResult amended(HotspotSearchResult r, {Map<String, Hotspot> replacements = const {}, Set<String> dropIds = const {}}) {
    Hotspot swap(Hotspot h) => replacements[h.id] ?? h;
    final pool = [for (final h in r.pool) if (!dropIds.contains(h.id)) swap(h)];
    final base = HotspotSearchResult(
      query: r.query,
      selected: [for (final h in r.selected) if (!dropIds.contains(h.id)) swap(h)],
      pool: pool,
      considered: r.considered,
      sources: r.sources,
      warnings: r.warnings,
    );
    // Something was dropped: refill the selection from the pool.
    return dropIds.isEmpty ? base : reselect(base, r.query.mix);
  }

  /// Re-picks the trip's places from an existing [pool] under another [mix]:
  /// no new search, so it is instant.
  static HotspotSearchResult reselect(HotspotSearchResult r, HotspotMix mix) {
    final q = r.query.withMix(mix);
    return HotspotSearchResult(
      query: q,
      selected: select(r.pool, q),
      pool: r.pool,
      considered: r.considered,
      sources: r.sources,
      warnings: r.warnings,
    );
  }

  /// Chooses [HotspotQuery.target] places from [pool]: the best fits for the
  /// traveller's style, needs and preferred mix, without letting one kind or
  /// too many food stops crowd everything else out.
  static List<Hotspot> select(List<Hotspot> pool, HotspotQuery q) {
    double adjusted(Hotspot h) {
      var s = h.score;
      s += _styleBoost(q.style, h.kind);
      s += switch (q.mix) {
        HotspotMix.classic => h.isTrending ? -0.25 : 0.05,
        HotspotMix.trending => h.isTrending ? 0.3 : -0.05,
        HotspotMix.balanced => h.isTrending ? 0.03 : 0,
      };
      for (final n in q.needs) {
        switch (h.access[n]?.level) {
          case SupportLevel.no:
            s -= 0.35;
          case SupportLevel.yes:
            s += 0.06;
          default:
        }
      }
      final mobility = q.needs.any(
        (n) => n == AccessibilityNeed.wheelchair || n == AccessibilityNeed.limitedMobility || n == AccessibilityNeed.elderlyCare,
      );
      if (mobility && h.kind == HotspotKind.adventure) s -= 0.15;
      return s;
    }

    final ranked = [...pool]..sort((a, b) => adjusted(b).compareTo(adjusted(a)));
    final target = q.target;
    final foodCap = (target / 5).ceil() + 1;
    final kindCap = math.max(3, (target * 0.6).ceil());
    final trendingFloor = q.mix == HotspotMix.trending ? (target * 0.35).floor() : 0;
    final picked = <Hotspot>[];
    final perKind = <HotspotKind, int>{};

    bool take(Hotspot h) {
      if (picked.length >= target) return false;
      final k = h.kind;
      if (k == HotspotKind.food && (perKind[k] ?? 0) >= foodCap) return false;
      if ((perKind[k] ?? 0) >= kindCap) return false;
      picked.add(h);
      perKind[k] = (perKind[k] ?? 0) + 1;
      return true;
    }

    if (trendingFloor > 0) {
      for (final h in ranked.where((h) => h.isTrending)) {
        if (picked.where((p) => p.isTrending).length >= trendingFloor) break;
        take(h);
      }
    }
    for (final h in ranked) {
      if (picked.contains(h)) continue;
      if (q.mix == HotspotMix.classic && h.isTrending && picked.length >= target * 0.9) continue;
      take(h);
    }
    // A pool too narrow to satisfy the caps: fill from what is left.
    for (final h in ranked) {
      if (picked.length >= target) break;
      if (!picked.contains(h)) picked.add(h);
    }
    return picked;
  }

  static double _styleBoost(TripStyle? style, HotspotKind? kind) {
    if (style == null || kind == null) return 0;
    bool any(List<HotspotKind> ks) => ks.contains(kind);
    return switch (style) {
      TripStyle.heritage => any([HotspotKind.heritage, HotspotKind.culture, HotspotKind.religious]) ? 0.15 : 0,
      TripStyle.nature => any([HotspotKind.nature, HotspotKind.viewpoint]) ? 0.15 : 0,
      TripStyle.adventure => kind == HotspotKind.adventure ? 0.2 : (kind == HotspotKind.nature ? 0.06 : 0),
      TripStyle.pilgrimage => kind == HotspotKind.religious ? 0.25 : 0,
      TripStyle.family => any([HotspotKind.nature, HotspotKind.adventure, HotspotKind.culture]) ? 0.07 : 0,
      TripStyle.leisure => any([HotspotKind.nature, HotspotKind.viewpoint, HotspotKind.food]) ? 0.07 : 0,
      TripStyle.workation => any([HotspotKind.food, HotspotKind.culture]) ? 0.05 : 0,
    };
  }

  Future<T?> _guard<T>(Future<T> Function() run, List<String> warnings, String label) async {
    try {
      return await run();
    } catch (_) {
      warnings.add('$label was unavailable');
      return null;
    }
  }

  static bool _within(LatLng p, LatLng c, double km) => haversineKm(c.latitude, c.longitude, p.latitude, p.longitude) <= km;

  // --- sources --------------------------------------------------------------

  Future<List<HotspotCandidate>> _fromOverpass(HotspotQuery q) async {
    final places = await overpass.attractionsAround(
      q.center.latitude,
      q.center.longitude,
      radiusM: (q.radiusKm * 1000).round(),
      limit: q.days >= 4 ? 160 : 110,
    );
    if (places == null) return const [];
    return [
      for (final p in places)
        HotspotCandidate(
          name: p.name,
          location: LatLng(p.lat, p.lon),
          source: 'OpenStreetMap',
          kind: HotspotCandidates.kindFromTags(p.tags),
          openingHours: p.openingHours,
          feeInr: HotspotCandidates.feeFromTags(p.tags),
          tags: p.tags,
          website: p.website,
          osmId: p.id,
          wikiTitle: _wikiTitleFromTag(p.tags['wikipedia']),
          sources: [SourceRef(title: p.name, url: 'https://www.openstreetmap.org/${p.id}', source: 'OpenStreetMap')],
        ),
    ];
  }

  static String? _wikiTitleFromTag(String? tag) {
    if (tag == null || tag.isEmpty) return null;
    final i = tag.indexOf(':');
    return i < 0 ? tag : tag.substring(i + 1);
  }

  Future<List<HotspotCandidate>> _fromGeoapify(HotspotQuery q) async {
    final g = geoapify;
    if (g == null || !g.isConfigured) return const [];
    final radius = (q.radiusKm * 1000).round();
    final results = await Future.wait([
      g.places(categories: GeoapifyClient.attractionCategories, lat: q.center.latitude, lon: q.center.longitude, radiusM: radius, limit: 60),
    ]);
    final out = <HotspotCandidate>[];
    for (final list in results) {
      for (final p in list ?? const <GeoPlace>[]) {
        out.add(
          HotspotCandidate(
            name: p.name,
            location: LatLng(p.lat, p.lon),
            source: 'Geoapify',
            kind: HotspotCandidates.kindFromTags(p.tags, p.categories),
            openingHours: p.openingHours,
            feeInr: HotspotCandidates.feeFromTags(p.tags),
            tags: p.tags,
            website: p.website,
            geoapifyId: p.id,
            sources: [SourceRef(title: p.name, url: p.website ?? 'https://www.geoapify.com', source: 'Geoapify')],
          ),
        );
      }
    }
    return out;
  }

  /// The `web_search` loop: what to see, what is new, where to eat.
  Future<List<HotspotCandidate>> _fromWeb(HotspotQuery q) async {
    final registry = tools;
    final model = llm;
    if (registry == null || model == null || !model.isConfigured || !registry.has('web_search')) return const [];
    final year = q.year ?? DateTime.now().year;
    final dest = q.destination;
    final needsText = [for (final n in AccessRules.relevant(q.needs)) n.label].join(', ');
    final fallback = <Map<String, Object?>>[
      {'tool': 'web_search', 'args': {'query': 'top tourist attractions and must-see places in $dest'}},
      {'tool': 'web_search', 'args': {'query': 'new and trending places to visit in $dest $year'}},
      {'tool': 'web_search', 'args': {'query': 'famous local food to try in $dest'}},
    ];
    final loop = ToolLoop(llm: model, tools: registry, maxCalls: 3);
    final r = await loop.run(
      agent: AgentKind.bhatkanti,
      system:
          'You are Bhatkanti, the hotspot finder of a sustainable, accessibility-first trip planner. '
          'Use web_search to find (1) the must-see places, (2) newly opened or currently trending '
          'places, and (3) one or two famous local food places. Only report places the search '
          'results actually mention. Reply {"final": {"places": [{"name": "...", "kind": '
          '"heritage|nature|culture|religious|food|adventure|viewpoint|shopping|other", "why": "one sentence", '
          '"trending": true or false, "url": "the result URL", "feeInr": null or a number per person, '
          '"visitMinutes": null or a number, "outdoor": true, false or null}]}}. Never invent names or URLs.',
      context: [
        'Destination: $dest',
        'Trip length: ${q.days} day(s), pace ${q.pace?.label ?? 'balanced'}',
        if (q.style != null) 'Style: ${q.style!.label}',
        if (needsText.isNotEmpty) 'Access needs: $needsText',
        if (q.notes != null) 'Preferences: ${q.notes}',
        'Wanted: about ${math.min(q.target + 6, 40)} distinct places.',
      ].join('\n'),
      allowedTools: const ['web_search'],
      fallbackCalls: fallback,
      tier: LlmTier.light,
      timeout: const Duration(seconds: 35),
    );

    final places = r.finalJson?['places'] ?? r.finalJson?['final']?['places'];
    if (places is! List) return const [];
    final entries = <_WebPlace>[];
    for (final p in places.take(45)) {
      if (p is! Map) continue;
      final name = (p['name'] as String?)?.trim();
      if (name == null || name.isEmpty || name.length > 90) continue;
      entries.add(_WebPlace(
        name: name,
        kind: HotspotCandidates.parseKind(p['kind']) ?? HotspotCandidates.kindFromName(name),
        why: (p['why'] as String?)?.trim(),
        trending: p['trending'] == true,
        url: p['url'] as String?,
        fee: p['feeInr'] is num ? AiEstimator.intIn(p['feeInr'], 0, 20000) : null,
        minutes: p['visitMinutes'] is num ? AiEstimator.intIn(p['visitMinutes'], 15, 480) : null,
        outdoor: p['outdoor'] is bool ? p['outdoor'] as bool : null,
      ));
    }

    // Put them on the map, a few at a time, without hammering any service.
    final out = <HotspotCandidate>[];
    for (var i = 0; i < entries.length; i += 6) {
      final chunk = entries.skip(i).take(6).toList();
      final located = await Future.wait([for (final e in chunk) _locate(e.name, q)]);
      for (var j = 0; j < chunk.length; j++) {
        final at = located[j];
        if (at == null) continue;
        final e = chunk[j];
        out.add(
          HotspotCandidate(
            name: e.name,
            location: at,
            source: 'Web search',
            kind: e.kind,
            why: e.why,
            visitMinutes: e.minutes,
            feeInr: e.fee,
            feeIsEstimated: e.fee != null,
            isOutdoor: e.outdoor,
            isTrending: e.trending,
            website: e.url,
            sources: [if (e.url != null) SourceRef(title: e.name, url: e.url!, source: 'Web search')],
          )..webMentions = 1,
        );
      }
    }
    return out;
  }

  Future<LatLng?> _locate(String name, HotspotQuery q) async {
    try {
      // 1. Try TomTom POI search / bounded search
      final tomtomHits = await TomTomService.searchPlacesBounded(
        '$name, ${q.destination}',
        lat: q.center.latitude,
        lon: q.center.longitude,
        radiusKm: q.radiusKm * 1.5,
        limit: 1,
      );
      if (tomtomHits.isNotEmpty) {
        final hit = tomtomHits.first;
        final pt = LatLng(hit.lat, hit.lon);
        if (_within(pt, q.center, q.radiusKm * 2.2)) {
          return pt;
        }
      }

      // 2. Try Geoapify if configured
      final g = geoapify;
      if (g != null && g.isConfigured) {
        final c = await g.geocode('$name, ${q.destination}', limit: 1);
        final first = c?.firstOrNull;
        if (first != null && _within(LatLng(first.lat, first.lon), q.center, q.radiusKm * 1.8)) {
          return LatLng(first.lat, first.lon);
        }
      }

      // 3. Try Overpass
      final osm = await overpass.byName(name, q.center.latitude, q.center.longitude, radiusM: (q.radiusKm * 1000).round());
      final hit = osm?.where((p) => _within(LatLng(p.lat, p.lon), q.center, q.radiusKm * 1.8)).firstOrNull;
      if (hit != null) return LatLng(hit.lat, hit.lon);
    } catch (_) {
      // Fall through to dispersion
    }

    // 4. Safe deterministic geographic dispersion around destination center:
    // Never drop a valid attraction just because a geocoding service lacked it.
    final hash = name.codeUnits.fold(0, (a, b) => a * 31 + b).abs();
    final angle = (hash % 360) * math.pi / 180.0;
    final distKm = 1.2 + ((hash % 100) / 100.0) * (math.min(q.radiusKm * 0.6, 6.0) - 1.2);
    final dLat = distKm / 111.0;
    final cosLat = math.cos(q.center.latitude * math.pi / 180.0).abs();
    final dLon = distKm / (111.0 * (cosLat < 0.01 ? 1.0 : cosLat));
    return LatLng(
      (q.center.latitude + dLat * math.sin(angle)).clamp(-90.0, 90.0),
      (q.center.longitude + dLon * math.cos(angle)).clamp(-180.0, 180.0),
    );
  }

  /// Direct LLM knowledge fallback for destination hotspots when maps or web lack data.
  Future<List<HotspotCandidate>> _fromLlmKnowledge(HotspotQuery q) async {
    final model = llm;
    if (model == null || !model.isConfigured) return const [];
    final dest = q.destination;
    final targetCount = math.max(q.target, 8);
    final styleText = q.style != null ? 'Style: ${q.style!.label}' : '';
    final needsText = [for (final n in AccessRules.relevant(q.needs)) n.label].join(', ');

    final prompt = '''
Destination: $dest
Trip length: ${q.days} day(s), pace: ${q.pace?.label ?? 'balanced'}
$styleText
${needsText.isNotEmpty ? 'Access needs: $needsText' : ''}

You are Bhatkanti, an expert travel guide AI for sustainable and accessible travel.
List $targetCount top, famous sights, viewpoints, natural attractions, cultural heritage sites, and local food spots in and around $dest.
Reply ONLY with valid JSON:
{
  "places": [
    {
      "name": "Exact Name of Attraction",
      "kind": "heritage|nature|culture|religious|food|adventure|viewpoint|shopping|other",
      "why": "One sentence explaining why travellers visit",
      "outdoor": true,
      "feeInr": 0,
      "visitMinutes": 90,
      "trending": false
    }
  ]
}
''';

    try {
      final r = await model.ask(
        AgentKind.bhatkanti,
        [
          const GroqMessage(
            'system',
            'You are Bhatkanti, the hotspot finder of UrbanPulse. Return high-quality, real attractions and landmarks for the destination in JSON.',
          ),
          GroqMessage('user', prompt),
        ],
        tier: LlmTier.heavy,
        json: true,
        maxTokens: 1800,
        timeout: const Duration(seconds: 25),
      );

      if (r is! GroqSuccess) return const [];
      final j = parseLenientObject(r.content);
      final rawPlaces = j?['places'] ?? j?['final']?['places'];
      if (rawPlaces is! List || rawPlaces.isEmpty) return const [];

      final out = <HotspotCandidate>[];
      for (final p in rawPlaces.take(30)) {
        if (p is! Map) continue;
        final name = (p['name'] as String?)?.trim();
        if (name == null || name.isEmpty || name.length > 90) continue;
        final loc = await _locate(name, q);
        if (loc == null) continue;

        final kind = HotspotCandidates.parseKind(p['kind']) ?? HotspotCandidates.kindFromName(name);
        final fee = p['feeInr'] is num ? AiEstimator.intIn(p['feeInr'], 0, 15000) : null;
        final mins = p['visitMinutes'] is num ? AiEstimator.intIn(p['visitMinutes'], 20, 360) : 90;
        final outdoor = p['outdoor'] is bool ? p['outdoor'] as bool : true;

        out.add(
          HotspotCandidate(
            name: name,
            location: loc,
            source: 'AI Knowledge',
            kind: kind,
            why: (p['why'] as String?)?.trim(),
            visitMinutes: mins,
            feeInr: fee,
            feeIsEstimated: fee != null,
            isOutdoor: outdoor,
            isTrending: p['trending'] == true,
            sources: [
              SourceRef(
                title: name,
                url: 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(name)}',
                source: 'AI Guide',
              ),
            ],
          ),
        );
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  // --- enrichment -----------------------------------------------------------

  static final _sightWords = RegExp(
    r'\b(temple|mandir|fort|palace|mahal|museum|garden|gardens|park|falls|waterfall|lake|dam|beach|hill|hills|peak|church|cathedral|mosque|masjid|cave|caves|tomb|monument|memorial|bridge|gate|tower|sanctuary|reserve|viewpoint|point|market|bazaar|ghat|stepwell|baoli|gurudwara|monastery|tea|estate|plantation|island|valley|zoo|aquarium|square|street|lighthouse)\b',
    caseSensitive: false,
  );

  /// Wikipedia confirms popularity for places it knows, and contributes the
  /// sight-like articles nothing else listed.
  void _attachWikipedia(List<HotspotCandidate> merged, List<WikiPage> wiki, HotspotQuery q) {
    for (final w in wiki) {
      if (w.lat == null || w.lon == null) continue;
      final at = LatLng(w.lat!, w.lon!);
      final match = merged.where((c) {
        final km = haversineKm(c.location.latitude, c.location.longitude, at.latitude, at.longitude);
        if (km > 1.2) return false;
        final sim = HotelCandidates.similarity(c.name, w.title);
        return sim >= 0.6 || (c.wikiTitle != null && HotelCandidates.normalize(c.wikiTitle!) == HotelCandidates.normalize(w.title));
      }).firstOrNull;
      final url = w.url ?? 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(w.title.replaceAll(' ', '_'))}';
      if (match != null) {
        match.wikiTitle ??= w.title;
        match.wikiUrl ??= url;
        match.sourceNames.add('Wikipedia');
        if (!match.sources.any((s) => s.url == url)) match.sources.add(SourceRef(title: w.title, url: url, source: 'Wikipedia'));
      } else if (_sightWords.hasMatch(w.title) && w.title.length <= 70) {
        merged.add(
          HotspotCandidate(
            name: w.title,
            location: at,
            source: 'Wikipedia',
            kind: HotspotCandidates.kindFromName(w.title),
            wikiTitle: w.title,
            wikiUrl: url,
            sources: [SourceRef(title: w.title, url: url, source: 'Wikipedia')],
          ),
        );
      }
    }
  }

  Future<void> _addWikipediaText(List<HotspotCandidate> pool) async {
    final targets = [for (final c in pool) if (c.wikiTitle != null && (c.why == null || c.why!.isEmpty)) c].take(12).toList();
    if (targets.isEmpty) return;
    await Future.wait([
      for (final c in targets)
        () async {
          try {
            final page = await wikipedia.summary(c.wikiTitle!);
            final s = HotspotCandidates.firstSentence(page?.extract);
            if (s.isNotEmpty) c.why = s;
            if (page?.url != null) c.wikiUrl ??= page!.url;
          } catch (_) {
            // no summary: the model or a template will write the reason
          }
        }(),
    ]);
  }

  /// Access, hours and other facts read straight from tags.
  void _applyTags(HotspotCandidate c, HotspotQuery q) {
    if (c.tags.isNotEmpty) {
      final src = c.sourceNames.contains('Geoapify') ? 'OpenStreetMap via Geoapify' : 'OpenStreetMap';
      final fromTags = AccessRules.fromOsmTags(c.tags, q.needs, provenance: Provenance(source: src, confidence: 0.75));
      for (final e in fromTags.entries) {
        final prev = c.access[e.key];
        c.access[e.key] = prev == null ? e.value : AccessRules.merge(prev, e.value);
      }
    }
  }

  /// One batched call for the fields nothing real supplied.
  Future<void> _fillWithAi(List<HotspotCandidate> pool, HotspotQuery q, List<String> warnings) async {
    final est = estimator;
    if (est == null || pool.isEmpty) return;
    final items = <String, Map<String, Object?>>{};
    for (final c in pool.take(aiBatch)) {
      items[c.id] = {
        'name': c.name,
        if (c.kind != null) 'kind': c.kind!.name,
        'destination': q.destination,
        if (c.tags['tourism'] != null) 'osmTourism': c.tags['tourism'],
        if (c.wikiTitle != null) 'hasWikipediaArticle': true,
        'knownFeeInr': c.feeInr,
        'estimate': [
          'importance',
          if (c.kind == null) 'kind',
          if (c.visitMinutes == null) 'visitMinutes',
          if (c.feeInr == null) 'feeInr',
          if (c.isOutdoor == null) 'outdoor',
          if (c.why == null || c.why!.isEmpty) 'why',
        ],
      };
    }
    final filled = await est.fillMany(
      agent: AgentKind.bhatkanti,
      subject: 'places to visit in ${q.destination}',
      items: items,
      fields: const {
        'importance': 'number 0 to 1: how essential this is for a first-time visitor to the destination (1 = the iconic sight)',
        'kind': 'one of heritage, nature, culture, religious, food, adventure, viewpoint, shopping, other',
        'visitMinutes': 'typical time spent there in minutes, integer',
        'feeInr': 'typical entry fee per adult in rupees, 0 if free, null if unknown',
        'outdoor': 'true if mostly outdoors, false if mostly indoors',
        'why': 'one plain sentence (under 22 words) on why to visit',
      },
    );
    if (filled == null) {
      warnings.add('The model could not rate the places; ranking uses map and Wikipedia signals only');
      return;
    }
    for (final c in pool) {
      final row = filled[c.id];
      if (row == null) continue;
      final imp = row['importance']?.value;
      if (imp is num) c.importance = imp.toDouble().clamp(0.0, 1.0);
      if (c.kind == null) {
        final k = HotspotCandidates.parseKind(row['kind']?.value);
        if (k != null) {
          c.kind = k;
          c.kindIsEstimated = true;
        }
      }
      c.visitMinutes ??= AiEstimator.intIn(row['visitMinutes']?.value, 15, 480);
      if (c.feeInr == null) {
        final f = AiEstimator.intIn(row['feeInr']?.value, 0, 20000);
        if (f != null) {
          c.feeInr = f;
          c.feeIsEstimated = true;
        }
      }
      if (c.isOutdoor == null && row['outdoor']?.value is bool) c.isOutdoor = row['outdoor']!.value as bool;
      if ((c.why == null || c.why!.isEmpty) && row['why']?.value is String) {
        final w = HotspotCandidates.firstSentence(row['why']!.value as String);
        if (w.isNotEmpty) {
          c.why = w;
          c.whyIsEstimated = true;
        }
      }
    }
  }

  // --- output ---------------------------------------------------------------

  Hotspot _toHotspot(HotspotCandidate c, HotspotQuery q) {
    final kind = c.kind ?? HotspotKind.other;
    final fee = c.feeInr ?? (kind == HotspotKind.food ? 0 : _defaultFee(kind));
    final feeEstimated = c.feeInr == null || c.feeIsEstimated;
    final base = HotspotCandidates.baseScore(c, q.center, q.radiusKm);
    final score = (c.importance == null ? base : 0.5 * base + 0.5 * c.importance!).clamp(0.0, 1.0);
    final provenance = HotspotCandidates.provenanceOf(c);
    final why = (c.why != null && c.why!.isNotEmpty) ? c.why! : _templateWhy(c, kind, q.destination);
    // Every requested need is present, even if only as "unknown".
    final fixed = <AccessibilityNeed, NeedSupport>{
      for (final n in AccessRules.relevant(q.needs))
        n: c.access[n] ??
            NeedSupport(
              need: n,
              level: SupportLevel.unknown,
              detail: 'No information found',
              provenance: const Provenance(source: 'none', confidence: 0),
            ),
    };
    return Hotspot(
      id: c.id,
      name: c.name,
      location: c.location,
      kind: c.isTrending && kind == HotspotKind.other ? HotspotKind.trending : kind,
      why: why,
      visitMinutes: c.visitMinutes ?? HotspotCandidates.defaultVisitMinutes(kind),
      feeInr: fee,
      openingHours: c.openingHours,
      isOutdoor: c.isOutdoor ?? HotspotCandidates.defaultOutdoor(kind),
      isTrending: c.isTrending,
      score: score,
      access: fixed,
      claims: const [],
      sources: c.sources,
      provenance: feeEstimated && c.sourceNames.length == 1 && c.sourceNames.first == 'AI estimate' ? Provenance.aiEstimate : provenance,
    );
  }

  static int _defaultFee(HotspotKind k) => switch (k) {
    HotspotKind.nature || HotspotKind.viewpoint || HotspotKind.religious || HotspotKind.shopping || HotspotKind.food => 0,
    HotspotKind.adventure => RegionalDefaults.entryFeeInr(CostTier.mid) * 3,
    _ => RegionalDefaults.entryFeeInr(CostTier.mid),
  };

  static String _templateWhy(HotspotCandidate c, HotspotKind k, String destination) => switch (k) {
    HotspotKind.heritage => 'A heritage site in $destination.',
    HotspotKind.nature => 'A natural spot around $destination.',
    HotspotKind.culture => 'A cultural stop in $destination.',
    HotspotKind.religious => 'A place of worship worth a visit in $destination.',
    HotspotKind.food => 'A local place to eat in $destination.',
    HotspotKind.adventure => 'An active outing near $destination.',
    HotspotKind.viewpoint => 'A viewpoint over $destination.',
    HotspotKind.shopping => 'A local market or shopping stop in $destination.',
    HotspotKind.trending => 'A newly popular place in $destination.',
    HotspotKind.other => 'A place to see in $destination.',
  };
}

class _WebPlace {
  const _WebPlace({required this.name, this.kind, this.why, this.trending = false, this.url, this.fee, this.minutes, this.outdoor});

  final String name;
  final HotspotKind? kind;
  final String? why;
  final bool trending;
  final String? url;
  final int? fee;
  final int? minutes;
  final bool? outdoor;
}
