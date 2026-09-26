import 'dart:convert';

import '../../domain/trip_brief/brief_merger.dart';
import '../../domain/trip_brief/extraction.dart';
import '../../models/trip_brief.dart';
import '../../models/yatri_question.dart';
import '../../services/groq_api_client.dart';
import '../core/llm_gateway.dart';
import '../core/yatri_agent.dart';

/// Everything the receptionist needs to read one user message.
class ReceptionistInput {
  const ReceptionistInput({
    required this.text,
    required this.brief,
    this.pending,
    this.history = const [],
  });

  final String text;
  final TripBrief brief;

  /// The question currently on screen, so "the second one" or "yes" can map to
  /// an answer.
  final YatriQuestion? pending;

  /// The last few turns, oldest first.
  final List<GroqMessage> history;
}

/// The receptionist agent. The model does two narrow jobs — turn free text
/// into structured field updates, and phrase the next question warmly — while
/// every decision about what is missing, invalid or in conflict stays in the
/// deterministic domain layer.
class ReceptionistAgent implements YatriAgent<ReceptionistInput, Extraction> {
  ReceptionistAgent(this._llm, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LlmGateway _llm;
  final DateTime Function() _clock;

  @override
  String get name => 'Receptionist';

  @override
  Future<AgentResult<Extraction>> run(ReceptionistInput input) async {
    final result = await _llm.chatJson([
      GroqMessage('system', extractionPrompt(input, _clock())),
      ...input.history,
      GroqMessage('user', input.text),
    ], maxTokens: 1800);

    switch (result) {
      case GroqSuccess(:final content):
        // Even a reply the parser can't use is a valid "nothing extracted".
        return AgentOk(ExtractionParser.parse(content));
      case GroqFailure(:final kind, :final detail):
        return AgentErr(kind, detail);
    }
  }

  /// The model's warmer wording of a deterministic question, or null when it
  /// can't be reached — the caller then shows the template text.
  Future<String?> phrase(
    YatriQuestion question,
    TripBrief brief, {
    String? ack,
    List<BriefChange> changes = const [],
  }) async {
    final result = await _llm.chatJson(
      [
        GroqMessage('system', _phrasingSystem),
        GroqMessage(
          'user',
          jsonEncode({
            'question': question.defaultText,
            'reason': question.reason.name,
            'problem': question.hint,
            'acknowledge': [
              ?ack,
              for (final c in changes) 'Updated ${c.label}: ${c.from} → ${c.to}',
            ],
            'answerWidget': question.widget.name,
            'known': brief.toPromptSummary(),
          }),
        ),
      ],
      temperature: 0.6,
      maxTokens: 600,
      timeout: const Duration(seconds: 8),
    );
    if (result is! GroqSuccess) return null;

    final sub = ExtractionParser.jsonSubstring(result.content);
    if (sub == null) return null;
    try {
      final decoded = jsonDecode(sub);
      final message = decoded is Map<String, dynamic>
          ? (decoded['message'] as String?)?.trim()
          : null;
      if (message == null || message.isEmpty || message.length > 320) {
        return null;
      }
      return message;
    } catch (_) {
      return null;
    }
  }

  static const _phrasingSystem =
      'You are Yatri, the professional and helpful receptionist of a sustainable, '
      'accessibility-first trip planner. Rewrite the given question in one '
      'warm, natural message of at most 45 words. Ask exactly one question. '
      'If "acknowledge" has items, briefly acknowledge them first. If '
      '"problem" is set, explain it gently in your own words. Never list the '
      'answer options (the app shows them). Never invent trip details. '
      'CRITICAL REQUIREMENT: Strictly NEVER use any emojis or emoticons in your response. '
      'Keep the text clean and professional. '
      'Reply ONLY with JSON: {"message": "<text>"}.';

  /// The extraction system prompt. Public for tests.
  static String extractionPrompt(ReceptionistInput input, DateTime now) {
    final offset = now.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hh = offset.inHours.abs().toString().padLeft(2, '0');
    final mm = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday', //
    ];
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} ${weekdays[now.weekday - 1]}';

    final pending = input.pending;
    final pendingJson = pending == null
        ? 'none'
        : jsonEncode({
            'id': pending.id,
            'question': pending.defaultText,
            'options': [
              for (final o in pending.options) {'id': o.id, 'label': o.label},
            ],
          });

    return '''
You extract trip-planning details from a traveller's message for an Indian sustainable-travel app. Reply with ONE JSON object and nothing else. Never use emojis in any extracted text.

Today is $today, local timezone UTC$sign$hh:$mm. Currency is INR. Resolve relative dates ("next weekend", "the 15th") to local ISO times like 2026-10-10T09:00.

Already known: ${input.brief.toPromptSummary()}
Question currently shown to the traveller: $pendingJson

JSON shape (omit keys you have nothing for; never invent values):
{
 "updates": {
  "destination": {"value": "Munnar", "confidence": 0.95},
  "originCity": {"value": "Pune", "confidence": 0.9},
  "start": {"value": "2026-10-10T09:00", "confidence": 0.8, "timeAssumed": true},
  "end": {"value": "2026-10-12T18:00", "confidence": 0.8, "timeAssumed": true},
  "travellerCount": {"value": 4, "confidence": 0.9},
  "adults": 2, "seniors": 0, "children": 2, "women": 1, "childAges": [6, 9],
  "budgetMinInr": 20000, "budgetMaxInr": 40000,
  "transportModes": ["train","metroLocal","eBus","bus","sharedEv","selfDriveEv","carTaxi","flight"],
  "accessibilityNeeds": ["wheelchair","limitedMobility","visual","hearing","elderlyCare","serviceAnimal","none"],
  "womenSafety": ["womenOnlyTransport","verifiedStays","avoidLateNightTransit","sharedLiveLocation","none"],
  "style": "leisure|family|pilgrimage|adventure|heritage|nature|workation",
  "pace": "relaxed|balanced|packed",
  "stayTypes": ["ecoStay","homestay","hotel","hostel","resort"],
  "dietary": ["veg","vegan","jain","halal","noPreference"],
  "notes": "free text"
 },
 "pendingAnswer": {"optionIds": ["<id from the shown question>"]}  or  {"bool": true},
 "clarify": "one short question if the message is ambiguous or contradicts itself",
 "offTopic": false,
 "ack": "a short friendly acknowledgement of what you understood"
}

Rules:
- Only extract what the traveller stated or clearly implied. "Family of 4" means travellerCount 4 ONLY — never guess the adult/child breakdown, ages, women, budget or transport.
- If they give a date without a time, use 09:00 for the start and 18:00 for the end and set "timeAssumed": true.
- Use ONLY the enum ids listed above. Give every uncertain value a lower confidence (below 0.7 if you are guessing).
- If the message answers the question currently shown, fill "pendingAnswer" using its option ids (or {"bool": true/false} for yes/no) as well as any updates.
- If they correct an earlier value ("actually make it 5 people"), output the new value.
- If the message is unrelated to planning a trip, set "offTopic": true and leave "updates" empty.
''';
  }
}
