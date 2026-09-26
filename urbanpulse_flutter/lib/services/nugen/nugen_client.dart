import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// One reply from Nugen's inference API.
class NugenReply {
  const NugenReply({this.content, this.error, this.latencyMs = 0});

  final String? content;
  final String? error;
  final int latencyMs;

  bool get ok => content != null && error == null;
}

/// Nugen's OpenAI-style chat endpoint, used for the UrbanPulse Travel-Risk
/// model aligned on Nugen (see `nugen/`). The network timeout is I/O hygiene
/// only; a failed call leaves the caller to fall back.
class NugenClient {
  NugenClient({required this.apiKey, http.Client? client, this.baseUrl = 'https://api.nugen.in/api/v3', this.timeout = const Duration(seconds: 45)})
    : _client = client ?? http.Client();

  final String apiKey;
  final String baseUrl;
  final Duration timeout;
  final http.Client _client;

  Future<NugenReply> chat({required String model, required String prompt, int maxTokens = 500, double temperature = 0}) async {
    final watch = Stopwatch()..start();
    try {
      final res = await _client
          .post(
            Uri.parse('$baseUrl/inference/chat/completions'),
            headers: {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json', 'accept': 'application/json'},
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'user', 'content': prompt},
              ],
              'max_tokens': maxTokens,
              'temperature': temperature,
              'stream': false,
            }),
          )
          .timeout(timeout);
      final ms = watch.elapsedMilliseconds;
      if (res.statusCode != 200) {
        return NugenReply(error: 'HTTP ${res.statusCode}: ${_short(res.body)}', latencyMs: ms);
      }
      final content = parseContent(utf8.decode(res.bodyBytes));
      return content == null ? NugenReply(error: 'no content: ${_short(res.body)}', latencyMs: ms) : NugenReply(content: content, latencyMs: ms);
    } on TimeoutException {
      return NugenReply(error: 'timed out', latencyMs: watch.elapsedMilliseconds);
    } catch (e) {
      return NugenReply(error: '$e', latencyMs: watch.elapsedMilliseconds);
    }
  }

  /// The assistant text of a chat completion (or of the `data:` lines of a
  /// streamed one).
  static String? parseContent(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map<String, dynamic>) {
        final choices = j['choices'];
        if (choices is List && choices.isNotEmpty) {
          final m = (choices.first as Map<String, dynamic>)['message'];
          final c = m is Map<String, dynamic> ? m['content'] : null;
          if (c is String) return c;
        }
      }
    } catch (_) {
      // maybe server-sent events
    }
    final buf = StringBuffer();
    for (final line in const LineSplitter().convert(body)) {
      final t = line.trim();
      if (!t.startsWith('data:')) continue;
      final data = t.substring(5).trim();
      if (data == '[DONE]') break;
      try {
        final j = jsonDecode(data);
        final delta = ((j['choices'] as List).first as Map<String, dynamic>)['delta'];
        final c = delta is Map<String, dynamic> ? delta['content'] : null;
        if (c is String) buf.write(c);
      } catch (_) {
        // skip keep-alives and error lines
      }
    }
    return buf.isEmpty ? null : buf.toString();
  }

  static String _short(String s) => s.length <= 160 ? s : '${s.substring(0, 160)}…';
}
