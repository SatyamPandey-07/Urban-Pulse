import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:urbanpulse/agents/khoji/khoji.dart';
import 'package:urbanpulse/agents/travel_risk/nugen_travel_risk.dart';
import 'package:urbanpulse/agents/travel_risk/travel_risk.dart';
import 'package:urbanpulse/agents/travel_risk/travel_risk_rules.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/services/nugen/nugen_client.dart';

WeatherDay _weather(Map<String, dynamic> w) => WeatherDay(
  tempMaxC: (w['temp_max_c'] as num).toDouble(),
  rainMm: (w['rain_mm'] as num).toDouble(),
  rainProb: (w['rain_prob'] as num).toInt(),
  windKmh: (w['wind_kmh'] as num).toDouble(),
  alert: WeatherAlert.parse(w['alert']),
  alertFor: '${w['alert_for'] ?? ''}',
);

/// A Nugen endpoint that answers every prompt with [reply] (or fails).
NugenTravelRisk _nugen(String Function(String prompt) reply, {int status = 200}) {
  final client = MockClient((req) async {
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    final prompt = ((body['messages'] as List).first as Map<String, dynamic>)['content'] as String;
    if (status != 200) return http.Response('{"detail":"Nugen inference failed: 502 Bad Gateway"}', status);
    return http.Response(
      jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': reply(prompt)},
          },
        ],
      }),
      200,
    );
  });
  return NugenTravelRisk(client: NugenClient(apiKey: 'test', client: client), modelId: 'model_test');
}

