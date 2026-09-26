import 'dart:async';

import 'package:latlong2/latlong.dart';

import '../../domain/access/access_rules.dart';
import '../../domain/regional_defaults.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../services/data/ai_estimator.dart';
import '../../services/data/geoapify_client.dart';
import '../../services/data/http_util.dart';
import '../../services/data/location_key_resolver.dart';
import '../../services/data/overpass_client.dart';
import '../../services/data/xotelo_client.dart';
import '../runtime/agent_kind.dart';
import '../runtime/llm_pool.dart';
import '../runtime/report.dart';
import '../tools/agent_tool.dart';
import '../tools/fetch_page_tool.dart';
import '../tools/tool_loop.dart';
import 'hotel_candidate.dart';

/// What Atithi is asked to find.
class HotelQuery {
  const HotelQuery({
    required this.destination,
    required this.center,
    required this.checkIn,
    required this.checkOut,
    this.rooms = 1,
    this.adults = 2,
    this.needs = const {},
    this.nightlyCapInr,
    this.radiusKm = 10,
    this.preferEco = false,
    this.notes,
  });

  final String destination;
  final LatLng center;
  final DateTime checkIn;
  final DateTime checkOut;
  final int rooms;

  /// Grown-ups across all rooms (Xotelo prices per guest count).
  final int adults;
  final Set<AccessibilityNeed> needs;

  /// The most the traveller wants to pay per room per night.
  final int? nightlyCapInr;
  final double radiusKm;
  final bool preferEco;

  /// Free-text preferences for the web search ("homestay", "near the tea gardens").
  final String? notes;

  int get nights {
    final d = DateTime(checkOut.year, checkOut.month, checkOut.day)
        .difference(DateTime(checkIn.year, checkIn.month, checkIn.day))
        .inDays;
    return d < 1 ? 1 : d;
  }

  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  HotelQuery copyWith({int? nightlyCapInr, double? radiusKm, Set<AccessibilityNeed>? needs, bool clearCap = false}) => HotelQuery(
    destination: destination,
    center: center,
    checkIn: checkIn,
    checkOut: checkOut,
    rooms: rooms,
    adults: adults,
    needs: needs ?? this.needs,
    nightlyCapInr: clearCap ? null : (nightlyCapInr ?? this.nightlyCapInr),
    radiusKm: radiusKm ?? this.radiusKm,
    preferEco: preferEco,
    notes: notes,
  );
}

class HotelSearchResult {
  const HotelSearchResult({
    required this.query,
    required this.options,
    this.considered = 0,
    this.sources = const [],
    this.warnings = const [],
    this.location,
    this.dateBand,
    this.cheapDates = const [],
  });

  final HotelQuery query;

  /// Best fit first.
  final List<HotelOption> options;

  /// How many distinct hotels were looked at before shortlisting.
  final int considered;

  /// The data sources that actually contributed.
  final List<String> sources;
  final List<String> warnings;
  final ResolvedLocation? location;

  /// "cheap" | "average" | "high" for the check-in date, from Xotelo's heatmap.
  final String? dateBand;

  /// Nearby dates Xotelo marks as cheap (ISO), for a "shift a day" suggestion.
  final List<String> cheapDates;

  bool get isEmpty => options.isEmpty;

  /// The same search with [options] replaced (after verification) and any
  /// [extraSources] noted.
  HotelSearchResult copyWith({List<HotelOption>? options, List<String>? extraSources}) => HotelSearchResult(
    query: query,
    options: options ?? this.options,
    considered: considered,
    sources: [...sources, ...?extraSources?.where((s) => !sources.contains(s))],
    warnings: warnings,
    location: location,
    dateBand: dateBand,
    cheapDates: cheapDates,
  );
}

typedef HotelProgress = void Function(String text, {String? why});

