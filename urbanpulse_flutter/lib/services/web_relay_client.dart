import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';

/// On the website, sends the few sources that refuse requests from web pages
/// (CORS) through the team's backend (`server/`, route `/relay`); every other
/// request goes straight out as usual. On Android and iOS it is a plain client.
class WebRelayClient extends http.BaseClient {
  WebRelayClient(this._inner, this.relayBase);

  /// Hosts that do not allow browser requests. Must match `RELAY_HOSTS` in
  /// `server/server.js`.
  static const relayedHosts = {'data.xotelo.com', 'api.nugen.in', 'news.google.com', 'www.reddit.com'};

  final http.Client _inner;

  /// e.g. `https://api.urbanpulse.example` (no trailing slash).
  final String relayBase;

  /// The app's HTTP client for this platform.
  static http.Client forPlatform([http.Client? inner]) {
    final base = inner ?? http.Client();
    final relay = AppConfig.webRelayUrl;
    return kIsWeb && relay.isNotEmpty ? WebRelayClient(base, relay) : base;
  }

  /// Where [url] is actually requested from.
  Uri route(Uri url) => relayedHosts.contains(url.host) && url.scheme == 'https'
      ? Uri.parse('$relayBase/relay').replace(queryParameters: {'url': url.toString()})
      : url;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final target = route(request.url);
    if (target == request.url) return _inner.send(request);
    final relayed = http.Request(request.method, target)
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..bodyBytes = await request.finalize().toBytes();
    return _inner.send(relayed);
  }

  @override
  void close() => _inner.close();
}
