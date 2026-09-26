import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../models/trip_intent.dart';
import 'groq_api_client.dart';

/// Turns a traveler's free-text request into structured [TripIntent]
/// constraints. Tries the real Groq LPU cloud first (sub-400ms structured JSON
/// extraction), falls back to Gemini if Groq is unavailable/fails, and finally
/// falls back to a deterministic keyword parser so the feature still works with
/// no live config at all.
///
/// Port of `intent/TripIntentParser.kt`. The Gemini step used the
/// `generativeai` Android SDK there; here it is the same model over Google's
/// public `generativelanguage` REST endpoint, which needs no extra dependency.
abstract final class TripIntentParser {
  static const _schema = '''
Respond with ONLY a raw JSON object (no markdown fences, no commentary) matching exactly this shape:
{
  "prioritizeCarbon": boolean,
  "prioritizeAccessibility": boolean,
  "prioritizeSpeed": boolean,
  "prioritizeBudget": boolean,
  "requireWheelchairAccess": boolean,
  "requireSolarEnergy": boolean,
  "requireZeroWaste": boolean,
  "maxPriceRupees": number or null,
  "searchKeywords": short string of the most relevant place/category keywords, or ""
}''';

  static const _groqCandidateModels = [
    'openai/gpt-oss-120b',
    'groq/compound',
    'openai/gpt-oss-20b',
  ];

  static Future<TripIntent> parse(String freeText) async {
    if (freeText.trim().isEmpty) return const TripIntent();

    if (AppConfig.hasGroqKey) {
      final intent = await _parseWithGroq(freeText);
      // Fall through to Gemini, then rules — never block the user on an LLM failure.
      if (intent != null) return intent;
    }

    if (AppConfig.hasGeminiKey) {
      final intent = await _parseWithGemini(freeText);
      if (intent != null) return intent;
    }

    return _parseWithRules(freeText);
  }

  static Future<TripIntent?> _parseWithGroq(String freeText) async {
    final prompt =
        'Extract structured travel-planning constraints from this traveler '
        'request.\n$_schema\n\nTraveler request: "${freeText.replaceAll('"', "'")}"';

    for (final model in _groqCandidateModels) {
      final content = await GroqApiClient.completion(
        model: model,
        systemPrompt:
            'You are a structured data extraction engine. Reply with raw JSON '
            'only, never prose.',
        userPrompt: prompt,
        temperature: 0.1,
        maxTokens: 300,
      );
      final intent = _decodeIntent(content, parsedBy: 'groq');
      if (intent != null) return intent;
    }
    return null;
  }

  static Future<TripIntent?> _parseWithGemini(String freeText) async {
    final prompt =
        'Extract structured travel-planning constraints from this traveler '
        'request.\n$_schema\n\nTraveler request: "${freeText.replaceAll('"', "'")}"';

    try {
      final response = await http
          .post(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/'
              'gemini-1.5-flash:generateContent?key=${AppConfig.geminiApiKey}',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return null;
      final parts =
          ((candidates.first as Map<String, dynamic>)['content']
                  as Map<String, dynamic>?)?['parts']
              as List<dynamic>?;
      if (parts == null || parts.isEmpty) return null;
      final text = (parts.first as Map<String, dynamic>)['text'] as String?;
      return _decodeIntent(text, parsedBy: 'gemini');
    } catch (_) {
      return null;
    }
  }

  static TripIntent? _decodeIntent(
    String? content, {
    required String parsedBy,
  }) {
    if (content == null || content.trim().isEmpty) return null;
    var jsonText = content.trim();
    if (jsonText.startsWith('```json')) jsonText = jsonText.substring(7);
    if (jsonText.startsWith('```')) jsonText = jsonText.substring(3);
    if (jsonText.endsWith('```')) {
      jsonText = jsonText.substring(0, jsonText.length - 3);
    }

    try {
      final parsed = jsonDecode(jsonText.trim()) as Map<String, dynamic>;
      return TripIntent(
        prioritizeCarbon: parsed['prioritizeCarbon'] as bool? ?? false,
        prioritizeAccessibility:
            parsed['prioritizeAccessibility'] as bool? ?? false,
        prioritizeSpeed: parsed['prioritizeSpeed'] as bool? ?? false,
        prioritizeBudget: parsed['prioritizeBudget'] as bool? ?? false,
        requireWheelchairAccess:
            parsed['requireWheelchairAccess'] as bool? ?? false,
        requireSolarEnergy: parsed['requireSolarEnergy'] as bool? ?? false,
        requireZeroWaste: parsed['requireZeroWaste'] as bool? ?? false,
        maxPriceRupees: (parsed['maxPriceRupees'] as num?)?.toInt(),
        searchKeywords: parsed['searchKeywords'] as String? ?? '',
        parsedBy: parsedBy,
      );
    } catch (_) {
      return null;
    }
  }

  /// Deterministic fallback — no network, no API key, always available.
  static TripIntent _parseWithRules(String freeText) {
    final text = freeText.toLowerCase();
    bool anyOf(List<String> needles) => needles.any(text.contains);

    final priceMatch =
        RegExp(
          r'(?:under|below|less than|max)?\s*(?:rs\.?|₹)\s*([\d,]+)',
          caseSensitive: false,
        ).firstMatch(text) ??
        RegExp(
          r'([\d,]+)\s*(?:rs\.?|rupees|₹)',
          caseSensitive: false,
        ).firstMatch(text);
    final maxPrice = int.tryParse(
      (priceMatch?.group(1) ?? '').replaceAll(',', ''),
    );

    const stopWords = {
      'i',
      'want',
      'a',
      'to',
      'the',
      'for',
      'with',
      'and',
      'trip',
      'hotel',
      'travel',
      'need',
      'looking',
      'cheap',
      'green',
      'eco',
      'wheelchair',
      'accessible',
      'fast',
      'under',
      'rs',
      'rupees',
    };
    final keywords = text
        .split(RegExp(r'\W+'))
        .where((w) => w.length > 2 && !stopWords.contains(w))
        .take(4)
        .join(' ');

    return TripIntent(
      prioritizeCarbon: anyOf([
        'green',
        'eco',
        'carbon',
        'sustainable',
        'emission',
      ]),
      prioritizeAccessibility: anyOf([
        'accessible',
        'accessibility',
        'wheelchair',
        'disab',
      ]),
      prioritizeSpeed: anyOf(['fast', 'quick', 'urgent', 'asap', 'hurry']),
      prioritizeBudget: anyOf([
        'cheap',
        'budget',
        'affordable',
        'low cost',
        'inexpensive',
      ]),
      requireWheelchairAccess: anyOf(['wheelchair', 'step-free', 'step free']),
      requireSolarEnergy: text.contains('solar'),
      requireZeroWaste: anyOf([
        'zero waste',
        'zero-waste',
        'no plastic',
        'plastic-free',
      ]),
      maxPriceRupees: maxPrice,
      searchKeywords: keywords,
    );
  }
}
