import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// A polite, identifying User-Agent. OpenStreetMap services, Wikipedia and
/// friends ask for one and block anonymous scrapers.
const kUserAgent = 'UrbanPulse/1.0 (sustainable travel planner; hackathon build)';

/// The outcome of one HTTP call. Adapters never throw: a failure is a value the
/// caller can route around.
class HttpOutcome {
  const HttpOutcome({this.status, this.body, this.error});

  final int? status;
  final String? body;
  final String? error;

  bool get ok => status != null && status! >= 200 && status! < 300 && body != null;

  /// The response decoded as JSON, or null.
  Object? get json {
    if (!ok) return null;
    try {
      return jsonDecode(body!);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? get map => json is Map<String, dynamic> ? json as Map<String, dynamic> : null;
}

/// GET [uri] with a timeout. Never throws.
Future<HttpOutcome> httpGet(
  http.Client client,
  Uri uri, {
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    final r = await client
        .get(uri, headers: {'User-Agent': kUserAgent, ...headers})
        .timeout(timeout);
    return HttpOutcome(status: r.statusCode, body: r.body);
  } on TimeoutException {
    return const HttpOutcome(error: 'timeout');
  } catch (e) {
    return HttpOutcome(error: 'network: $e');
  }
}

/// POST a form or JSON body. Never throws.
Future<HttpOutcome> httpPost(
  http.Client client,
  Uri uri, {
  Map<String, String> headers = const {},
  Object? body,
  Duration timeout = const Duration(seconds: 15),
}) async {
  try {
    final r = await client
        .post(uri, headers: {'User-Agent': kUserAgent, ...headers}, body: body)
        .timeout(timeout);
    return HttpOutcome(status: r.statusCode, body: r.body);
  } on TimeoutException {
    return const HttpOutcome(error: 'timeout');
  } catch (e) {
    return HttpOutcome(error: 'network: $e');
  }
}

double? asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

int? asInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// Great-circle distance in kilometres.
double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * r * math.asin(math.sqrt(a));
}
