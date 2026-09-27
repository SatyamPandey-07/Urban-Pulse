import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbanpulse/agents/core/llm_gateway.dart';
import 'package:urbanpulse/agents/planner/trip_plan_handoff_agent.dart';
import 'package:urbanpulse/agents/receptionist/receptionist_agent.dart';
import 'package:urbanpulse/models/trip_models.dart';
import 'package:urbanpulse/models/yatri_question.dart';
import 'package:urbanpulse/repositories/trip_brief_repository.dart';
import 'package:urbanpulse/repositories/trip_repository.dart';
import 'package:urbanpulse/services/groq_api_client.dart';
import 'package:urbanpulse/state/yatri_controller.dart';

import 'test_support.dart';

/// Scripted stand-in for Groq. Extraction and phrasing calls are told apart by
/// their system prompt.
class ScriptedLlmReply implements LlmGateway {
  ScriptedLlmReply({this.configured = true});

  bool configured;
  final List<String> extractions = [];
  bool failNextExtraction = false;
  bool phrasingWorks = true;
  int extractionCalls = 0;
  int nextBestCalls = 0;

  /// What the next-best-question call returns.
  String nextBestReply = '{"ask": []}';

  /// What the phrasing call returns.
  String phrasingReply = '{"message": "Warm rewrite of the question?"}';

  @override
  bool get isConfigured => configured;

  @override
  Future<GroqResult> chatJson(
    List<GroqMessage> messages, {
    double temperature = 0.1,
    int maxTokens = 1500,
    Duration? timeout,
  }) async {
    final system = messages.first.content;
    if (system.contains('You extract trip-planning details')) {
      extractionCalls++;
      if (failNextExtraction) {
        failNextExtraction = false;
        return const GroqFailure(GroqErrorKind.timeout);
      }
      return GroqSuccess(extractions.removeAt(0), 'scripted');
    }
    if (system.contains('whether to ask the traveller anything more')) {
      nextBestCalls++;
      return GroqSuccess(nextBestReply, 'scripted');
    }
    if (!phrasingWorks) return const GroqFailure(GroqErrorKind.timeout);
    return GroqSuccess(phrasingReply, 'scripted');
  }
}

TripPlan scriptedPlan() => const TripPlan(
  id: 'p1',
  destination: 'Munnar',
  title: 'Munnar',
  durationDays: 4,
  travelDates: 'Upcoming Journey',
  travelMode: 'Train',
  co2SavedKg: 12,
  pulsePointsEarned: 100,
  isCompleted: false,
  hotelName: 'Eco Stay',
  hotelRating: 4.5,
  isStepFreeAccessible: false,
  totalBudgetInr: 30000,
  aqiStatus: 'Good',
  transitCostInr: 4000,
  dailyItinerary: [],
);

