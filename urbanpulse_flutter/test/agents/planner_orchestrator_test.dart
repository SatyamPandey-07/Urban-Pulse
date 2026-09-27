import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/agents/runtime/agent_kind.dart';
import 'package:urbanpulse/agents/runtime/agent_toolkit.dart';
import 'package:urbanpulse/agents/runtime/plan_clock.dart';
import 'package:urbanpulse/agents/runtime/task_graph.dart';
import 'package:urbanpulse/agents/tools/web_search_tool.dart';
import 'package:urbanpulse/agents/yatri/planner_orchestrator.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/models/yatri_question.dart';
import 'package:urbanpulse/services/data/ai_estimator.dart';
import 'package:urbanpulse/services/data/data_cache.dart';
import 'package:urbanpulse/services/data/forecast_client.dart';
import 'package:urbanpulse/services/data/overpass_client.dart';
import 'package:urbanpulse/services/data/wikipedia_client.dart';
import 'package:urbanpulse/services/data/xotelo_client.dart';
import 'package:urbanpulse/services/place_geocoder.dart';

import '../yatri/test_support.dart';
import 'scripted.dart';
import 'hotel_world.dart';

class _Geocoder extends PlaceGeocoder {
  _Geocoder(this.places);

  final Map<String, LatLng> places;

  @override
  Future<GeoArea?> lookupArea(String name) async {
    final p = places[name.trim().toLowerCase()];
    return p == null ? null : GeoArea(p);
  }
}

AgentToolkit toolkitFor(HotelWorld world, {Map<String, LatLng>? places, ScriptedLlm? llm}) {
  final cache = MemoryCache();
  final client = world.client;
  final model = llm ?? (ScriptedLlm()..configured = false);
  return AgentToolkit(
    llm: model,
    cache: cache,
    client: client,
    xotelo: XoteloClient(client: client, cache: cache),
    overpass: OverpassClient(client: client, cache: cache),
    wikipedia: WikipediaClient(client: client, cache: cache),
    forecast: ForecastClient(client: client, cache: cache),
    geocoder: _Geocoder(places ?? {'munnar': munnarCenter}),
    estimator: AiEstimator(model),
    tavily: TavilySearchProvider(keys: const ['test-key'], client: client),
  );
}

/// What the traveller does: answers by option id, in order, recording what was asked.
class Traveller {
  Traveller([this.script = const {}]);

  /// Question id (or prefix) -> option id to pick.
  final Map<String, String> script;
  final List<YatriQuestion> asked = [];
  bool sawWaitingUser = false;
  PlannerOrchestrator? orchestrator;

  Future<YatriAnswer> call(YatriQuestion q) async {
    asked.add(q);
    sawWaitingUser = sawWaitingUser || (orchestrator?.graph.hasWaitingUser ?? false);
    for (final e in script.entries) {
      if (q.id.startsWith(e.key)) {
        final opt = q.options.firstWhere((o) => o.id == e.value, orElse: () => q.options.first);
        return ChoiceAnswer(opt.id, opt.label);
      }
    }
    final o = q.options.firstWhere((o) => o.recommended, orElse: () => q.options.first);
    return ChoiceAnswer(o.id, o.label);
  }
}

PlannerOrchestrator orchestratorFor(AgentToolkit tk, Traveller who, {PlanClock? clock}) {
  final o = PlannerOrchestrator(toolkit: tk, ask: who.call, clock: clock, hotelsOnly: true);
  who.orchestrator = o;
  return o;
}

TripBrief briefWith({int? budget, Set<AccessibilityNeed>? needs, String? destination}) => completeBrief().copyWith(
  budgetMaxInr: budget,
  accessibilityNeeds: needs,
  destination: destination,
);

