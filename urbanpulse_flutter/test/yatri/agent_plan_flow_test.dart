import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbanpulse/agents/planner/trip_plan_handoff_agent.dart';
import 'package:urbanpulse/agents/receptionist/receptionist_agent.dart';
import 'package:urbanpulse/models/yatri_question.dart';
import 'package:urbanpulse/repositories/trip_brief_repository.dart';
import 'package:urbanpulse/repositories/trip_repository.dart';
import 'package:urbanpulse/state/yatri_controller.dart';

import '../agents/hotel_world.dart';
import '../agents/planner_orchestrator_test.dart' show toolkitFor;
import 'receptionist_flow_test.dart' show FakeLlm, fakePlan;
import 'test_support.dart';

Future<(YatriController, List<String>)> build({Map<String, LatLng>? places, HotelWorld? world}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final drafts = <String>[];
  final c = YatriController(
    receptionist: ReceptionistAgent(FakeLlm(), clock: () => testNow),
    handoff: TripPlanHandoffAgent(
      generator:
          ({
            required destination,
            required originCity,
            required days,
            required isAccessible,
            required travelStyle,
          }) async {
            drafts.add(destination);
            return fakePlan();
          },
    ),
    briefs: TripBriefRepository(prefs),
    trips: TripRepository(prefs),
    hasKey: () => true,
    clock: () => testNow,
    toolkit: toolkitFor(world ?? HotelWorld(), places: places),
  );
  return (c, drafts);
}

Future<YatriQuestion> waitForQuestion(YatriController c, String idPrefix) async {
  for (var i = 0; i < 300; i++) {
    final q = c.activeQuestion?.question;
    if (q != null && q.id.startsWith(idPrefix)) return q;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('no question starting with $idPrefix; active: ${c.activeQuestion?.question.id}');
}

void main() {
  test('confirming the brief runs the agents, asks which stay, and puts it in the plan', () async {
    final (c, drafts) = await build();
    c.start();
    final done = c.confirmBrief(completeBrief());

    final q = await waitForQuestion(c, 'plan.hotels.choice');
    expect(c.entries.whereType<TaskGraphEntry>(), hasLength(1), reason: 'the live graph is in the chat');
    expect(c.phase, YatriPhase.planning);
    expect(c.busy, isTrue);
    final pick = q.hotels[1];
    await c.answer(q, ChoiceAnswer(pick.id, pick.name));
    await done;

    expect(c.phase, YatriPhase.done);
    expect(c.busy, isFalse);
    expect(drafts, ['Munnar'], reason: 'the day-by-day draft ran once, alongside');
    final plan = c.entries.whereType<PlanEntry>().single.plan;
    expect(plan.hotelName, pick.name);
    expect(plan.hotelRating, pick.rating);
    final text = c.entries.whereType<AgentText>().last.text;
    expect(text, contains('staying at ${pick.name}'));
    expect(c.entries.whereType<PlanningEntry>(), isEmpty);
    // The traveller's choice shows in the chat as their answer.
    expect(c.entries.whereType<UserText>().map((e) => e.text), contains(pick.name));
  });

  test('a mid-plan question is answerable even though the plan is busy', () async {
    final (c, _) = await build();
    c.start();
    final done = c.confirmBrief(completeBrief().copyWith(budgetMaxInr: 6000));

    final budget = await waitForQuestion(c, 'plan.hotels.budget');
    expect(c.busy, isTrue);
    expect(budget.agent, 'yatri');
    await c.answer(budget, const ChoiceAnswer('accept', 'Keep it'));
    final choice = await waitForQuestion(c, 'plan.hotels.choice');
    await c.answer(choice, const ChoiceAnswer('auto', 'Let Yatri choose'));
    await done;
    expect(c.phase, YatriPhase.done);
    expect(c.entries.whereType<PlanEntry>(), hasLength(1));
  });

  test('a destination that is not on the map is handed back to the conversation', () async {
    final (c, _) = await build(places: {});
    c.start();
    await c.confirmBrief(completeBrief().copyWith(destination: 'Atlantis'));

    expect(c.phase, YatriPhase.intake);
    expect(c.entries.whereType<PlanEntry>(), isEmpty);
    expect(c.entries.whereType<AgentText>().map((e) => e.text).join(' '), contains('Atlantis'));
    expect(c.brief.destination, isNull, reason: 'the bad destination is taken back');
    expect(c.activeQuestion?.question.id, 'destination', reason: 'and asked for again');
    expect(c.busy, isFalse);
  });

  test('without a toolkit the phase-1 planner is used unchanged', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = YatriController(
      receptionist: ReceptionistAgent(FakeLlm(), clock: () => testNow),
      handoff: TripPlanHandoffAgent(
        generator: ({required destination, required originCity, required days, required isAccessible, required travelStyle}) async => fakePlan(),
      ),
      briefs: TripBriefRepository(prefs),
      trips: TripRepository(prefs),
      hasKey: () => true,
      clock: () => testNow,
    );
    c.start();
    await c.confirmBrief(completeBrief());
    expect(c.entries.whereType<TaskGraphEntry>(), isEmpty);
    expect(c.entries.whereType<PlanEntry>().single.plan.hotelName, 'Eco Stay');
  });
}