Future<(YatriController, ScriptedLlmReply, List<Map<String, Object?>>)> build({
  bool hasKey = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final llm = ScriptedLlmReply(configured: hasKey);
  final handoffCalls = <Map<String, Object?>>[];
  final controller = YatriController(
    receptionist: ReceptionistAgent(llm, clock: () => testNow),
    handoff: TripPlanHandoffAgent(
      generator:
          ({
            required destination,
            required originCity,
            required days,
            required isAccessible,
            required travelStyle,
          }) async {
            handoffCalls.add({
              'destination': destination,
              'origin': originCity,
              'days': days,
              'accessible': isAccessible,
            });
            return scriptedPlan();
          },
    ),
    briefs: TripBriefRepository(prefs),
    trips: TripRepository(prefs),
    hasKey: () => hasKey,
    detectedCity: () => 'Pune',
    clock: () => testNow,
  );
  return (controller, llm, handoffCalls);
}

Future<void> answerActive(YatriController c, YatriAnswer a) async {
  final q = c.activeQuestion!.question;
  await c.answer(q, a);
}

void main() {
  test('runs the Munnar conversation from free text to a plan card', () async {
    final (c, llm, handoffCalls) = await build();
    c.start();
    expect(c.entries.single, isA<WelcomeEntry>());

    llm.extractions.add(
      '{"updates": {"destination": "Munnar", "travellerCount": 4},'
      ' "ack": "Munnar with family of four — lovely!"}',
    );
    await c.sendText('i want to visit Munnar with my family of 4');

    // Destination and total were extracted; origin is the first missing field
    // and the question uses the model's phrasing.
    expect(c.brief.destination, 'Munnar');
    expect(c.brief.travellerCount, 4);
    expect(c.brief.hasGroupBreakdown, isFalse);
    expect(c.activeQuestion!.question.id, 'origin');
    expect(c.activeQuestion!.question.displayText, 'Warm rewrite of the question?');
    expect(c.busy, isFalse);

    await answerActive(c, const ChoiceAnswer('Pune', 'Use my location: Pune'));
    expect(c.activeQuestion!.question.id, 'dates');

    await answerActive(
      c,
      DateRangeAnswer(DateTime(2026, 10, 10, 9), DateTime(2026, 10, 13, 18)),
    );
    // Travellers was already known, so the group breakdown is next.
    expect(c.activeQuestion!.question.id, 'group');

    await answerActive(
      c,
      const GroupAnswer(adults: 2, seniors: 0, children: 2, women: 1, childAges: [6, 9]),
    );
    expect(c.activeQuestion!.question.id, 'womenSafety');

    await answerActive(c, const MultiChoiceAnswer({'verifiedStays'}, ['Verified stays']));
    expect(c.activeQuestion!.question.id, 'accessibility');
    expect(c.activeQuestion!.question.options, isNotEmpty);

    await answerActive(c, const MultiChoiceAnswer({'wheelchair'}, ['Wheelchair']));
    expect(c.activeQuestion!.question.id, 'a11y.wheelchair.type');
    await answerActive(c, const ChoiceAnswer('manual', 'Manual'));
    expect(c.activeQuestion!.question.id, 'a11y.wheelchair.facilities');
    await answerActive(c, const MultiChoiceAnswer({'lift'}, ['Lift']));

    expect(c.activeQuestion!.question.id, 'transport');
    await answerActive(c, const MultiChoiceAnswer({'train'}, ['Train']));
    expect(c.activeQuestion!.question.id, 'budget');
    await answerActive(c, const BudgetAnswer(20000, 40000));

    // The model was asked once whether more detail would help and said no.
    expect(llm.nextBestCalls, 1);
    expect(c.phase, YatriPhase.review);
    expect(c.entries.last, isA<ReviewReadyEntry>());
    expect(c.report.isComplete, isTrue);

    await c.confirmBrief(c.brief);
    expect(c.phase, YatriPhase.done);
    final plan = c.entries.whereType<PlanEntry>().single;
    expect(plan.plan.travelDates, '10 Oct – 13 Oct 2026');
    expect(handoffCalls.single, {
      'destination': 'Munnar',
      'origin': 'Pune',
      'days': 4,
      'accessible': true,
    });

    await c.saveTrip(plan);
    expect(plan.saved, isTrue);
    expect(c.trips.getTrips(), hasLength(1));
    expect(c.briefs.latest()!.destination, 'Munnar');
  });

  test('a mid-flow correction re-asks the group with a conflict hint', () async {
    final (c, llm, _) = await build();
    c.start();
    llm.extractions.add('{"updates": {"destination": "Coorg", "travellerCount": 4}}');
    await c.sendText('Coorg for four');
    await answerActive(c, const ChoiceAnswer('Pune', 'Pune'));
    await answerActive(
      c,
      DateRangeAnswer(DateTime(2026, 10, 10, 9), DateTime(2026, 10, 12, 18)),
    );
    await answerActive(
      c,
      const GroupAnswer(adults: 4, seniors: 0, children: 0, women: 0, childAges: []),
    );
    expect(c.brief.hasGroupBreakdown, isTrue);

    llm.extractions.add('{"updates": {"travellerCount": 5}}');
    await c.sendText('actually make it 5 people');

    expect(c.brief.travellerCount, 5);
    final q = c.activeQuestion!.question;
    expect(q.id, 'group');
    expect(q.reason, IssueKind.conflict);
    expect(q.hint, contains('5'));
  });

  test('an invalid card answer keeps the card open with a hint', () async {
    final (c, llm, _) = await build();
    c.start();
    llm.extractions.add('{"updates": {"destination": "Hampi"}}');
    await c.sendText('Hampi');
    await answerActive(c, const ChoiceAnswer('Pune', 'Pune'));

    await answerActive(
      c,
      DateRangeAnswer(DateTime(2026, 9, 1, 9), DateTime(2026, 9, 3, 9)),
    );
    final active = c.activeQuestion!;
    expect(active.question.id, 'dates');
    expect(active.question.hint, contains('past'));
    expect(active.question.attempt, 1);
  });

  test('an LLM failure shows a retry card and retry succeeds', () async {
    final (c, llm, _) = await build();
    c.start();
    llm.failNextExtraction = true;
    await c.sendText('Munnar please');

    final error = c.entries.last as ErrorEntry;
    expect(error.kind, GroqErrorKind.timeout);
    expect(c.busy, isFalse);

    llm.extractions.add('{"updates": {"destination": "Munnar"}}');
    await c.retry(error);
    expect(c.brief.destination, 'Munnar');
    expect(c.entries.whereType<UserText>(), hasLength(1), reason: 'no duplicate bubble');
    expect(c.activeQuestion, isNotNull);
  });

  test('falls back to template wording when phrasing fails', () async {
    final (c, llm, _) = await build();
    c.start();
    llm.phrasingWorks = false;
    llm.extractions.add('{"updates": {"destination": "Munnar"}, "ack": "Nice choice!"}');
    await c.sendText('Munnar');

    expect(c.activeQuestion!.question.displayText, 'Which city will you start from?');
    expect(
      c.entries.whereType<AgentText>().map((e) => e.text),
      contains('Nice choice!'),
    );
  });

  test('without a key the chat shows the key card and never calls the model', () async {
    final (c, llm, _) = await build(hasKey: false);
    c.start();
    expect(c.entries.single, isA<NoKeyEntry>());
    expect(c.canType, isFalse);

    await c.sendText('Munnar');
    expect(llm.extractionCalls, 0);
  });

  test('nothing understood keeps the current card and explains', () async {
    final (c, llm, _) = await build();
    c.start();
    llm.extractions.add('{"updates": {"destination": "Munnar"}}');
    await c.sendText('Munnar');
    final before = c.activeQuestion!;

    llm.extractions.add('{}');
    await c.sendText('hmm');
    expect(c.activeQuestion, same(before));
    expect(c.entries.last, isA<AgentText>());
  });
}
