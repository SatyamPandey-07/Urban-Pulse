import '../../services/nugen/nugen_client.dart';
import 'travel_risk.dart';
import 'travel_risk_rules.dart';

/// The Travel-Risk jobs answered by the Nugen-aligned model
/// (`llama-v3p2-3b-reasoning` aligned on the UrbanPulse handbook and worked
/// examples; see `nugen/`). Every answer is checked before it is used, and
/// anything the model cannot answer falls back to [RuleTravelRisk], so the app
/// never stalls on the model:
/// - access facts keep only quotes that really are in the snippet; with none
///   left, the answer is "unknown" (the model guessed);
/// - an answer that is not valid JSON of the right shape is replaced by the
///   rules' answer.
/// Answers are cached per prompt, so the twin can re-simulate freely.
class NugenTravelRisk implements TravelRiskModel {
  NugenTravelRisk({required this.client, required this.modelId, this.fallback = const RuleTravelRisk()});

  final NugenClient client;
  final String modelId;
  final RuleTravelRisk fallback;

  final Map<String, Future<Object?>> _cache = {};

  /// Calls, successes and the last few latencies, for the UI.
  int calls = 0;
  int answered = 0;
  int fellBack = 0;
  String? lastError;
  final List<int> latenciesMs = [];

  @override
  String get label => RiskSource.aligned.label;

  @override
  bool get isAligned => true;

  int? get medianLatencyMs {
    if (latenciesMs.isEmpty) return null;
    final s = [...latenciesMs]..sort();
    return s[s.length ~/ 2];
  }

  Future<Map<String, dynamic>?> _ask(String prompt) async {
    final cached = _cache[prompt];
    if (cached != null) return (await cached) as Map<String, dynamic>?;
    final f = () async {
      calls++;
      final r = await client.chat(model: modelId, prompt: prompt, maxTokens: 600);
      if (!r.ok) {
        lastError = r.error;
        return null;
      }
      latenciesMs.add(r.latencyMs);
      if (latenciesMs.length > 50) latenciesMs.removeAt(0);
      return TravelRiskAnswers.firstObject(r.content!);
    }();
    _cache[prompt] = f;
    final v = await f;
    // A failed call is retried next time rather than cached.
    if (v == null) _cache.remove(prompt);
    return v;
  }

  @override
  Future<AccessFacts> accessClaims({required String place, required String kind, required String city, required String snippet}) async {
    final j = await _ask(TravelRiskPrompts.access(place: place, kind: kind, city: city, snippet: snippet));
    final facts = TravelRiskAnswers.access(j, RiskSource.aligned);
    if (facts == null) {
      fellBack++;
      return RuleTravelRisk.readAccess(snippet);
    }
    answered++;
    return facts.groundedIn(snippet);
  }

  @override
  Future<PlaceImpact> weatherImpact({required String place, required String category, required String city, required DateTime date, required WeatherDay weather}) async {
    final j = await _ask(TravelRiskPrompts.impact(place: place, category: category, city: city, date: date, weather: weather));
    final impact = TravelRiskAnswers.impact(j, RiskSource.aligned);
    if (impact == null) {
      fellBack++;
      return fallback.weatherImpact(place: place, category: category, city: city, date: date, weather: weather);
    }
    answered++;
    return impact;
  }

  @override
  Future<WeatherEvent> weatherEvent({required String city, required String post}) async {
    final j = await _ask(TravelRiskPrompts.event(city: city, post: post));
    final ev = TravelRiskAnswers.event(j, RiskSource.aligned);
    if (ev == null) {
      fellBack++;
      return RuleTravelRisk.readEvent(post);
    }
    answered++;
    return ev;
  }
}
