import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/agents/atithi/hotel_finder.dart';
import 'package:urbanpulse/agents/bhatkanti/hotspot_finder.dart';
import 'package:urbanpulse/agents/hariyali/carbon_engine.dart';
import 'package:urbanpulse/agents/khoji/khoji.dart';
import 'package:urbanpulse/agents/runtime/agent_kind.dart';
import 'package:urbanpulse/agents/runtime/llm_pool.dart';
import 'package:urbanpulse/agents/runtime/report.dart';
import 'package:urbanpulse/agents/runtime/task_graph.dart';
import 'package:urbanpulse/agents/safar/transport_planner.dart';
import 'package:urbanpulse/agents/saksham/audit_engine.dart';
import 'package:urbanpulse/agents/yatri/planner_orchestrator.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/models/yatri_question.dart';
import 'package:urbanpulse/services/groq_api_client.dart';

/// Long strings (page text, model reasoning) are kept up to this length, with
/// a marker saying how much was cut, so the report stays readable.
const maxString = 8000;

/// Every model call exactly as the agents made it and as it came back.
class RecordingLlm implements AgentLlm {
  RecordingLlm(this.inner);

  final AgentLlm inner;
  final List<Map<String, Object?>> calls = [];
  final _started = DateTime.now();

  @override
  bool get isConfigured => inner.isConfigured;

  @override
  Future<GroqResult> ask(
    AgentKind agent,
    List<GroqMessage> messages, {
    LlmTier tier = LlmTier.light,
    bool json = false,
    double temperature = 0.2,
    int maxTokens = 1400,
    Duration? timeout,
    Map<String, Object?>? extraBody,
  }) async {
    final index = calls.length;
    final entry = <String, Object?>{
      'index': index,
      'agent': agent.name,
      'tier': tier.name,
      'json': json,
      'temperature': temperature,
      'maxTokens': maxTokens,
      'timeoutMs': timeout?.inMilliseconds,
      'extraBody': extraBody,
      'atMs': DateTime.now().difference(_started).inMilliseconds,
      'request': [for (final m in messages) {'role': m.role, 'content': m.content}],
    };
    calls.add(entry);
    final sw = Stopwatch()..start();
    final r = await inner.ask(agent, messages, tier: tier, json: json, temperature: temperature, maxTokens: maxTokens, timeout: timeout, extraBody: extraBody);
    entry['durationMs'] = sw.elapsedMilliseconds;
    entry['response'] = switch (r) {
      GroqSuccess() => {'ok': true, 'model': r.model, 'content': r.content, 'raw': r.raw},
      GroqFailure() => {'ok': false, 'kind': r.kind.name, 'status': r.status, 'detail': r.detail, 'retryAfterMs': r.retryAfter?.inMilliseconds},
    };
    return r;
  }
}

/// Every HTTP request the data clients made, with the response as it came back.
class RecordingClient extends http.BaseClient {
  RecordingClient(this.inner);

  final http.Client inner;
  final List<Map<String, Object?>> calls = [];
  final _started = DateTime.now();

  static String redact(Uri u) {
    final q = {
      for (final e in u.queryParameters.entries) e.key: RegExp(r'key|token|secret', caseSensitive: false).hasMatch(e.key) ? '<redacted>' : e.value,
    };
    return u.replace(queryParameters: q.isEmpty ? null : q).toString();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final entry = <String, Object?>{
      'index': calls.length,
      'method': request.method,
      'url': redact(request.url),
      'atMs': DateTime.now().difference(_started).inMilliseconds,
      if (request is http.Request && request.body.isNotEmpty) 'requestBody': _redactBody(request.body),
    };
    calls.add(entry);
    final sw = Stopwatch()..start();
    try {
      final resp = await inner.send(request);
      final bytes = await resp.stream.toBytes();
      entry['status'] = resp.statusCode;
      entry['durationMs'] = sw.elapsedMilliseconds;
      entry['bytes'] = bytes.length;
      entry['responseBody'] = utf8.decode(bytes, allowMalformed: true);
      return http.StreamedResponse(http.ByteStream.fromBytes(bytes), resp.statusCode, headers: resp.headers, request: resp.request, reasonPhrase: resp.reasonPhrase);
    } catch (e) {
      entry['durationMs'] = sw.elapsedMilliseconds;
      entry['error'] = e.toString();
      rethrow;
    }
  }

  static String _redactBody(String body) => body.replaceAll(RegExp(r'("?(api_?key|token)"?\s*[:=]\s*")[^"]+(")', caseSensitive: false), r'$1<redacted>$3');
}

/// Turns any object the planner produced into plain JSON: its own `toJson`
/// when it has one, otherwise its fields, converted all the way down.
Object? toPlain(Object? o) {
  final r = _plain(o);
  // A typed object became a map or list of raw fields: convert those too.
  if ((r is Map && o is! Map) || (r is List && o is! Iterable)) return toPlain(r);
  return r;
}

