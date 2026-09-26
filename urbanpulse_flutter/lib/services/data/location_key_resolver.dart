import 'dart:async';
import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../agents/runtime/agent_kind.dart';
import '../../agents/runtime/llm_pool.dart';
import '../../agents/tools/web_search_tool.dart';
import 'data_cache.dart';
import 'http_util.dart';
import 'xotelo_client.dart';

/// A TripAdvisor location that was checked against the real destination.
class ResolvedLocation {
  const ResolvedLocation({
    required this.key,
    required this.center,
    required this.source,
    this.checkedHotels = 0,
    this.nearHotels = 0,
  });

  /// TripAdvisor location key, e.g. `g293916`.
  final String key;
  final LatLng center;

  /// Where the key came from: `cache`, `xotelo search`, `web search`, `ai guess`.
  final String source;
  final int checkedHotels;
  final int nearHotels;

  Map<String, dynamic> toJson() => {
    'key': key,
    'lat': center.latitude,
    'lng': center.longitude,
    'source': source,
    'checked': checkedHotels,
    'near': nearHotels,
  };

  static ResolvedLocation? fromJson(Object? j) {
    if (j is! Map<String, dynamic> || j['key'] is! String) return null;
    final lat = asDouble(j['lat']);
    final lng = asDouble(j['lng']);
    if (lat == null || lng == null) return null;
    return ResolvedLocation(
      key: j['key'] as String,
      center: LatLng(lat, lng),
      source: (j['source'] as String?) ?? 'cache',
      checkedHotels: asInt(j['checked']) ?? 0,
      nearHotels: asInt(j['near']) ?? 0,
    );
  }
}

/// Finds the TripAdvisor `location_key` Xotelo needs for any destination.
///
/// Xotelo's `/list`, `/rates` and `/heatmap` need a key like `g293916`, but its
/// `/search` (the only way to look one up) requires a RapidAPI key. So keys come
/// from, in order: the cache, Xotelo search (if a key is set), a web search whose
/// results link to TripAdvisor pages (their URLs contain the key), and finally a
/// language model's guess.
///
/// **Every candidate is validated** before it is trusted: its hotels must sit
/// near the destination's coordinates. A wrong key is otherwise silent and
/// disastrous: a guessed key for Munnar really did return Bengaluru hotels.
class LocationKeyResolver {
  LocationKeyResolver({
    required this.xotelo,
    required this.geocode,
    this.llm,
    this.search,
    DataCache? cache,
    this.maxKm = 60,
    this.minHotels = 3,
    this.nearFraction = 0.6,
  }) : _cache = cache ?? MemoryCache();

  final XoteloClient xotelo;

  /// Destination text -> coordinates (the app's geocoder).
  final Future<LatLng?> Function(String place) geocode;
  final AgentLlm? llm;
  final WebSearchTool? search;
  final DataCache _cache;

  /// How close the hotels must be to the destination centre.
  final double maxKm;

  /// The fewest hotels with coordinates a key must return to be believed.
  final int minHotels;

  /// The share of those hotels that must be within [maxKm].
  final double nearFraction;

  /// `-g293916-` in a TripAdvisor URL (also `Hotels-g293916-Bangkok…`).
  static final _urlKey = RegExp(r'[-/_]g(\d{3,9})(?=[-._/]|$)');

  /// A bare key in text ("g293916").
  static final _bareKey = RegExp(r'\bg(\d{3,9})\b');

  /// Every distinct TripAdvisor key mentioned in [text], in order.
  static List<String> extractKeys(String text) {
    final seen = <String>{};
    for (final m in _urlKey.allMatches(text)) {
      seen.add('g${m.group(1)}');
    }
    for (final m in _bareKey.allMatches(text)) {
      seen.add('g${m.group(1)}');
    }
    return seen.toList();
  }

