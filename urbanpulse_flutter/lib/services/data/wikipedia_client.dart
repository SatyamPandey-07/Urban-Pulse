import 'package:http/http.dart' as http;

import 'data_cache.dart';
import 'http_util.dart';

class WikiPage {
  const WikiPage({
    required this.title,
    this.pageId,
    this.lat,
    this.lon,
    this.distanceM,
    this.extract,
    this.url,
  });

  final String title;
  final int? pageId;
  final double? lat;
  final double? lon;
  final double? distanceM;

  /// A short plain-text summary, when fetched.
  final String? extract;
  final String? url;
}

/// Wikipedia: free, no key, generous limits, and the best no-key source of
/// "what is notable near here". Requires an identifying User-Agent (sent by
/// [httpGet]) and attribution when text is shown.
class WikipediaClient {
  WikipediaClient({http.Client? client, DataCache? cache, this.language = 'en'})
    : _client = client ?? http.Client(),
      _cache = cache ?? MemoryCache();

  final http.Client _client;
  final DataCache _cache;
  final String language;

  String get _api => 'https://$language.wikipedia.org/w/api.php';

  /// Articles with coordinates within [radiusM] (max 10,000) of a point.
  Future<List<WikiPage>?> geosearch(double lat, double lon, {int radiusM = 10000, int limit = 30}) async {
    final r = radiusM.clamp(10, 10000);
    final json = await _cache.rememberJson(
      'wiki.geo.${lat.toStringAsFixed(3)}.${lon.toStringAsFixed(3)}.$r.$limit',
      () async {
        final o = await httpGet(
          _client,
          Uri.parse(_api).replace(queryParameters: {
            'action': 'query',
            'list': 'geosearch',
            'gscoord': '$lat|$lon',
            'gsradius': '$r',
            'gslimit': '$limit',
            'format': 'json',
            'formatversion': '2',
          }),
        );
        return (o.map?['query'] as Map<String, dynamic>?)?['geosearch'];
      },
      ttl: const Duration(days: 3),
    );
    return parseGeosearch(json);
  }

  static List<WikiPage>? parseGeosearch(Object? list) {
    if (list is! List) return null;
    return [
      for (final e in list)
        if (e is Map<String, dynamic> && e['title'] is String)
          WikiPage(
            title: e['title'] as String,
            pageId: asInt(e['pageid']),
            lat: asDouble(e['lat']),
            lon: asDouble(e['lon']),
            distanceM: asDouble(e['dist']),
          ),
    ];
  }

  /// Full-text search for [query] (e.g. "Munnar tourist attractions").
  Future<List<WikiPage>?> search(String query, {int limit = 8}) async {
    if (query.trim().isEmpty) return null;
    final json = await _cache.rememberJson(
      'wiki.search.${query.trim().toLowerCase()}.$limit',
      () async {
        final o = await httpGet(
          _client,
          Uri.parse(_api).replace(queryParameters: {
            'action': 'query',
            'list': 'search',
            'srsearch': query.trim(),
            'srlimit': '$limit',
            'format': 'json',
            'formatversion': '2',
          }),
        );
        return (o.map?['query'] as Map<String, dynamic>?)?['search'];
      },
      ttl: const Duration(days: 3),
    );
    if (json is! List) return null;
    return [
      for (final e in json)
        if (e is Map<String, dynamic> && e['title'] is String)
          WikiPage(
            title: e['title'] as String,
            pageId: asInt(e['pageid']),
            extract: _stripHtml(e['snippet'] as String?),
          ),
    ];
  }

  /// A short summary of an article, with its coordinates when it has them.
  Future<WikiPage?> summary(String title) async {
    if (title.trim().isEmpty) return null;
    final json = await _cache.rememberJson(
      'wiki.summary.${title.trim().toLowerCase()}',
      () async {
        final o = await httpGet(
          _client,
          Uri.https(
            '$language.wikipedia.org',
            '/api/rest_v1/page/summary/${Uri.encodeComponent(title.trim().replaceAll(' ', '_'))}',
          ),
        );
        return o.map;
      },
      ttl: const Duration(days: 7),
    );
    if (json is! Map<String, dynamic>) return null;
    final coords = json['coordinates'] as Map<String, dynamic>?;
    final urls = json['content_urls'] as Map<String, dynamic>?;
    return WikiPage(
      title: json['title'] as String? ?? title,
      pageId: asInt(json['pageid']),
      lat: asDouble(coords?['lat']),
      lon: asDouble(coords?['lon']),
      extract: json['extract'] as String?,
      url: ((urls?['desktop'] as Map<String, dynamic>?)?['page']) as String?,
    );
  }

  static String? _stripHtml(String? s) =>
      s?.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&quot;', '"').replaceAll('&amp;', '&');
}
