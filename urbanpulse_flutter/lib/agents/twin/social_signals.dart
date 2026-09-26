import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../services/place_geocoder.dart';
import '../tools/web_search_tool.dart';
import '../travel_risk/travel_risk.dart';

/// A public post or headline about a place.
class SocialPost {
  const SocialPost({required this.text, required this.source, this.url, this.at});

  final String text;

  /// Google News, Reddit, Web or "You" (a report typed in the app).
  final String source;
  final String? url;
  final DateTime? at;
}

/// A post the Travel-Risk model read as a travel disruption, placed on the map
/// when its place could be found.
class WeatherSignal {
  const WeatherSignal({required this.post, required this.event, this.location});

  final SocialPost post;
  final WeatherEvent event;
  final LatLng? location;
}

/// Real-world reactions and reports about the weather at a destination:
/// Google News headlines (public RSS), Reddit posts (public search) and, when
/// a Tavily key is set, posts found on the web (X, Reddit, local news). Every
/// source is optional; one that fails is skipped.
class SocialSignalFeed {
  SocialSignalFeed({http.Client? client, this.webSearch, this.geocoder}) : _client = client ?? http.Client();

  final http.Client _client;
  final SearchProvider? webSearch;
  final PlaceGeocoder? geocoder;

  static const timeout = Duration(seconds: 12);
  static const _weatherWords = 'rain OR flood OR waterlogging OR heatwave OR landslide OR storm OR cyclone';

  final Map<String, LatLng?> _geo = {};

  /// Which sources answered on the last fetch, for the UI.
  final List<String> lastSources = [];