  Future<ResolvedLocation?> resolve(String destination, {LatLng? center}) async {
    final name = destination.trim();
    if (name.isEmpty) return null;
    final cacheKey = 'xotelo.loc.${name.toLowerCase()}';

    final hit = await _cache.get(cacheKey);
    if (hit != null) {
      try {
        final decoded = jsonDecode(hit);
        if (decoded is Map<String, dynamic> && decoded['none'] == true) return null;
        final r = ResolvedLocation.fromJson(decoded);
        if (r != null) {
          return ResolvedLocation(
            key: r.key,
            center: r.center,
            source: 'cache',
            checkedHotels: r.checkedHotels,
            nearHotels: r.nearHotels,
          );
        }
      } catch (_) {
        // corrupt entry: resolve again
      }
    }

    final where = center ?? await geocode(name);
    // Without coordinates there is nothing to validate against.
    if (where == null) return null;

    final result = await _resolveWithin(name, where);
    if (result != null) {
      await _cache.put(cacheKey, jsonEncode(result.toJson()), ttl: const Duration(days: 30));
    } else {
      // A short negative cache so a place TripAdvisor lacks is not retried (and
      // its credits spent) on every plan.
      await _cache.put(cacheKey, jsonEncode({'none': true}), ttl: const Duration(hours: 12));
    }
    return result;
  }

  Future<ResolvedLocation?> _resolveWithin(String name, LatLng where) async {
    // Cheap sources in parallel; the model's guess only if they fail.
    final fromSearch = _viaXoteloSearch(name);
    final fromWeb = _viaWebSearch(name);
    final gathered = await Future.wait([fromSearch, fromWeb]);

    final candidates = <(String, String)>[];
    void add(List<String> keys, String source) {
      for (final k in keys) {
        if (!candidates.any((c) => c.$1 == k)) candidates.add((k, source));
      }
    }

    add(await Future.value(gathered[0]), 'xotelo search');
    add(gathered[1], 'web search');

    final found = await _firstValid(candidates.take(4).toList(), where);
    if (found != null) return found;

    final guesses = await _viaModel(name);
    return _firstValid([for (final k in guesses.take(4)) if (!candidates.any((c) => c.$1 == k)) (k, 'ai guess')], where);
  }

  Future<List<String>> _viaXoteloSearch(String name) async {
    final places = await xotelo.search(name);
    if (places == null) return const [];
    // Location keys only (a hotel key contains "-d").
    return [
      for (final p in places)
        if (!p.isHotel && RegExp(r'^g\d+$').hasMatch(p.key)) p.key,
    ];
  }

  Future<List<String>> _viaWebSearch(String name) async {
    final tool = search;
    if (tool == null) return const [];
    final out = await tool.run({'query': 'TripAdvisor hotels in $name', 'max_results': 6}, caller: AgentKind.atithi);
    if (!out.ok || out.data is! List<SearchResult>) return const [];
    final keys = <String>[];
    for (final r in out.data as List<SearchResult>) {
      // Only TripAdvisor URLs carry a meaningful key.
      final tripAdvisor = r.url.contains('tripadvisor.');
      keys.addAll(extractKeys(tripAdvisor ? r.url : ''));
    }
    return keys.toSet().toList();
  }

  Future<List<String>> _viaModel(String name) async {
    final model = llm;
    if (model == null || !model.isConfigured) return const [];
    final reply = await model.askJson(
      AgentKind.atithi,
      system:
          'You know TripAdvisor location IDs ("geo ids", written like g293916). '
          'Reply ONLY with JSON {"keys": ["g..."]}: up to 3 likely IDs for the '
          'place and, after it, for its district or region. Say [] if you do '
          'not know: a wrong ID is worse than none.',
      user: name,
      maxTokens: 300,
      timeout: const Duration(seconds: 10),
    );
    final keys = reply.map?['keys'];
    if (keys is! List) return const [];
    return [
      for (final k in keys)
        if (k is String && RegExp(r'^g\d{3,9}$').hasMatch(k.trim())) k.trim(),
    ];
  }

  /// Validates candidates concurrently and returns the first (in the given
  /// order) that checks out.
  Future<ResolvedLocation?> _firstValid(List<(String, String)> candidates, LatLng where) async {
    if (candidates.isEmpty) return null;
    final checks = await Future.wait([for (final (key, source) in candidates) _validate(key, source, where)]);
    for (final r in checks) {
      if (r != null) return r;
    }
    return null;
  }

  Future<ResolvedLocation?> _validate(String key, String source, LatLng where) async {
    final list = await xotelo.list(key, limit: 12);
    if (list == null) return null;
    final located = [for (final h in list.hotels) if (h.hasLocation) h];
    if (located.length < minHotels) return null;
    final near = located.where((h) => haversineKm(where.latitude, where.longitude, h.lat!, h.lng!) <= maxKm).length;
    if (near / located.length < nearFraction) return null;
    return ResolvedLocation(
      key: key,
      center: where,
      source: source,
      checkedHotels: located.length,
      nearHotels: near,
    );
  }
}