void main() {
  group('the happy path', () {
    test('Yatri allocates Atithi and Hisab, then asks which stay the traveller wants', () async {
      final who = Traveller({'plan.hotels.choice': 'g100001-d4'});
      final o = orchestratorFor(toolkitFor(HotelWorld()), who);
      final out = await o.run(briefWith());

      expect(out.status, PlanStatus.planned);
      expect(out.hotel!.id, 'g100001-d4');
      expect(out.hotel!.name, 'Misty Hills Cottages');
      expect(out.center, isNotNull);

      final q = who.asked.single;
      expect(q.id, 'plan.hotels.choice');
      expect(q.widget, AnswerWidget.hotelChoice);
      expect(q.agent, 'yatri');
      expect(q.why, isNotEmpty);
      expect(q.hotels.length, inInclusiveRange(2, 5));
      expect(q.options.last.id, PlannerOrchestrator.autoPick);
      expect(q.options.map((x) => x.id), containsAll(q.hotels.map((h) => h.id)));
    });

    test('the task graph shows the specialists, their order and the feed', () async {
      final who = Traveller();
      final o = orchestratorFor(toolkitFor(HotelWorld()), who);
      await o.run(briefWith());

      final ids = o.graph.nodes.map((n) => n.id).toList();
      expect(ids, containsAll(['yatri.plan', 'atithi.hotels.0', 'hisab.hotels.0']));
      expect(o.graph.node('atithi.hotels.0')!.delegatedBy, 'yatri.plan');
      expect(o.graph.node('hisab.hotels.0')!.parentIds, contains('atithi.hotels.0'));
      expect(o.graph.nodes.every((n) => n.status.isFinished), isTrue, reason: 'nothing left running');

      final feed = o.graph.events.map((e) => e.text).join(' | ');
      expect(feed, contains('allocated the hotel search to Atithi'));
      expect(feed, contains('Hisab'));
      expect(feed, contains('found'));
      expect(o.graph.events.where((e) => e.agent == AgentKind.yatri && e.kind == FeedKind.ask), isNotEmpty);
      expect(o.graph.events.every((e) => e.why == null || e.why!.trim().isNotEmpty), isTrue);
    });

    test('“Let Yatri choose” takes the best-ranked stay', () async {
      final who = Traveller({'plan.hotels.choice': PlannerOrchestrator.autoPick});
      final o = orchestratorFor(toolkitFor(HotelWorld()), who);
      final out = await o.run(briefWith());
      expect(out.hotel!.id, who.asked.single.hotels.first.id);
    });

    test('the plan clock stops while the traveller is being asked', () async {
      final who = Traveller();
      final o = orchestratorFor(toolkitFor(HotelWorld()), who);
      await o.run(briefWith());
      expect(who.sawWaitingUser, isTrue, reason: 'the asking node is in the waiting state');
    });

    test('a weird answer (not a choice) falls back to the recommended option', () async {
      final o = PlannerOrchestrator(
        toolkit: toolkitFor(HotelWorld()),
        ask: (q) async => const BoolAnswer(true),
        hotelsOnly: true,
      );
      final out = await o.run(briefWith());
      expect(out.status, PlanStatus.planned);
      expect(out.hotel, isNotNull);
    });

    test('a question that throws never stops the plan', () async {
      final o = PlannerOrchestrator(toolkit: toolkitFor(HotelWorld()), ask: (q) => throw StateError('ui gone'), hotelsOnly: true);
      final out = await o.run(briefWith());
      expect(out.status, PlanStatus.planned);
      expect(out.hotel, isNotNull);
    });
  });

  group('when goals collide, Yatri asks', () {
    test('a budget nothing fits: Hisab flags it, the traveller raises it, Atithi searches again', () async {
      // 6000 total over 3 nights and one room gives a cap of 800 a night.
      final who = Traveller({'plan.hotels.budget': 'raise'});
      final o = orchestratorFor(toolkitFor(HotelWorld()), who);
      final out = await o.run(briefWith(budget: 6000, needs: const {AccessibilityNeed.none}));

      expect(who.asked.first.id, startsWith('plan.hotels.budget@'));
      final q = who.asked.first;
      expect(q.agent, 'yatri');
      expect(q.reason, IssueKind.conflict);
      expect(q.why, contains('Hisab'));
      expect(q.options.map((x) => x.id), containsAll(['raise', 'accept']));
      expect(q.options.firstWhere((x) => x.id == 'raise').recommended, isTrue);
      expect(q.defaultText, contains('₹'));

      expect(o.graph.node('atithi.hotels.1'), isNotNull, reason: 'Atithi was re-tasked with the raised budget');
      expect(o.graph.events.map((e) => e.text).join('|'), contains('re-tasked Atithi'));
      expect(out.hotel, isNotNull);
      // The same problem is not asked twice.
      expect(who.asked.where((x) => x.id.startsWith('plan.hotels.budget@800')).length, 1);
    });

    test('keeping the budget and accepting shows the closest options without asking again', () async {
      final who = Traveller({'plan.hotels.budget': 'accept'});
      final o = orchestratorFor(toolkitFor(HotelWorld()), who);
      final out = await o.run(briefWith(budget: 6000));
      expect(out.hotel, isNotNull);
      expect(o.graph.node('atithi.hotels.1'), isNull);
      expect(who.asked.map((q) => q.id), ['plan.hotels.budget@800', 'plan.hotels.choice']);
    });

    test('no hotel is accessible: the question offers a wider search and the closest options', () async {
      final world = HotelWorld(xotelo: const [
        WorldHotel('g100001-d3', 'Budget Inn Munnar', totalInr: 4200, pageText: 'Stairs only to reach the rooms.'),
        WorldHotel('g100001-d5', 'Grand Plaza Munnar', totalInr: 16800, pageText: 'Not wheelchair accessible in the older wing.'),
        WorldHotel('g100001-d7', 'Roadside Lodge', totalInr: 5000, dLat: 0.006, pageText: 'No lift. Steep stairs only.'),
      ]);
      final who = Traveller({'plan.hotels.access': 'accept'});
      final o = orchestratorFor(toolkitFor(world), who);
      final out = await o.run(briefWith(needs: const {AccessibilityNeed.wheelchair}));

      final q = who.asked.first;
      expect(q.id, startsWith('plan.hotels.access@'));
      expect(q.defaultText, contains('wheelchair access'));
      expect(q.options.map((x) => x.id), containsAll(['wider', 'accept']));
      expect(q.options.firstWhere((x) => x.id == 'wider').recommended, isTrue);
      expect(q.why, contains('unconfirmed'));
      expect(out.status, PlanStatus.planned);
    });

    test('searching wider goes round again and is never repeated forever', () async {
      // Nothing ever fits: the traveller keeps asking to widen. Terminates.
      final world = HotelWorld(xotelo: const [
        WorldHotel('g100001-d3', 'Budget Inn Munnar', totalInr: 4200, pageText: 'Stairs only to reach the rooms.'),
        WorldHotel('g100001-d5', 'Grand Plaza Munnar', totalInr: 16800, pageText: 'Not wheelchair accessible in the older wing.'),
        WorldHotel('g100001-d7', 'Roadside Lodge', totalInr: 5000, dLat: 0.006, pageText: 'No lift. Steep stairs only.'),
      ]);
      final who = Traveller({'plan.hotels.access': 'wider', 'plan.hotels.budget': 'wider', 'plan.hotels.none': 'wider'});
      final o = orchestratorFor(toolkitFor(world), who);
      final out = await o.run(briefWith(needs: const {AccessibilityNeed.wheelchair}, budget: 6000));
      expect(out.status, PlanStatus.planned);
      expect(who.asked.length, lessThan(8));
      expect(o.graph.nodes.every((n) => n.status.isFinished), isTrue);
    });

    test('the traveller can choose to continue without a hotel', () async {
      final world = HotelWorld(xoteloDown: true, geoapifyDown: true, overpassDown: true, tripAdvisorDown: true);
      final who = Traveller({'plan.hotels.none': 'skip'});
      final o = orchestratorFor(toolkitFor(world), who);
      final out = await o.run(briefWith());
      expect(who.asked.first.id, startsWith('plan.hotels.none@'));
      expect(out.status, PlanStatus.planned);
      expect(out.hotel, isNull);
      expect(out.summary, contains('without a hotel'));
    });
  });

  group('robustness', () {
    test('a place that is not on the map is handed back, not planned', () async {
      final who = Traveller();
      final o = orchestratorFor(toolkitFor(HotelWorld()), who);
      final out = await o.run(briefWith(destination: 'Atlantis, the sunken city'));
      expect(out.status, PlanStatus.unlocatable);
      expect(out.summary, contains('Atlantis'));
      expect(who.asked, isEmpty);
      expect(o.graph.node('atithi.hotels.0'), isNull, reason: 'no specialist is sent to a place that does not exist');
    });

    test('an incomplete brief is a failure, not a crash', () async {
      final o = orchestratorFor(toolkitFor(HotelWorld()), Traveller());
      final out = await o.run(TripBrief.empty(testNow));
      expect(out.status, PlanStatus.failed);
    });

    test('however long the plan has run, the traveller is still asked, never overruled', () async {
      var now = DateTime(2026, 1, 1, 12);
      final who = Traveller();
      final o = orchestratorFor(toolkitFor(HotelWorld()), who, clock: PlanClock(now: () => now));
      o.clock.start();
      now = now.add(const Duration(hours: 2));
      final out = await o.run(briefWith(budget: 6000));
      expect(who.asked, isNotEmpty, reason: 'a long plan still puts the choices to the traveller');
      expect(out.hotel, isNotNull);
      expect(o.graph.events.map((e) => e.text).join('|'), isNot(contains('time is short')));
    });

    test('with every data source down it still ends, with a clear outcome', () async {
      final world = HotelWorld(xoteloDown: true, geoapifyDown: true, overpassDown: true, tripAdvisorDown: true);
      final o = orchestratorFor(toolkitFor(world), Traveller());
      final out = await o.run(briefWith());
      expect(out.status, PlanStatus.planned);
      expect(o.graph.nodes.every((n) => n.status.isFinished), isTrue);
    });

    test('chaos: random outages, needs, budgets and random answers always end cleanly', () async {
      final rng = Random(2026);
      for (var i = 0; i < 60; i++) {
        final needs = {
          for (final n in AccessibilityNeed.values)
            if (rng.nextInt(4) == 0) n,
        };
        final world = HotelWorld(
          xoteloDown: rng.nextInt(4) == 0,
          geoapifyDown: rng.nextInt(3) == 0,
          overpassDown: rng.nextInt(3) == 0,
          tripAdvisorDown: rng.nextInt(3) == 0,
          ratesDown: rng.nextInt(4) == 0,
        );
        final asked = <String>[];
        late PlannerOrchestrator o;
        o = PlannerOrchestrator(
          hotelsOnly: true,
          toolkit: toolkitFor(world),
          ask: (q) async {
            asked.add(q.id);
            switch (rng.nextInt(6)) {
              case 0:
                throw StateError('the UI went away');
              case 1:
                return const BoolAnswer(false);
              default:
                final opt = q.options[rng.nextInt(q.options.length)];
                return ChoiceAnswer(opt.id, opt.label);
            }
          },
        );
        final budget = [null, 1, 900, 6000, 40000, 5000000][rng.nextInt(6)];
        final out = await o.run(briefWith(budget: budget, needs: needs.isEmpty ? null : needs));
        final where = 'run $i needs=$needs budget=$budget asked=$asked';
        expect(out.status, PlanStatus.planned, reason: where);
        expect(asked.length, lessThan(12), reason: where);
        expect(o.graph.nodes.every((n) => n.status.isFinished), isTrue, reason: where);
        expect(o.board.debugRunning, 0, reason: 'no concurrency slot leaked: $where');
        if (out.hotel != null) expect(out.hotels!.options.map((h) => h.id), contains(out.hotel!.id), reason: where);
      }
    });

    test('budgets and party sizes are turned into a sane hotel search', () async {
      final world = HotelWorld();
      final o = orchestratorFor(toolkitFor(world), Traveller());
      await o.run(briefWith());
      // 2 adults + 2 children: one room, two adults, three nights.
      expect(world.hitsFor('/rates'), greaterThan(0));
    });
  });
}
