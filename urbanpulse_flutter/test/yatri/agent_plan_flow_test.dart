import 'dart:async';

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

/// Plays the traveller: answers every question the planner asks with the
/// option in [script] (question id prefix -> option id), else the recommended
/// one. Records what was asked.
Future<List<String>> playTraveller(YatriController c, Future<void> done, {Map<String, String> script = const {}}) async {
  final asked = <String>[];
  var finished = false;
  unawaited(done.whenComplete(() => finished = true));
  for (var i = 0; i < 800 && !finished; i++) {
    final q = c.activeQuestion?.question;
    if (q != null && q.id.startsWith('plan.') && !asked.contains(q.id)) {
      asked.add(q.id);
      final want = script.entries.where((e) => q.id.startsWith(e.key)).firstOrNull?.value;
      final o = q.options.firstWhere(
        (o) => o.id == want,
        orElse: () => q.options.firstWhere((o) => o.recommended, orElse: () => q.options.first),
      );
      await c.answer(q, ChoiceAnswer(o.id, o.label));
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  await done;
  return asked;
}

void main() {
  test('confirming the brief runs the agents, asks which stay, and builds the itinerary', () async {
    final (c, drafts) = await build();
    c.start();
    final done = c.confirmBrief(completeBrief());
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(c.entries.whereType<TaskGraphEntry>(), hasLength(1), reason: 'the live graph is in the chat');
    expect(c.phase, YatriPhase.planning);
    expect(c.busy, isTrue);

    final asked = await playTraveller(c, done, script: {'plan.hotels.choice': 'g100001-d4'});
    expect(asked, contains('plan.hotels.choice'));

    expect(c.phase, YatriPhase.done);
    expect(c.busy, isFalse);
    expect(drafts, isEmpty, reason: 'the phase-1 draft is only a fallback');
    final entry = c.entries.whereType<ItineraryEntry>().single;
    expect(entry.itinerary.hotel!.id, 'g100001-d4');
    expect(entry.itinerary.destination, 'Munnar');
    expect(entry.itinerary.days, isNotEmpty);
    expect(c.entries.whereType<AgentText>().last.text, contains('staying at Misty Hills Cottages'));
    expect(c.entries.whereType<PlanningEntry>(), isEmpty);

    await c.saveItinerary(entry);
    expect(entry.saved, isTrue);
  });

  test('a mid-plan question is answerable even though the plan is busy', () async {
    final (c, _) = await build();
    c.start();
    final done = c.confirmBrief(completeBrief().copyWith(budgetMaxInr: 6000));
    final asked = await playTraveller(c, done, script: {'plan.hotels.budget': 'accept'});
    expect(asked.any((id) => id.startsWith('plan.hotels.budget')), isTrue);
    expect(c.phase, YatriPhase.done);
    expect(c.entries.whereType<ItineraryEntry>(), hasLength(1));
  });

  test('restarting the conversation mid-plan stops the old plan and never touches the new chat', () async {
    final (c, _) = await build();
    c.start();
    final done = c.confirmBrief(completeBrief());
    final q = await waitForQuestion(c, 'plan.');
    expect(q.id, startsWith('plan.'));

    c.start(); // the traveller starts over while a question is open
    final fresh = c.entries.length;
    await done;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.entries.length, fresh, reason: 'nothing from the old run was added');
    expect(c.entries.single, isA<WelcomeEntry>());
    expect(c.entries.whereType<ItineraryEntry>(), isEmpty);
    expect(c.entries.whereType<TaskGraphEntry>(), isEmpty);
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