void main() {
  final fixture = jsonDecode(File('test/fixtures/travel_risk_parity.json').readAsStringSync()) as Map<String, dynamic>;

  group('parity with the training data (nugen/travel_risk_rules.py)', () {
    test('the offline weather-impact rules give the training labels', () {
      final cases = fixture['impacts'] as List<dynamic>;
      var checked = 0;
      for (final c in cases.cast<Map<String, dynamic>>()) {
        final got = RuleTravelRisk.impactFor(c['category'] as String, _weather(c['weather'] as Map<String, dynamic>));
        final exp = c['expected'] as Map<String, dynamic>;
        final where = '${c['category']} ${c['weather']}';
        expect(got.level.name, exp['impact'], reason: where);
        expect(got.sensitiveTo, [for (final s in exp['sensitive_to'] as List) '$s'], reason: where);
        expect(got.bestTime, exp['best_time'], reason: where);
        expect(got.reason, exp['reason'], reason: where);
        checked++;
      }
      expect(checked, 400);
    });

    test('place types are read from names the same way', () {
      for (final c in (fixture['categories'] as List).cast<Map<String, dynamic>>()) {
        expect(RuleTravelRisk.categoryFromName(c['name'] as String), c['category'], reason: '${c['name']}');
      }
    });

    test('the app sends the model exactly the prompts it was aligned on', () {
      for (final p in (fixture['prompts'] as List).cast<Map<String, dynamic>>()) {
        final String prompt = switch (p['task']) {
          'weather_impact' => TravelRiskPrompts.impact(
            place: p['place'] as String,
            category: p['category'] as String,
            city: p['city'] as String,
            date: DateTime.parse(p['date'] as String),
            weather: _weather(p['weather'] as Map<String, dynamic>),
          ),
          'access_claims' => TravelRiskPrompts.access(place: p['place'] as String, kind: p['kind'] as String, city: p['city'] as String, snippet: p['snippet'] as String),
          _ => TravelRiskPrompts.event(city: p['city'] as String, post: p['post'] as String),
        };
        expect(prompt, p['prompt']);
      }
    });
  });

  group('answers', () {
    test('the all-string answer format is read into facts', () {
      final j = TravelRiskAnswers.firstObject(
        '<think>steps are mentioned</think>\n{"step_free": "no", "lift": "unknown", "ramp": "no", "accessible_toilet": "unknown", "stairs": "40", "evidence": "There are about 40 steep steps up to the main palace | No ramp anywhere, only stairs"}',
      );
      final f = TravelRiskAnswers.access(j, RiskSource.aligned)!;
      expect(f.stepFree, Tri.no);
      expect(f.ramp, Tri.no);
      expect(f.stairs, 40);
      expect(f.evidence, hasLength(2));
    });

    test('real JSON lists, numbers and booleans are read too', () {
      final ev = TravelRiskAnswers.event({'is_weather_event': true, 'event': 'waterlogging', 'place': 'MI Road', 'severity': 'moderate', 'affects': ['roads']}, RiskSource.aligned)!;
      expect(ev.isEvent, isTrue);
      expect(ev.place, 'MI Road');
      expect(ev.affects, ['roads']);
      final none = TravelRiskAnswers.event({'is_weather_event': 'no', 'event': 'none', 'place': 'none', 'severity': 'none', 'affects': 'none'}, RiskSource.aligned)!;
      expect(none.isEvent, isFalse);
      expect(none.place, isNull);
    });

    test('a guess is not a fact: quotes not in the snippet make the answer unknown', () {
      const snippet = 'Stunning sunset views over the city. Very accommodating staff, they helped us a lot.';
      const guessed = AccessFacts(stepFree: Tri.yes, ramp: Tri.yes, evidence: ['Wheelchair accessible with ramps'], source: RiskSource.aligned);
      final grounded = guessed.groundedIn(snippet);
      expect(grounded.isEmpty, isTrue);
      expect(grounded.stepFree, Tri.unknown);

      const real = AccessFacts(stepFree: Tri.no, stairs: 40, evidence: ['There are about 40 steep steps up to the main palace.'], source: RiskSource.aligned);
      final kept = real.groundedIn('Great views. There are about 40 steep steps up to the main palace. Go early.');
      expect(kept.stepFree, Tri.no);
      expect(kept.evidence, hasLength(1));
    });

    test('Nugen replies and streamed replies are both read', () {
      expect(NugenClient.parseContent('{"choices":[{"message":{"content":"hi"}}]}'), 'hi');
      expect(NugenClient.parseContent('data: {"choices":[{"delta":{"content":"he"}}]}\n\ndata: {"choices":[{"delta":{"content":"llo"}}]}\n\ndata: [DONE]\n'), 'hello');
    });
  });

  group('the aligned model in the app', () {
    test('its answers are used and labelled as Nugen', () async {
      final risk = _nugen((_) => '{"impact": "high", "sensitive_to": "heat", "best_time": "morning", "reason": "An exposed climb with little shade; go before 10 am."}');
      final i = await risk.weatherImpact(place: 'Amber Fort', category: 'fort', city: 'Jaipur', date: DateTime(2026, 5, 20), weather: const WeatherDay(tempMaxC: 44, rainMm: 0));
      expect(i.level, ImpactLevel.high);
      expect(i.source, RiskSource.aligned);
      expect(risk.answered, 1);
    });

    test('a failing endpoint falls back to the rules, and the failure is not cached', () async {
      final risk = _nugen((_) => '', status: 502);
      const w = WeatherDay(tempMaxC: 30, rainMm: 180, rainProb: 100, alert: WeatherAlert.red, alertFor: 'heavy rain');
      final i = await risk.weatherImpact(place: 'Dudhsagar Falls', category: 'waterfall', city: 'Goa', date: DateTime(2026, 7, 2), weather: w);
      expect(i.level, ImpactLevel.closed);
      expect(i.source, RiskSource.rules);
      expect(risk.fellBack, 1);
      expect(risk.lastError, contains('502'));
      await risk.weatherImpact(place: 'Dudhsagar Falls', category: 'waterfall', city: 'Goa', date: DateTime(2026, 7, 2), weather: w);
      expect(risk.calls, 2);
    });

    test('an answer that is not JSON falls back to the rules', () async {
      final risk = _nugen((_) => 'I think it is fine to visit.');
      final ev = await risk.weatherEvent(city: 'Mumbai', post: 'Knee-deep water at Andheri Subway, cars stuck, avoid the route!');
      expect(ev.source, RiskSource.rules);
      expect(ev.type, 'waterlogging');
    });

    test('a guessed access answer from the model becomes unknown', () async {
      final risk = _nugen((_) => '{"step_free": "yes", "lift": "unknown", "ramp": "yes", "accessible_toilet": "unknown", "stairs": "unknown", "evidence": "The fort is wheelchair friendly"}');
      final f = await risk.accessClaims(place: 'Nahargarh Fort', kind: 'sight', city: 'Jaipur', snippet: 'Stunning sunset views over the city. Good for elderly people.');
      expect(f.isEmpty, isTrue);
    });
  });

  group('offline reading', () {
    test('reviews: steps, ramps, lifts and toilets', () {
      final f = RuleTravelRisk.readAccess('There are about 40 steep steps up to the main palace. No ramp anywhere, only stairs. Accessible toilet near the entrance.');
      expect(f.stepFree, Tri.no);
      expect(f.stairs, 40);
      expect(f.ramp, Tri.no);
      expect(f.accessibleToilet, Tri.yes);
      expect(RuleTravelRisk.readAccess('Lovely views and friendly staff.').isEmpty, isTrue);
    });

    test('posts: event, severity and place', () {
      final a = RuleTravelRisk.readEvent('Amber Fort closed today due to heavy rain, officials say');
      expect(a.type, 'attraction_closed');
      expect(a.place, 'Amber Fort');
      final b = RuleTravelRisk.readEvent('Knee-deep water at Hindmata, cars stuck, avoid the route!');
      expect(b.type, 'waterlogging');
      expect(b.severity, EventSeverity.moderate);
      expect(b.place, 'Hindmata');
      expect(RuleTravelRisk.readEvent('Lovely weather today, perfect for chai and pakode').isEvent, isFalse);
    });
  });

  group('Khoji', () {
    test('access facts become need support', () {
      const steps = AccessFacts(stepFree: Tri.no, stairs: 40, evidence: ['40 steps']);
      expect(Khoji.accessLevel(AccessibilityNeed.wheelchair, steps, hotel: false), SupportLevel.no);
      expect(Khoji.accessLevel(AccessibilityNeed.elderlyCare, steps, hotel: false), SupportLevel.no);
      const fewSteps = AccessFacts(stepFree: Tri.no, stairs: 12, evidence: ['12 steps']);
      expect(Khoji.accessLevel(AccessibilityNeed.limitedMobility, fewSteps, hotel: false), SupportLevel.partial);
      const level = AccessFacts(stepFree: Tri.yes, accessibleToilet: Tri.no, evidence: ['level entry']);
      expect(Khoji.accessLevel(AccessibilityNeed.wheelchair, level, hotel: false), SupportLevel.partial);
      const lift = AccessFacts(lift: Tri.yes, evidence: ['lift']);
      expect(Khoji.accessLevel(AccessibilityNeed.elderlyCare, lift, hotel: true), SupportLevel.yes);
      expect(Khoji.accessLevel(AccessibilityNeed.wheelchair, const AccessFacts(), hotel: true), isNull);
    });
  });
}