/// Atithi's engine: finds, merges, ranks and enriches hotels for a stay.
///
/// Real data first (Xotelo for hotels and live prices, Geoapify and
/// OpenStreetMap for positions and accessibility tags, a `web_search` tool loop
/// for area- and need-specific finds, listing pages for amenities). Anything
/// still missing is filled by the model and labelled as an estimate. Every
/// source can fail; the finder returns whatever the others produced.
class HotelFinder {
  HotelFinder({
    required this.resolver,
    required this.xotelo,
    required this.overpass,
    this.geoapify,
    this.tools,
    this.llm,
    this.estimator,
    this.fetchPage,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final LocationKeyResolver resolver;
  final XoteloClient xotelo;
  final GeoapifyClient? geoapify;
  final OverpassClient overpass;
  final ToolRegistry? tools;
  final AgentLlm? llm;
  final AiEstimator? estimator;
  final FetchPageTool? fetchPage;
  // ignore: unused_field
  final DateTime Function() _now;

  static const shortlistSize = 12;
  static const rateLookups = 6;
  static const pagesToRead = 3;
  static const maxOptions = 8;

  Future<HotelSearchResult> find(
    HotelQuery q, {
    HotelProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    final warnings = <String>[];
    final used = <String>{};
    bool degraded() => isCancelled?.call() ?? false;

    // 1. Gather candidates from every source at once.
    // (All three start now and run concurrently; awaiting them in turn only
    // collects the results.)
    final xoteloF = _guard<_XoteloPart, _XoteloPart>(() => _fromXotelo(q, warnings), (r) => r, warnings, 'Xotelo');
    final geoF = _guard<List<HotelCandidate>, List<HotelCandidate>>(() => _fromGeoapify(q), (r) => r, warnings, 'Geoapify');
    final osmF = _guard<List<HotelCandidate>, List<HotelCandidate>>(() => _fromOverpass(q), (r) => r, warnings, 'OpenStreetMap');
    final xoteloPart = await xoteloF;
    final geoCandidates = await geoF ?? const <HotelCandidate>[];
    final osmCandidates = await osmF ?? const <HotelCandidate>[];
    final xoteloCandidates = xoteloPart?.candidates ?? const <HotelCandidate>[];
    if (xoteloCandidates.isNotEmpty) used.add('Xotelo');
    if (geoCandidates.isNotEmpty) used.add('Geoapify');
    if (osmCandidates.isNotEmpty) used.add('OpenStreetMap');
    onProgress?.call(
      'found ${xoteloCandidates.length + geoCandidates.length + osmCandidates.length} hotel listings',
      why: 'Hotels come from several sources at once (TripAdvisor prices, OpenStreetMap, Geoapify) so no single gap hides a good option.',
    );

    // Nothing far from the centre belongs in the list, whichever source sent it.
    final reach = q.radiusKm * 3 < 25 ? 25.0 : q.radiusKm * 3;
    bool inReach(HotelCandidate c) =>
        c.location == null || haversineKm(q.center.latitude, q.center.longitude, c.location!.latitude, c.location!.longitude) <= reach;
    var merged = HotelCandidates.merge([...xoteloCandidates, ...geoCandidates, ...osmCandidates].where(inReach).toList());

    // 2. A targeted web search when the data is thin or the group has needs.
    final web = degraded() ? null : await _guard(() => _fromWeb(q, merged), (r) => r, warnings, 'web search');
    if (web != null && web.isNotEmpty) {
      used.add('Web search');
      merged = HotelCandidates.merge([...merged, ...web]);
      onProgress?.call(
        'searched the web for ${q.needs.any((n) => n != AccessibilityNeed.none) ? 'hotels that suit your access needs' : 'more hotels'} and added ${web.length}',
        why: 'The listings were thin for this area, so Atithi searched the web for places that match what you asked for.',
      );
    }

    // 3. Accessibility from tags, then rank and shortlist.
    for (final c in merged) {
      if (c.tags.isNotEmpty) {
        final src = c.sources.any((s) => s.source.contains('Geoapify')) ? 'OpenStreetMap via Geoapify' : 'OpenStreetMap';
        final fromTags = AccessRules.fromOsmTags(c.tags, q.needs, provenance: Provenance(source: src, confidence: 0.75));
        for (final e in fromTags.entries) {
          final prev = c.access[e.key];
          c.access[e.key] = prev == null ? e.value : AccessRules.merge(prev, e.value);
        }
      }
    }
    double score(HotelCandidate c) => HotelCandidates.fit(
      c,
      needs: q.needs,
      nightlyCapInr: q.nightlyCapInr,
      center: q.center,
      preferEco: q.preferEco,
    );
    merged.sort((a, b) => score(b).compareTo(score(a)));
    final considered = merged.length;
    final shortlist = merged.take(shortlistSize).toList();

    // 4. Enrich the shortlist: live rates, price band, listing pages.
    await Future.wait([
      _addRates(shortlist, q, warnings, used),
      _addPages(shortlist, q, warnings, used, skip: degraded()),
    ]);
    final heat = await _guard(() => _heatmap(shortlist, q), (r) => r, warnings, 'price heatmap');

    // 5. Fill what is still unknown with the model, labelled.
    if (!degraded()) {
      await _guard(() => _fillWithAi(shortlist, q), (_) => null, warnings, 'AI estimates');
    }
    for (final c in shortlist) {
      if (c.nightlyInr == null) {
        c.nightlyInr = RegionalDefaults.hotelNightlyInr(_tierFor(c));
        c.priceIsEstimated = true;
        c.sources.add(const Provenance(source: 'Regional average', isEstimated: true, confidence: 0.25));
      }
    }

    // 6. Final order and shape.
    shortlist.sort((a, b) => score(b).compareTo(score(a)));
    final options = [for (final c in shortlist.take(maxOptions)) _toOption(c, q, heat?.band)];
    if (options.any((o) => o.priceIsEstimated)) used.add('AI or regional estimate');

    return HotelSearchResult(
      query: q,
      options: options,
      considered: considered,
      sources: used.toList(),
      warnings: warnings,
      location: xoteloPart?.location,
      dateBand: heat?.band,
      cheapDates: heat?.cheapDates ?? const [],
    );
  }

  /// Runs a source; on any failure records a warning and yields null.
  Future<T?> _guard<R, T>(
    Future<R> Function() run,
    T Function(R) pick,
    List<String> warnings,
    String label,
  ) async {
    try {
      return pick(await run());
    } catch (e) {
      warnings.add('$label was unavailable');
      return null;
    }
  }

  // --- sources --------------------------------------------------------------

  Future<_XoteloPart> _fromXotelo(HotelQuery q, List<String> warnings) async {
    final loc = await resolver.resolve(q.destination, center: q.center);
    if (loc == null) {
      warnings.add('This destination was not found on TripAdvisor, so live hotel prices are not available');
      return const _XoteloPart(null, []);
    }
    final list = await xotelo.list(loc.key, limit: 60);
    if (list == null) {
      warnings.add('Xotelo returned no hotels');
      return _XoteloPart(loc, const []);
    }
    final reach = q.radiusKm * 3 < 25 ? 25.0 : q.radiusKm * 3;
    final nearby = [
      for (final h in list.hotels)
        if (h.hasLocation && haversineKm(q.center.latitude, q.center.longitude, h.lat!, h.lng!) <= reach) h,
    ]..sort((a, b) => haversineKm(q.center.latitude, q.center.longitude, a.lat!, a.lng!)
        .compareTo(haversineKm(q.center.latitude, q.center.longitude, b.lat!, b.lng!)));
    final candidates = <HotelCandidate>[];
    for (final h in nearby.take(30)) {
      final price = h.approxNightlyInr;
      candidates.add(
        HotelCandidate(
          name: h.name,
          source: 'Xotelo',
          location: LatLng(h.lat!, h.lng!),
          type: h.type,
          rating: h.rating,
          reviewCount: h.reviewCount,
          nightlyInr: price == null ? null : ((price.$1 + price.$2) / 2).round(),
          priceIsEstimated: true,
          xoteloKey: h.key,
          tripAdvisorUrl: h.url,
          imageUrl: h.image,
          labels: h.labels,
          sources: [Provenance(source: 'Xotelo (TripAdvisor)', url: h.url, confidence: 0.85)],
        ),
      );
    }
    return _XoteloPart(loc, candidates);
  }

  Future<List<HotelCandidate>> _fromGeoapify(HotelQuery q) async {
    final g = geoapify;
    if (g == null || !g.isConfigured) return const [];
    final wantsAccess = q.needs.any(
      (n) => n == AccessibilityNeed.wheelchair || n == AccessibilityNeed.limitedMobility || n == AccessibilityNeed.elderlyCare,
    );
    final radius = (q.radiusKm * 1000).round();
    final results = await Future.wait([
      g.places(categories: GeoapifyClient.hotelCategories, lat: q.center.latitude, lon: q.center.longitude, radiusM: radius, limit: 30),
      if (wantsAccess)
        g.places(
          categories: GeoapifyClient.hotelCategories,
          lat: q.center.latitude,
          lon: q.center.longitude,
          radiusM: radius,
          limit: 20,
          wheelchairOnly: true,
        ),
    ]);
    final out = <HotelCandidate>[];
    final seen = <String>{};
    for (final list in results) {
      for (final p in list ?? const <GeoPlace>[]) {
        if (!seen.add(p.id)) continue;
        out.add(_fromGeoPlace(p));
      }
    }
    return out;
  }

  static HotelCandidate _fromGeoPlace(GeoPlace p) => HotelCandidate(
    name: p.name,
    source: 'Geoapify',
    location: LatLng(p.lat, p.lon),
    address: p.address,
    type: _typeFrom(p.categories, p.tags['tourism']),
    website: p.website,
    phone: p.phone,
    stars: int.tryParse(p.tags['stars'] ?? ''),
    geoapifyId: p.id,
    tags: p.tags,
    sources: [Provenance(source: 'Geoapify', confidence: 0.8)],
  );

  Future<List<HotelCandidate>> _fromOverpass(HotelQuery q) async {
    final places = await overpass.hotelsAround(q.center.latitude, q.center.longitude, radiusM: (q.radiusKm * 1000).round());
    if (places == null) return const [];
    return [
      for (final p in places)
        HotelCandidate(
          name: p.name,
          source: 'OpenStreetMap',
          location: LatLng(p.lat, p.lon),
          type: _typeFrom(const [], p.tags['tourism']),
          website: p.website,
          phone: p.phone,
          stars: int.tryParse(p.tags['stars'] ?? ''),
          osmId: p.id,
          tags: p.tags,
          sources: [Provenance(source: 'OpenStreetMap', url: 'https://www.openstreetmap.org/${p.id}', confidence: 0.75)],
        ),
    ];
  }

  static String _typeFrom(List<String> categories, String? tourism) {
    final t = (tourism ?? '').toLowerCase();
    final joined = categories.join(' ').toLowerCase();
    String has(String w) => (t.contains(w) || joined.contains(w)) ? w : '';
    if (has('hostel').isNotEmpty) return 'Hostel';
    if (has('guest_house').isNotEmpty) return 'Guest house';
    if (has('apartment').isNotEmpty) return 'Apartment';
    if (has('resort').isNotEmpty) return 'Resort';
    if (has('motel').isNotEmpty) return 'Motel';
    if (has('chalet').isNotEmpty || has('hut').isNotEmpty) return 'Cottage';
    return 'Hotel';
  }

  /// The model-driven `web_search` loop: area- and need-specific hotel finds.
  Future<List<HotelCandidate>> _fromWeb(HotelQuery q, List<HotelCandidate> known) async {
    final registry = tools;
    final model = llm;
    if (registry == null || model == null || !model.isConfigured || !registry.has('web_search')) return const [];
    final wantsNeeds = AccessRules.relevant(q.needs).isNotEmpty;
    if (!wantsNeeds && known.length >= 8) return const [];

    final needsText = [for (final n in AccessRules.relevant(q.needs)) n.label].join(', ');
    final cap = q.nightlyCapInr;
    final fallbackQueries = <Map<String, Object?>>[
      {'tool': 'web_search', 'args': {'query': 'best hotels in ${q.destination}${cap == null ? '' : ' under ₹$cap per night'}'}},
      if (wantsNeeds)
        {'tool': 'web_search', 'args': {'query': '${q.destination} hotels for guests with $needsText accessible rooms'}},
    ];

    final loop = ToolLoop(llm: model, tools: registry, maxCalls: 2);
    final r = await loop.run(
      agent: AgentKind.atithi,
      system:
          'You are Atithi, the hotel finder of a sustainable, accessibility-first '
          'trip planner. Use web_search to find real hotels or homestays that '
          'suit this trip, especially ones that fit the group\'s access needs. '
          'Only report hotels the search results actually mention. Reply with '
          '{"final": {"hotels": [{"name": "...", "area": "...", "why": "one '
          'sentence", "url": "the result URL", "priceHintInr": null or a number '
          'per night, "accessibilityClaims": ["what the source says about access"]}]}}. '
          'Never invent names or URLs; an empty list is fine.',
      context: [
        'Destination: ${q.destination}',
        'Nights: ${q.nights} (${HotelQuery.iso(q.checkIn)} to ${HotelQuery.iso(q.checkOut)})',
        'Rooms: ${q.rooms}, adults: ${q.adults}',
        if (cap != null) 'Budget: up to ₹$cap per room per night',
        if (needsText.isNotEmpty) 'Access needs: $needsText',
        if (q.notes != null) 'Preferences: ${q.notes}',
        'Already found: ${known.take(12).map((c) => c.name).join('; ')}',
      ].join('\n'),
      allowedTools: const ['web_search'],
      fallbackCalls: fallbackQueries,
      tier: LlmTier.light,
      timeout: const Duration(seconds: 14),
    );

    final hotels = r.finalJson?['hotels'];
    if (hotels is! List) return const [];
    final out = <HotelCandidate>[];
    for (final h in hotels.take(8)) {
      if (h is! Map) continue;
      final name = (h['name'] as String?)?.trim();
      if (name == null || name.isEmpty || name.length > 90) continue;
      final url = h['url'] as String?;
      final claims = [
        for (final c in (h['accessibilityClaims'] as List<dynamic>? ?? const []))
          if (c is String && c.trim().isNotEmpty) c.trim(),
      ];
      final where = await _locate(name, q);
      final hint = h['priceHintInr'];
      final c = HotelCandidate(
        name: name,
        source: 'web search',
        location: where,
        address: h['area'] as String?,
        nightlyInr: hint is num ? AiEstimator.intIn(hint, 300, 200000) : null,
        priceIsEstimated: true,
        website: url,
        claims: claims,
        sources: [
          Provenance(source: 'Web search', url: url, confidence: 0.55),
        ],
      );
      // What the source says about access becomes evidence, not a verified fact.
      if (claims.isNotEmpty) {
        final text = claims.join('. ');
        c.access.addAll(
          AccessRules.fromText(text, q.needs, provenance: Provenance(source: 'Web search', url: url, confidence: 0.5)),
        );
      }
      out.add(c);
    }
    return out;
  }

  /// Puts a web-found hotel on the map: OpenStreetMap by name, else Geoapify.
  /// The result must be near the destination or it is discarded.
  Future<LatLng?> _locate(String name, HotelQuery q) async {
    try {
      final osm = await overpass.byName(name, q.center.latitude, q.center.longitude, radiusM: 15000);
      final hit = osm?.where((p) => haversineKm(q.center.latitude, q.center.longitude, p.lat, p.lon) <= 30).firstOrNull;
      if (hit != null) return LatLng(hit.lat, hit.lon);
      final g = geoapify;
      if (g != null && g.isConfigured) {
        final c = await g.geocode('$name, ${q.destination}', limit: 1);
        final first = c?.firstOrNull;
        if (first != null && haversineKm(q.center.latitude, q.center.longitude, first.lat, first.lon) <= 30) {
          return LatLng(first.lat, first.lon);
        }
      }
    } catch (_) {
      // an unlocated hotel is still listed, just without a pin
    }
    return null;
  }

  // --- enrichment -----------------------------------------------------------

  Future<void> _addRates(List<HotelCandidate> shortlist, HotelQuery q, List<String> warnings, Set<String> used) async {
    final targets = shortlist.where((c) => c.xoteloKey != null).take(rateLookups).toList();
    if (targets.isEmpty) return;
    final results = await Future.wait([
      for (final c in targets)
        xotelo
            .rates(
              c.xoteloKey!,
              checkIn: HotelQuery.iso(q.checkIn),
              checkOut: HotelQuery.iso(q.checkOut),
              rooms: q.rooms,
              adults: q.adults.clamp(1, 32),
            )
            .catchError((_) => null),
    ]);
    var live = 0;
    for (var i = 0; i < targets.length; i++) {
      final cheapest = results[i]?.cheapest;
      if (cheapest == null) continue;
      final c = targets[i];
      c.totalStayInr = cheapest.rate;
      c.cheapestOta = cheapest.name;
      c.nightlyInr = (cheapest.rate / q.nights / q.rooms).round();
      c.priceIsEstimated = false;
      c.bookingUrl = c.tripAdvisorUrl;
      c.sources.add(Provenance(source: 'Live rate via ${cheapest.name}', url: c.tripAdvisorUrl, confidence: 0.95));
      live++;
    }
    if (live > 0) used.add('Xotelo live rates');
    if (live == 0) warnings.add('Live prices were not available; prices are estimates');
  }

  Future<void> _addPages(List<HotelCandidate> shortlist, HotelQuery q, List<String> warnings, Set<String> used, {required bool skip}) async {
    final page = fetchPage;
    if (skip || page == null) return;
    // With access needs the listing text is the best evidence there is, so read more of them.
    final count = AccessRules.relevant(q.needs).isEmpty ? pagesToRead : pagesToRead * 2;
    final targets = shortlist.where((c) => c.tripAdvisorUrl != null).take(count).toList();
    if (targets.isEmpty) return;
    final outs = await Future.wait([
      for (final c in targets) page.run({'url': c.tripAdvisorUrl}, caller: AgentKind.atithi).catchError((_) => ToolOutput.failure('fetch failed')),
    ]);
    var read = 0;
    for (var i = 0; i < targets.length; i++) {
      final out = outs[i];
      if (!out.ok || out.data is! String) continue;
      read++;
      final c = targets[i];
      final text = out.data as String;
      final prov = Provenance(source: 'TripAdvisor listing', url: c.tripAdvisorUrl, confidence: 0.6);
      for (final e in AccessRules.fromText(text, q.needs, provenance: prov).entries) {
        final prev = c.access[e.key];
        c.access[e.key] = prev == null ? e.value : AccessRules.merge(prev, e.value);
        if (e.value.level != SupportLevel.unknown && e.value.detail.isNotEmpty) c.claims.add(e.value.detail);
      }
      for (final a in HotelCandidates.amenitiesIn(text)) {
        if (!c.amenities.contains(a)) c.amenities.add(a);
      }
    }
    if (read > 0) used.add('TripAdvisor listings');
  }

  Future<({String? band, List<String> cheapDates})?> _heatmap(List<HotelCandidate> shortlist, HotelQuery q) async {
    final top = shortlist.where((c) => c.xoteloKey != null).firstOrNull;
    if (top == null) return null;
    final hm = await xotelo.heatmap(top.xoteloKey!, checkOut: HotelQuery.iso(q.checkOut));
    if (hm == null) return null;
    final from = q.checkIn.subtract(const Duration(days: 3));
    final to = q.checkIn.add(const Duration(days: 3));
    final cheap = [
      for (final d in hm.cheap)
        if (DateTime.tryParse(d) case final dt? when !dt.isBefore(from) && !dt.isAfter(to)) d,
    ]..sort();
    return (band: hm.bandFor(HotelQuery.iso(q.checkIn)), cheapDates: cheap);
  }

  /// One batched model call for what nothing real could tell us: a price for
  /// hotels with none, and a cautious read on needs still unknown.
  Future<void> _fillWithAi(List<HotelCandidate> shortlist, HotelQuery q) async {
    final est = estimator;
    if (est == null) return;
    final wanted = AccessRules.relevant(q.needs);
    final items = <String, Map<String, Object?>>{};
    final fields = <String, String>{'nightlyInr': 'typical price of a double room per night in rupees as an integer, or null'};
    for (final n in wanted) {
      fields['access_${n.name}'] =
          'does a property like this realistically suit "${n.label}"? one of yes, partial, no, unknown; '
          'say unknown unless you have a real basis';
    }
    for (final c in shortlist.take(shortlistSize)) {
      final unknownNeeds = [for (final n in wanted) if ((c.access[n]?.level ?? SupportLevel.unknown) == SupportLevel.unknown) n];
      final needsPrice = c.nightlyInr == null;
      if (!needsPrice && unknownNeeds.isEmpty) continue;
      items[c.id] = {
        'name': c.name,
        'type': c.type,
        if (c.rating != null) 'rating': c.rating,
        if (c.address != null) 'address': c.address,
        'destination': q.destination,
        'amenities': c.amenities,
        'estimate': [if (needsPrice) 'nightlyInr', for (final n in unknownNeeds) 'access_${n.name}'],
      };
    }
    if (items.isEmpty) return;

    final filled = await est.fillMany(
      agent: AgentKind.atithi,
      subject: 'hotels in ${q.destination}',
      items: items,
      fields: fields,
    );
    if (filled == null) return;
    for (final c in shortlist) {
      final row = filled[c.id];
      if (row == null) continue;
      if (c.nightlyInr == null) {
        final p = AiEstimator.intIn(row['nightlyInr']?.value, 300, 200000);
        if (p != null) {
          c.nightlyInr = p;
          c.priceIsEstimated = true;
          c.sources.add(Provenance.aiEstimate);
        }
      }
      for (final n in wanted) {
        final raw = row['access_${n.name}']?.value;
        if (raw is! String) continue;
        if ((c.access[n]?.level ?? SupportLevel.unknown) != SupportLevel.unknown) continue;
        var level = switch (raw.toLowerCase().trim()) {
          'yes' => SupportLevel.yes,
          'partial' => SupportLevel.partial,
          'no' => SupportLevel.no,
          _ => SupportLevel.unknown,
        };
        if (level == SupportLevel.unknown) continue;
        // A model's "yes" without evidence is never presented as confirmed.
        if (level == SupportLevel.yes) level = SupportLevel.partial;
        c.access[n] = NeedSupport(
          need: n,
          level: level,
          detail: 'Estimated from the type of property; not verified. Confirm with the hotel before booking.',
          provenance: Provenance.aiEstimate,
        );
      }
    }
  }

  CostTier _tierFor(HotelCandidate c) {
    final t = c.type.toLowerCase();
    if (t.contains('hostel')) return CostTier.budget;
    if (t.contains('resort')) return CostTier.premium;
    final stars = c.stars ?? 0;
    if (stars >= 5) return CostTier.premium;
    if (stars > 0 && stars <= 2) return CostTier.budget;
    return CostTier.mid;
  }

  // --- output ---------------------------------------------------------------

  HotelOption _toOption(HotelCandidate c, HotelQuery q, String? band) {
    final wanted = AccessRules.relevant(q.needs);
    // Every requested need is present, even if only as "unknown".
    final access = <AccessibilityNeed, NeedSupport>{
      for (final n in wanted)
        n: c.access[n] ?? NeedSupport(need: n, level: SupportLevel.unknown, detail: 'No information found', provenance: const Provenance(source: 'none', confidence: 0)),
    };
    final url = c.tripAdvisorUrl ?? c.website;
    final km = c.location == null
        ? null
        : double.parse(haversineKm(q.center.latitude, q.center.longitude, c.location!.latitude, c.location!.longitude).toStringAsFixed(1));
    final provenance = c.sources.firstWhere((s) => !s.isEstimated, orElse: () => c.sources.first);

    return HotelOption(
      id: c.id,
      name: c.name,
      location: c.location,
      address: c.address,
      type: c.type,
      rating: c.rating,
      reviewCount: c.reviewCount,
      nightlyInr: c.nightlyInr,
      totalStayInr: c.totalStayInr ?? (c.nightlyInr == null ? null : c.nightlyInr! * q.nights * q.rooms),
      priceIsEstimated: c.priceIsEstimated,
      cheapestOta: c.cheapestOta,
      bookingUrl: c.bookingUrl ?? url,
      tripAdvisorUrl: c.tripAdvisorUrl,
      imageUrl: c.imageUrl,
      access: access,
      amenities: c.amenities,
      claims: [
        for (final text in c.claims.toSet().take(6))
          Claim(text: text, sources: [if (url != null) SourceRef(title: 'Listing', url: url, source: provenance.source)]),
      ],
      distanceToCenterKm: km,
      ecoScore: HotelCandidates.ecoScore(c),
      labels: c.labels,
      priceBand: band,
      provenance: provenance,
    );
  }
}

class _XoteloPart {
  const _XoteloPart(this.location, this.candidates);

  final ResolvedLocation? location;
  final List<HotelCandidate> candidates;
}
