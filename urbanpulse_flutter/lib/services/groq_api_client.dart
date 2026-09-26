import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';

/// Conversational Groq LPU client. Port of `network/GroqApiClient.kt`.
///
/// Returns null (never throws) when no key is configured or every candidate
/// model fails, so callers can fall back to the grounded local intelligence
/// service exactly as the Kotlin version did.
abstract final class GroqApiClient {
  static const endpoint = 'https://api.groq.com/openai/v1/chat/completions';
  static const timeout = Duration(seconds: 25);

  /// Active high-performance models available on the project's Groq account,
  /// tried in order.
  ///
  /// (`groq/compound-mini` was decommissioned on 2026-09-21.)
  static const candidateModels = [
    'openai/gpt-oss-120b',
    'openai/gpt-oss-20b',
    'qwen/qwen3.8-27b',
  ];

  static const _defaultSystemPrompt =
      'You are Yatri AI, an expert sustainable travel & smart mobility assistant for '
      'UrbanPulse. When asked general questions, math, or travel questions, answer '
      'naturally, accurately, and concisely.';

  static Future<String?> queryGroq(
    String userPrompt, {
    String systemPrompt = _defaultSystemPrompt,
  }) async {
    if (!AppConfig.hasGroqKey) return null;

    for (final model in candidateModels) {
      final content = await completion(
        model: model,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        temperature: 0.4,
        maxTokens: 800,
      );
      if (content != null && content.trim().isNotEmpty) return content;
    }
    return null;
  }

  /// Single chat completion against one model. Shared by the conversational
  /// client, the agentic trip planner and the intent parser. Returns null on
  /// any failure; use [chat] when the reason matters.
  static Future<String?> completion({
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required double temperature,
    required int maxTokens,
    String? apiKeyOverride,
  }) async {
    final result = await chat(
      model: model,
      messages: [
        GroqMessage('system', systemPrompt),
        GroqMessage('user', userPrompt),
      ],
      temperature: temperature,
      maxTokens: maxTokens,
      apiKeyOverride: apiKeyOverride,
    );
    return result is GroqSuccess ? result.content : null;
  }

  /// Multi-turn chat completion with a typed result, so callers can tell a
  /// rejected key from a timeout. Optional JSON mode and reasoning effort are
  /// used by the Yatri receptionist agent (gpt-oss reasons before answering,
  /// so a low `reasoningEffort` keeps `maxTokens` for the actual reply).
  static Future<GroqResult> chat({
    required String model,
    required List<GroqMessage> messages,
    double temperature = 0.2,
    int maxTokens = 1024,
    bool jsonMode = false,
    String? reasoningEffort,
    Duration? requestTimeout,
    String? apiKeyOverride,
    http.Client? client,

    /// Extra top-level request fields, e.g. `search_settings` for
    /// `groq/compound`'s built-in web search.
    Map<String, Object?>? extraBody,
  }) async {
    final apiKey = apiKeyOverride ?? AppConfig.groqApiKey;
    if (apiKey.isEmpty) return const GroqFailure(GroqErrorKind.noKey);

    final http_ = client ?? http.Client();
    try {
      final response = await http_
          .post(
            Uri.parse(endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                for (final m in messages) {'role': m.role, 'content': m.content},
              ],
              'temperature': temperature,
              'max_tokens': maxTokens,
              if (jsonMode) 'response_format': {'type': 'json_object'},
              if (reasoningEffort != null) 'reasoning_effort': reasoningEffort,
              ...?extraBody,
            }),
          )
          .timeout(requestTimeout ?? timeout);

      final status = response.statusCode;
      if (status < 200 || status >= 300) {
        return GroqFailure(
          _kindFor(status),
          status: status,
          detail: response.body,
          retryAfter: _retryAfter(response.headers['retry-after']),
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        return const GroqFailure(GroqErrorKind.empty);
      }
      final message = (choices.first as Map<String, dynamic>)['message'];
      final content = (message as Map<String, dynamic>?)?['content'] as String?;
      if (content == null || content.trim().isEmpty) {
        return const GroqFailure(GroqErrorKind.empty);
      }
      return GroqSuccess(content, model, raw: json);
    } on TimeoutException {
      return const GroqFailure(GroqErrorKind.timeout);
    } catch (_) {
      return const GroqFailure(GroqErrorKind.network);
    } finally {
      if (client == null) http_.close();
    }
  }

  /// The `Retry-After` header (seconds), if the provider sent one.
  static Duration? _retryAfter(String? header) {
    final seconds = double.tryParse((header ?? '').trim());
    if (seconds == null || seconds < 0) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  static GroqErrorKind _kindFor(int status) => switch (status) {
    401 || 403 => GroqErrorKind.unauthorized,
    429 => GroqErrorKind.rateLimited,
    >= 400 && < 500 => GroqErrorKind.badRequest,
    _ => GroqErrorKind.server,
  };
}

class GroqMessage {
  const GroqMessage(this.role, this.content);

  final String role;
  final String content;
}

enum GroqErrorKind {
  noKey,
  unauthorized,
  rateLimited,
  badRequest,
  server,
  timeout,
  network,
  empty,
}

sealed class GroqResult {
  const GroqResult();
}

final class GroqSuccess extends GroqResult {
  const GroqSuccess(this.content, this.model, {this.raw});

  final String content;
  final String model;

  /// The decoded response body, for callers that need more than the text (e.g.
  /// `groq/compound`'s `executed_tools` with its search results).
  final Map<String, dynamic>? raw;
}

final class GroqFailure extends GroqResult {
  const GroqFailure(this.kind, {this.status, this.detail, this.retryAfter});

  final GroqErrorKind kind;
  final int? status;
  final String? detail;

  /// How long the provider asked us to wait (rate limits).
  final Duration? retryAfter;
}
