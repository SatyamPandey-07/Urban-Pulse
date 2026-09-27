import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/runtime/agent_kind.dart';
import 'package:urbanpulse/domain/regional_defaults.dart';
import 'package:urbanpulse/services/data/ai_estimator.dart';
import 'package:urbanpulse/services/groq_api_client.dart';

import '../agents/scripted.dart';

void main() {
  group('AiEstimator.fill', () {
    test('returns the answered fields, every one marked as an estimate', () async {
      final llm = ScriptedLlm(['{"nightlyInr": 2800, "stars": 3, "unknown": null}']);
      final r = (await AiEstimator(llm).fill(
        agent: AgentKind.atithi,
        subject: 'Hotel Sunrise, Munnar',
        fields: {'nightlyInr': 'typical double-room price', 'stars': 'star rating', 'unknown': 'x', 'missing': 'y'},
        known: {'rating': 4.2},
      ))!;
      expect(r.keys, unorderedEquals(['nightlyInr', 'stars']));
      expect(r['nightlyInr']!.value, 2800);
      expect(r['nightlyInr']!.provenance.isEstimated, isTrue);
      expect(r['nightlyInr']!.provenance.source, 'AI estimate');
      // What is already known is sent to the model, and the calling agent is used.
      expect(llm.asked.single.agent, AgentKind.atithi);
      expect(llm.asked.single.messages.last.content, contains('"rating":4.2'));
    });

    test('a failed or unusable reply is null so the caller uses defaults', () async {
      expect(await AiEstimator(ScriptedLlm()..fallback = null).fill(agent: AgentKind.atithi, subject: 's', fields: {'a': 'b'}), isNull);
      expect(await AiEstimator(ScriptedLlm(['no json at all'])).fill(agent: AgentKind.atithi, subject: 's', fields: {'a': 'b'}), isNull);
      expect(await AiEstimator(ScriptedLlm([const GroqFailure(GroqErrorKind.rateLimited)])).fill(agent: AgentKind.atithi, subject: 's', fields: {'a': 'b'}), isNull);
    });

    test('nested objects are not accepted as a field value', () async {
      final llm = ScriptedLlm(['{"a": {"nested": true}, "b": 5}']);
      final r = (await AiEstimator(llm).fill(agent: AgentKind.atithi, subject: 's', fields: {'a': 'x', 'b': 'y'}))!;
      expect(r.keys, ['b']);
    });
  });

  group('AiEstimator.fillMany', () {
    test('one call fills many items and skips the ones the model left out', () async {
      final llm = ScriptedLlm(['{"items": {"h1": {"nightlyInr": 2500}, "h2": {"nightlyInr": null}}}']);
      final r = (await AiEstimator(llm).fillMany(
        agent: AgentKind.atithi,
        subject: 'hotels in Munnar',
        items: {'h1': {'name': 'A'}, 'h2': {'name': 'B'}, 'h3': {'name': 'C'}},
        fields: {'nightlyInr': 'price'},
      ))!;
      expect(llm.asked, hasLength(1));
      expect(r.keys, ['h1']);
      expect(r['h1']!['nightlyInr']!.value, 2500);
    });

    test('no items means no call; a bad reply means null', () async {
      final llm = ScriptedLlm();
      expect(await AiEstimator(llm).fillMany(agent: AgentKind.atithi, subject: 's', items: {}, fields: {'a': 'b'}), isEmpty);
      expect(llm.asked, isEmpty);
      final bad = ScriptedLlm(['{"nope": 1}']);
      expect(await AiEstimator(bad).fillMany(agent: AgentKind.atithi, subject: 's', items: {'x': {}}, fields: {'a': 'b'}), isNull);
    });
  });

  test('intIn clamps sane ranges and rejects non-numbers', () {
    expect(AiEstimator.intIn(2800.4, 500, 100000), 2800);
    expect(AiEstimator.intIn('3200', 500, 100000), 3200);
    expect(AiEstimator.intIn(99, 500, 100000), 500);
    expect(AiEstimator.intIn(9e9, 500, 100000), 100000);
    expect(AiEstimator.intIn('cheap', 500, 100000), isNull);
  });

  group('regional defaults', () {
    test('costs rise with the tier', () {
      for (final f in [RegionalDefaults.hotelNightlyInr, RegionalDefaults.foodPerPersonDayInr, RegionalDefaults.localTransportPerDayInr, RegionalDefaults.entryFeeInr]) {
        expect(f(CostTier.budget), lessThan(f(CostTier.mid)));
        expect(f(CostTier.mid), lessThan(f(CostTier.premium)));
      }
    });

    test('rooms: two grown-ups per room, children share', () {
      expect(RegionalDefaults.roomsFor(adults: 2, seniors: 0, children: 2), 1);
      expect(RegionalDefaults.roomsFor(adults: 4, seniors: 0, children: 0), 2);
      expect(RegionalDefaults.roomsFor(adults: 3, seniors: 0, children: 0), 2);
      expect(RegionalDefaults.roomsFor(adults: 2, seniors: 2, children: 1), 2);
      expect(RegionalDefaults.roomsFor(adults: 1, seniors: 0, children: 0), 1);
      expect(RegionalDefaults.roomsFor(adults: 0, seniors: 0, children: 3), 1);
    });

    test('tier parsing is forgiving', () {
      expect(CostTier.parse('Premium'), CostTier.premium);
      expect(CostTier.parse(' budget '), CostTier.budget);
      expect(CostTier.parse('luxury'), CostTier.mid);
      expect(CostTier.parse(null), CostTier.mid);
    });

    test('a train is cheaper per kilometre than a cab or a flight', () {
      expect(RegionalDefaults.farePerKmInr('train'), lessThan(RegionalDefaults.farePerKmInr('carTaxi')));
      expect(RegionalDefaults.farePerKmInr('train'), lessThan(RegionalDefaults.farePerKmInr('flight')));
      expect(RegionalDefaults.farePerKmInr('unknown'), greaterThan(0));
    });
  });
}
