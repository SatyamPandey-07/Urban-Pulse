import 'dart:convert';

import '../../domain/trip_brief/brief_merger.dart';
import '../../domain/trip_brief/extraction.dart';
import '../../domain/trip_brief/next_best.dart';
import '../../domain/trip_brief/question_catalog.dart';
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

/// The model's wording of a question, plus its widget choice when the question
/// allows one.
class PhrasedQuestion {
  const PhrasedQuestion(this.message, this.widget);

  final String message;
  final String? widget;
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

  /// The model's warmer wording of a deterministic question — and, where the
  /// question allows it, its choice of answer widget — or null when it can't
  /// be reached. The caller then shows the template text and default widget.
  Future<PhrasedQuestion?> phrase(
    YatriQuestion question,
    TripBrief brief, {
    String? ack,
    List<BriefChange> changes = const [],
  }) async {
    final variants = QuestionCatalog.variantsFor(question.id);
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
            if (variants.isNotEmpty) 'widgetChoices': variants,
            'known': brief.toPromptSummary(),
          }),
        ),
      ],
      temperature: 0.6,
      maxTokens: 600,
      timeout: const Duration(seconds: 8),
    );
    if (result is! GroqSuccess) return null;
    return parsePhrasing(result.content, question.id);
  }

  /// Reads the phrasing reply. The widget is kept only when it is one of the
  /// allowed choices for [questionId]. Public for tests.
  static PhrasedQuestion? parsePhrasing(String raw, String questionId) {
    final sub = ExtractionParser.jsonSubstring(raw);
    if (sub == null) return null;
    try {
      final decoded = jsonDecode(sub);
      if (decoded is! Map<String, dynamic>) return null;
      final message = (decoded['message'] as String?)?.trim();
      if (message == null || message.isEmpty || message.length > 320) {
        return null;
      }
      return PhrasedQuestion(
        message,
        QuestionCatalog.validVariant(questionId, decoded['widget'] as String?),
      );
    } catch (_) {
      return null;
    }
  }

  /// The next-best-question step: with every mandatory field valid, ask the
  /// model whether up to [NextBestQuestion.maxAsks] optional questions would
  /// materially improve the plan. Returns their ids; empty means "enough".
  /// Costs one small call, and none at all when the brief is already rich.
  Future<List<String>> nextBest(TripBrief brief) async {
    final candidates = NextBestQuestion.candidates(brief);
    if (!NextBestQuestion.worthConsulting(brief)) return const [];

    final result = await _llm.chatJson(
      [
        GroqMessage('system', _nextBestSystem),
        GroqMessage(
          'user',
          jsonEncode({
            'brief': brief.toPromptSummary(),
            'candidates': {
              'style': 'trip style: leisure, family, pilgrimage, adventure, heritage, nature, workation',
              'pace': 'relaxed, balanced or packed days',
              'stay': 'stay type: eco stay, homestay, hotel, hostel, resort',
              'dietary': 'food preferences',
            }..removeWhere((k, _) => !candidates.contains(k)),
          }),
        ),
      ],
      temperature: 0.2,
      maxTokens: 400,
      timeout: const Duration(seconds: 8),
    );
    if (result is! GroqSuccess) return const [];
    return NextBestQuestion.parse(result.content, candidates);
  }

  static const _nextBestSystem =
      'You help a sustainable, accessibility-first trip planner decide whether '
      'to ask the traveller anything more before planning. The essentials are '
      'already collected. Ask about an optional topic ONLY if the answer would '
      'materially change the plan for THIS trip; otherwise ask nothing. Prefer '
      'nothing over a low-value question, never ask more than 2, and choose '
      'only from the given candidate ids. Reply ONLY with JSON: '
      '{"ask": ["<candidate id>", ...]} (an empty list means enough).';

  static const _phrasingSystem =
      'You are Yatri, the professional and helpful receptionist of a sustainable, '
      'accessibility-first trip planner. Rewrite the given question in one '
      'warm, natural message of at most 45 words. Ask exactly one question. '
      'If "acknowledge" has items, briefly acknowledge them first. If '
      '"problem" is set, explain it gently in your own words. Never list the '
      'answer options (the app shows them). Never invent trip details. '
      'If "widgetChoices" is present, also choose the one answer widget that '
      'suits this traveller best (for dates: "calendar" when they have given no '
      'timing at all, "presets" when they gave a rough one such as a weekend; '
      'for budget: "tiers" for a quick pick, "slider" when they mentioned a '
      'specific amount; for travellers: "list" normally, "stepper" for a large '
      'or unusual group) and return it as "widget". '
      'CRITICAL REQUIREMENT: Strictly NEVER use any emojis or emoticons in your response. '
      'Keep the text clean and professional. '
      'Reply ONLY with JSON: {"message": "<text>", "widget": "<choice, only if widgetChoices was given>"}.';

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
  "accessibilityNeeds": ["wheelchair","limitedMobility","visual","hearing","elderlyCare","serviceAnimal","cognitiveSensory","otherSpecial","none"],
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
- Only extract what the traveller stated or clearly implied. Never guess budget or transport.
- GROUP BREAKDOWN: fill adults / seniors / children / women whenever the traveller's words make them unambiguous, so the app does not have to ask. Always give travellerCount as well, and when you can work out the breakdown give ALL of adults, seniors and children (use 0 for a group that is clearly absent). Examples:
  "4 men" or "four guys" -> travellerCount 4, adults 4, seniors 0, children 0, women 0.
  "3 women friends" or "3 girls" -> travellerCount 3, adults 3, seniors 0, children 0, women 3.
  "3 friends" -> travellerCount 3, adults 3, seniors 0, children 0 (leave women out: their gender is not stated).
  "me and my wife" or "a couple" -> travellerCount 2, adults 2, seniors 0, children 0 (leave women out unless stated).
  "solo trip" -> travellerCount 1, adults 1, seniors 0, children 0.
  "me, my parents and 2 kids" -> children 2 (give childAges only if stated), and only give the rest if the count of parents and the total are clear.
  "family of 4" -> travellerCount 4 ONLY: a family's split is not clear, so do not guess the breakdown, ages or women.
  Never guess children's ages, and never guess the number of women when gender is not stated.
- If they give a date without a time, use 09:00 for the start and 18:00 for the end and set "timeAssumed": true.
- Use ONLY the enum ids listed above. Give every uncertain value a lower confidence (below 0.7 if you are guessing).
- If the message answers the question currently shown, fill "pendingAnswer" using its option ids (or {"bool": true/false} for yes/no) as well as any updates.
- If they correct an earlier value ("actually make it 5 people"), output the new value.
- If the message is unrelated to planning a trip, set "offTopic": true and leave "updates" empty.
''';
  }
}