Object? _plain(Object? o) {
  if (o == null || o is num || o is bool) return o;
  if (o is String) return o.length <= maxString ? o : '${o.substring(0, maxString)}…[${o.length - maxString} more characters cut]';
  if (o is Enum) return o.name;
  if (o is DateTime) return o.toIso8601String();
  if (o is Duration) return '${o.inMilliseconds} ms';
  if (o is LatLng) return {'lat': o.latitude, 'lon': o.longitude};
  if (o is Map) return {for (final e in o.entries) (e.key is Enum ? (e.key as Enum).name : '${e.key}'): toPlain(e.value)};
  if (o is Iterable) return [for (final e in o) toPlain(e)];
  if (o is PlanOutcome) {
    return {'status': o.status, 'summary': o.summary, 'hotel': toPlain(o.hotel), 'center': toPlain(o.center), 'notes': o.notes, 'hotelsFound': o.hotels?.options.length, 'itinerary': o.itinerary == null ? null : '(see section 7)'};
  }
  if (o is AgentReport) {
    return {'agent': o.agent, 'status': o.status, 'summary': o.summary, 'why': o.why, 'issues': toPlain(o.issues), 'evidence': toPlain(o.evidence), 'payloadType': o.payload?.runtimeType.toString(), 'payload': toPlain(o.payload)};
  }
  if (o is Issue) return {'id': o.id, 'agent': o.agent, 'severity': o.severity, 'message': o.message, 'why': o.why, 'userVisible': o.userVisible, 'options': toPlain(o.options)};
  if (o is IssueOption) return {'id': o.id, 'label': o.label, 'subtitle': o.subtitle, 'badge': o.badge, 'recommended': o.recommended, 'effect': toPlain(o.effect)};
  if (o is Evidence) return {'claim': o.claim, 'provenance': toPlain(o.provenance)};
  if (o is HotelSearchResult) {
    return {'query': toPlain(o.query), 'options': toPlain(o.options), 'considered': o.considered, 'sources': o.sources, 'warnings': o.warnings, 'dateBand': o.dateBand, 'cheapDates': o.cheapDates};
  }
  if (o is HotelQuery) {
    return {'destination': o.destination, 'center': toPlain(o.center), 'checkIn': toPlain(o.checkIn), 'checkOut': toPlain(o.checkOut), 'rooms': o.rooms, 'adults': o.adults, 'needs': toPlain(o.needs), 'nightlyCapInr': o.nightlyCapInr, 'radiusKm': o.radiusKm, 'preferEco': o.preferEco, 'notes': o.notes};
  }
  if (o is HotspotSearchResult) {
    return {'query': toPlain(o.query), 'selected': toPlain(o.selected), 'poolNotSelected': toPlain([for (final h in o.pool) if (!o.selected.any((s) => s.id == h.id)) h]), 'considered': o.considered, 'sources': o.sources, 'warnings': o.warnings};
  }
  if (o is HotspotQuery) {
    return {'destination': o.destination, 'center': toPlain(o.center), 'days': o.days, 'pace': toPlain(o.pace), 'style': toPlain(o.style), 'needs': toPlain(o.needs), 'details': toPlain(o.details), 'limits': o.limits, 'avoidsStairs': o.avoidsStairs, 'mix': o.mix, 'radiusKm': o.radiusKm, 'target': o.target, 'notes': o.notes};
  }
  if (o is TransportPlan) return {'query': o.query.toString(), 'options': toPlain(o.options), 'recommendedIndex': o.recommendedIndex};
  if (o is KhojiFinding) return {'claims': toPlain(o.claims), 'reviews': toPlain(o.reviews), 'access': toPlain(o.access), 'sources': toPlain(o.sources), 'closed': o.closed, 'methods': o.methods};
  if (o is AuditResult) return {'audit': toPlain(o.audit), 'failures': [for (final f in o.failures) f.toString()]};
  if (o is GreenResult) return {'report': toPlain(o.report), 'greenerJourney': o.greenerJourney?.toString()};
  if (o is TaskNode) {
    return {
      'id': o.id,
      'agent': o.agent,
      'title': o.spec.title,
      'goal': o.spec.goal,
      'why': o.why ?? o.spec.why,
      'parents': o.spec.parents,
      'delegatedBy': o.delegatedBy,
      'status': o.status,
      'startedAt': toPlain(o.startedAt),
      'endedAt': toPlain(o.endedAt),
      'elapsed': toPlain(o.elapsed),
      'summary': o.summary,
      'error': o.error,
    };
  }
  if (o is FeedEvent) return {'time': toPlain(o.time), 'agent': o.agent, 'kind': o.kind, 'nodeId': o.nodeId, 'text': o.text, 'why': o.why};
  if (o is YatriQuestion) {
    return {
      'id': o.id,
      'widget': o.widget,
      'agent': o.agent,
      'reason': o.reason,
      'text': o.defaultText,
      'why': o.why,
      'options': [for (final q in o.options) {'id': q.id, 'label': q.label, 'subtitle': q.subtitle, 'badge': q.badge, 'recommended': q.recommended}],
      if (o.hotels.isNotEmpty) 'hotels': toPlain(o.hotels),
      if (o.hotelNeeds.isNotEmpty) 'hotelNeeds': toPlain(o.hotelNeeds),
    };
  }
  if (o is ChoiceAnswer) return {'type': 'choice', 'optionId': o.optionId, 'label': o.label};
  if (o is MultiChoiceAnswer) return {'type': 'multiChoice', 'optionIds': o.optionIds.toList(), 'labels': o.labels};
  if (o is TripBrief) return o.toJson();
  try {
    return toPlain((o as dynamic).toJson());
  } on NoSuchMethodError {
    return {'type': o.runtimeType.toString(), 'value': o.toString()};
  }
}

/// A fenced JSON block. Anything that still cannot be encoded is written as
/// its text, so one odd object never loses the report.
String jsonBlock(Object? o) {
  try {
    return '```json\n${JsonEncoder.withIndent('  ', (x) => x is Enum ? x.name : x.toString()).convert(toPlain(o))}\n```\n';
  } catch (e) {
    return '```\n(could not write as JSON: $e)\n$o\n```\n';
  }
}

/// Writes [text] to [path], creating the folder if needed.
void writeFile(String path, String text) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(text);
}
