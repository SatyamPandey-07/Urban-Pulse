import 'package:http/http.dart' as http;

import 'data_cache.dart';
import 'http_util.dart';

/// A node/way/relation from OpenStreetMap with its tags.
class OsmPlace {
  const OsmPlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.tags,
  });

  /// e.g. `way/12345`.
  final String id;
  final String name;
  final double lat;
  final double lon;
  final Map<String, String> tags;

  String? get wheelchair => tags['wheelchair'];
  String? get openingHours => tags['opening_hours'];
  String? get website => tags['website'] ?? tags['contact:website'];
  String? get phone => tags['phone'] ?? tags['contact:phone'];

  static OsmPlace? fromElement(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final tags = <String, String>{
      for (final e in ((raw['tags'] as Map<String, dynamic>?) ?? const {}).entries)
        if (e.value != null) e.key: '${e.value}',
    };
    final name = tags['name'] ?? tags['name:en'];
    if (name == null || name.trim().isEmpty) return null;
    final center = raw['center'] as Map<String, dynamic>?;
    final lat = asDouble(raw['lat'] ?? center?['lat']);
    final lon = asDouble(raw['lon'] ?? center?['lon']);
    if (lat == null || lon == null) return null;
    return OsmPlace(
      id: '${raw['type']}/${raw['id']}',
      name: name.trim(),
      lat: lat,
      lon: lon,
      tags: tags,
    );
  }
}

/// OpenStreetMap through the public Overpass API. The usage policy is strict
/// (roughly 10,000 requests and 1 GB a day, and it must not be the backend of a
/// third-party app), so every query is cached, identical requests are shared,
/// and the bounding area is kept small.
class OverpassClient {
  OverpassClient({http.Client? client, DataCache? cache, List<String>? endpoints})
    : _client = client ?? http.Client(),
      _cache = cache ?? MemoryCache(),
      _endpoints = endpoints ?? defaultEndpoints;

  static const defaultEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  final http.Client _client;
  final DataCache _cache;
  final List<String> _endpoints;
  final Map<String, Future<Object?>> _inFlight = {};

  static const _hotelFilter = '"tourism"~"^(hotel|guest_house|hostel|motel|apartment|chalet|resort)\$"';

  Future<List<OsmPlace>?> hotelsAround(double lat, double lon, {int radiusM = 8000, int limit = 80}) =>
      _run('hotels', lat, lon, radiusM, limit, '''
(
  nwr[$_hotelFilter](around:$radiusM,$lat,$lon);
);''');

  Future<List<OsmPlace>?> attractionsAround(double lat, double lon, {int radiusM = 10000, int limit = 120}) =>
      _run('sights', lat, lon, radiusM, limit, '''
(
  nwr["tourism"~"^(attraction|museum|gallery|viewpoint|zoo|theme_park|artwork)\$"](around:$radiusM,$lat,$lon);
  nwr["historic"~"^(monument|memorial|castle|fort|ruins|archaeological_site|temple|church)\$"](around:$radiusM,$lat,$lon);
  nwr["leisure"~"^(park|nature_reserve|garden)\$"]["name"](around:$radiusM,$lat,$lon);
  nwr["natural"~"^(peak|waterfall|beach|hot_spring|cave_entrance)\$"]["name"](around:$radiusM,$lat,$lon);
  nwr["amenity"="place_of_worship"]["name"]["tourism"](around:$radiusM,$lat,$lon);
);''');

  /// Named places of one kind around a point (for a map's category buttons).
  /// [filters] are Overpass tag filters such as `["amenity"="hospital"]`; each
  /// one is a separate alternative.
  Future<List<OsmPlace>?> nearby(String kind, List<String> filters, double lat, double lon, {int radiusM = 4000, int limit = 40}) =>
      _run('near.$kind', lat, lon, radiusM, limit, '(\n${[for (final f in filters) '  nwr$f["name"](around:$radiusM,$lat,$lon);'].join('\n')}\n);');

  /// Finds a named place (to read its accessibility tags), nearest first.
  Future<List<OsmPlace>?> byName(String name, double lat, double lon, {int radiusM = 3000}) {
    final safe = escapeRegex(name.trim());
    if (safe.isEmpty) return Future.value(null);
    return _run('name.$safe', lat, lon, radiusM, 10, '''
(
  nwr["name"~"^$safe\$",i](around:$radiusM,$lat,$lon);
);''');
  }

  /// Escapes a value for use inside an Overpass regex string. Inside an
  /// Overpass string literal a regex escape needs two backslashes, and a quote
  /// needs one.
  static String escapeRegex(String s) => s
      .replaceAll('\n', ' ')
      .replaceAllMapped(
        RegExp(r'[\\^$.|?*+()\[\]{}"]'),
        (m) => m[0] == '"' ? r'\"' : r'\\' + m[0]!,
      );

  /// The full query text. Public for tests.
  static String buildQuery(String body, int limit) =>
      '[out:json][timeout:20];\n$body\nout center tags $limit;';

  Future<List<OsmPlace>?> _run(
    String kind,
    double lat,
    double lon,
    int radiusM,
    int limit,
    String body,
  ) async {
    final key = 'overpass.$kind.${lat.toStringAsFixed(3)}.${lon.toStringAsFixed(3)}.$radiusM.$limit';
    // Identical concurrent requests share one call.
    // (The block body matters: `remove` returns this very future, and
    // `whenComplete` would wait on it forever.)
    final json = await (_inFlight[key] ??= _cache
        .rememberJson(key, () => _fetch(buildQuery(body, limit)))
        .whenComplete(() {
          _inFlight.remove(key);
        }));
    return parse(json);
  }

  Future<Object?> _fetch(String query) async {
    for (final endpoint in _endpoints) {
      final o = await httpPost(
        _client,
        Uri.parse(endpoint),
        body: {'data': query},
        timeout: const Duration(seconds: 25),
      );
      final m = o.map;
      if (m != null && m['elements'] is List) return m['elements'];
      // 429 / 504: try the mirror.
    }
    return null;
  }

  static List<OsmPlace>? parse(Object? elements) {
    if (elements is! List) return null;
    return [
      for (final e in elements)
        if (OsmPlace.fromElement(e) case final p?) p,
    ];
  }
}
