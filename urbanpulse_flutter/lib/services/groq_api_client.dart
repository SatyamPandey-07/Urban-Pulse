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
  static const candidateModels = [
    'openai/gpt-oss-120b',
    'groq/compound',
    'openai/gpt-oss-20b',
    'groq/compound-mini',
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
  /// client, the agentic trip planner and the intent parser.
  static Future<String?> completion({
    required String model,
    required String systemPrompt,
    required String userPrompt,
    required double temperature,
    required int maxTokens,
    String? apiKeyOverride,
  }) async {
    final apiKey = apiKeyOverride ?? AppConfig.groqApiKey;
    if (apiKey.isEmpty) return null;

    try {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userPrompt},
              ],
              'temperature': temperature,
              'max_tokens': maxTokens,
            }),
          )
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;
      final message = (choices.first as Map<String, dynamic>)['message'];
      final content = (message as Map<String, dynamic>?)?['content'] as String?;
      if (content == null || content.trim().isEmpty) return null;
      return content;
    } catch (_) {
      // Caller tries the next candidate model, then a non-LLM fallback.
      return null;
    }
  }
}