  Future<List<SocialPost>> fetch(String city) async {
    lastSources.clear();
    final results = await Future.wait([_news(city), _reddit(city), _web(city)]);
    final out = <SocialPost>[];
    final seen = <String>{};
    for (final list in results) {
      for (final p in list) {
        final k = p.text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (k.length < 12 || !seen.add(k)) continue;
        out.add(p);
      }
    }
    out.sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000)));
    return out;
  }

  /// Fetches, classifies with [risk] and places the disruptions on the map.
  Future<List<WeatherSignal>> signals(String city, LatLng center, TravelRiskModel risk, {int limit = 12}) async {
    final posts = (await fetch(city)).take(limit).toList();
    final out = <WeatherSignal>[];
    final events = await Future.wait([
      for (final p in posts) risk.weatherEvent(city: city, post: p.text).catchError((_) => const WeatherEvent()),
    ]);
    for (var i = 0; i < posts.length; i++) {
      if (!events[i].isEvent) continue;
      out.add(WeatherSignal(post: posts[i], event: events[i], location: await locate(events[i].place, city, center)));
    }
    return out;
  }

  /// One report typed by the traveller (or a judge), read the same way.
  Future<WeatherSignal> classify(String text, String city, LatLng center, TravelRiskModel risk, {String source = 'You'}) async {
    final post = SocialPost(text: text, source: source, at: DateTime.now());
    final event = await risk.weatherEvent(city: city, post: text);
    return WeatherSignal(post: post, event: event, location: event.isEvent ? await locate(event.place, city, center) : null);
  }

  /// A named road or place, found near the destination (within 40 km).
  Future<LatLng?> locate(String? place, String city, LatLng center) async {
    final g = geocoder;
    if (g == null || place == null || place.trim().length < 3) return null;
    final key = '${place.toLowerCase()}|${city.toLowerCase()}';
    if (_geo.containsKey(key)) return _geo[key];
    LatLng? at;
    try {
      at = await g.lookup('$place, $city').timeout(timeout);
    } catch (_) {
      at = null;
    }
    if (at != null && const Distance().as(LengthUnit.Kilometer, at, center) > 40) at = null;
    _geo[key] = at;
    return at;
  }

  Future<List<SocialPost>> _news(String city) async {
    try {
      // The last three days only: older headlines are not live signals.
      final q = Uri.encodeQueryComponent('"$city" ($_weatherWords) when:3d');
      final res = await _client.get(Uri.parse('https://news.google.com/rss/search?q=$q&hl=en-IN&gl=IN&ceid=IN:en')).timeout(timeout);
      if (res.statusCode != 200) return const [];
      final posts = parseGoogleNewsRss(utf8.decode(res.bodyBytes));
      if (posts.isNotEmpty) lastSources.add('Google News');
      return posts.take(15).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<SocialPost>> _reddit(String city) async {
    try {
      final q = Uri.encodeQueryComponent('$city (rain OR flood OR waterlogging OR heat)');
      final res = await _client
          .get(Uri.parse('https://www.reddit.com/search.json?q=$q&sort=new&t=week&limit=15'), headers: {'User-Agent': 'UrbanPulseApp/1.0 (weather twin)'})
          .timeout(timeout);
      if (res.statusCode != 200) return const [];
      final posts = parseReddit(utf8.decode(res.bodyBytes));
      if (posts.isNotEmpty) lastSources.add('Reddit');
      return posts;
    } catch (_) {
      return const [];
    }
  }

  Future<List<SocialPost>> _web(String city) async {
    final s = webSearch;
    if (s == null) return const [];
    try {
      final results = await s.search('$city waterlogging OR flooding OR "closed due to rain" OR heatwave today site:x.com OR site:reddit.com OR site:timesofindia.indiatimes.com', maxResults: 8).timeout(timeout);
      if (results == null || results.isEmpty) return const [];
      lastSources.add('Web');
      return [
        for (final r in results)
          SocialPost(text: r.snippet.trim().isEmpty ? r.title : '${r.title}. ${r.snippet}'.replaceAll(RegExp(r'\s+'), ' '), source: 'Web', url: r.url),
      ];
    } catch (_) {
      return const [];
    }
  }

  static List<SocialPost> parseGoogleNewsRss(String xml) {
    final out = <SocialPost>[];
    for (final m in RegExp(r'<item>([\s\S]*?)</item>').allMatches(xml)) {
      final item = m.group(1)!;
      String? tag(String name) {
        final t = RegExp('<$name[^>]*>([\\s\\S]*?)</$name>').firstMatch(item)?.group(1);
        return t == null ? null : _decode(t.replaceAll(RegExp(r'^<!\[CDATA\[|\]\]>$'), '').trim());
      }

      final title = tag('title');
      if (title == null || title.isEmpty) continue;
      // "Headline - Publisher": the model reads the headline, the app credits the outlet.
      final cut = title.lastIndexOf(' - ');
      final publisher = cut > 0 && title.length - cut <= 40 ? title.substring(cut + 3).trim() : null;
      out.add(
        SocialPost(
          text: publisher == null ? title : title.substring(0, cut).trim(),
          source: publisher == null ? 'Google News' : 'Google News · $publisher',
          url: tag('link'),
          at: _rfc822(tag('pubDate')),
        ),
      );
    }
    return out;
  }

  static List<SocialPost> parseReddit(String body) {
    try {
      final j = jsonDecode(body) as Map<String, dynamic>;
      final children = (j['data'] as Map<String, dynamic>?)?['children'] as List<dynamic>? ?? const [];
      return [
        for (final c in children)
          if (c is Map<String, dynamic> && c['data'] is Map<String, dynamic>)
            () {
              final d = c['data'] as Map<String, dynamic>;
              final title = '${d['title'] ?? ''}'.trim();
              final text = '${d['selftext'] ?? ''}'.trim();
              final created = d['created_utc'];
              return SocialPost(
                text: text.isEmpty ? title : '$title. ${text.length > 240 ? text.substring(0, 240) : text}',
                source: 'Reddit',
                url: d['permalink'] == null ? null : 'https://www.reddit.com${d['permalink']}',
                at: created is num ? DateTime.fromMillisecondsSinceEpoch((created * 1000).round(), isUtc: true) : null,
              );
            }(),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String _decode(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll(RegExp(r'<[^>]+>'), '');

  static const _months = {'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6, 'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12};

  /// "Sat, 26 Sep 2026 14:05:00 GMT".
  static DateTime? _rfc822(String? s) {
    if (s == null) return null;
    final m = RegExp(r'(\d{1,2}) (\w{3}) (\d{4}) (\d{2}):(\d{2})').firstMatch(s);
    if (m == null) return null;
    final month = _months[m.group(2)];
    if (month == null) return null;
    return DateTime.utc(int.parse(m.group(3)!), month, int.parse(m.group(1)!), int.parse(m.group(4)!), int.parse(m.group(5)!));
  }
}
