/// UrbanPulse Travel-Risk: the three narrow jobs the Nugen-aligned model does
/// for the app, their prompts and their answers.
///
/// - access_claims: wheelchair-access facts quoted from one review snippet;
///   never guessed (Khoji uses it).
/// - weather_impact: how one day's weather affects visiting one place (the
///   weather digital twin uses it).
/// - weather_event: the travel disruption, if any, one social post reports
///   (the twin's social signals).
///
/// The prompts here are character-for-character the ones the model was
/// aligned on (`nugen/travel_risk_rules.py`), and every answer value is a
/// string: numbers in quotes, lists joined, "none"/"unknown" for missing.
library;

import 'dart:convert';

/// yes / no / unknown.
enum Tri {
  yes,
  no,
  unknown;

  static Tri parse(Object? v) => switch ('$v'.trim().toLowerCase()) {
    'yes' || 'true' => Tri.yes,
    'no' || 'false' => Tri.no,
    _ => Tri.unknown,
  };
}

/// Who answered: the aligned model or the offline rules.
enum RiskSource {
  aligned,
  rules;

  String get label => switch (this) {
    RiskSource.aligned => 'UrbanPulse Travel-Risk (Nugen)',
    RiskSource.rules => 'Offline rules',
  };
}

// --- access_claims ---------------------------------------------------------------

class AccessFacts {
  const AccessFacts({
    this.stepFree = Tri.unknown,
    this.lift = Tri.unknown,
    this.ramp = Tri.unknown,
    this.accessibleToilet = Tri.unknown,
    this.stairs,
    this.evidence = const [],
    this.source = RiskSource.rules,
  });

  final Tri stepFree;
  final Tri lift;
  final Tri ramp;
  final Tri accessibleToilet;
  final int? stairs;

  /// Sentences copied from the snippet that back the answers.
  final List<String> evidence;
  final RiskSource source;

  bool get isEmpty =>
      stepFree == Tri.unknown && lift == Tri.unknown && ramp == Tri.unknown && accessibleToilet == Tri.unknown && stairs == null;

  /// Only what the snippet itself says survives: quotes that are not in the
  /// snippet are dropped, and with no real quote left every answer becomes
  /// unknown (the answer was a guess).
  AccessFacts groundedIn(String snippet) {
    final hay = _norm(snippet);
    final kept = [for (final q in evidence) if (q.trim().length >= 6 && hay.contains(_norm(q))) q.trim()];
    if (kept.isEmpty) return AccessFacts(source: source);
    return AccessFacts(
      stepFree: stepFree,
      lift: lift,
      ramp: ramp,
      accessibleToilet: accessibleToilet,
      stairs: stairs,
      evidence: kept,
      source: source,
    );
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[“”"]'), '').replaceAll(RegExp(r'\s+'), ' ').trim().replaceAll(RegExp(r'[.!]+$'), '');

  Map<String, Object?> toJson() => {
    'step_free': stepFree.name,
    'lift': lift.name,
    'ramp': ramp.name,
    'accessible_toilet': accessibleToilet.name,
    'stairs': stairs,
    'evidence': evidence,
    'source': source.name,
  };
}

// --- weather_impact --------------------------------------------------------------

enum WeatherAlert {
  none,
  yellow,
  orange,
  red;

  static WeatherAlert parse(Object? v) => WeatherAlert.values.firstWhere((a) => a.name == '$v'.trim().toLowerCase(), orElse: () => WeatherAlert.none);
}

/// One day's weather at a place, as the model reads it.
class WeatherDay {
  const WeatherDay({
    required this.tempMaxC,
    required this.rainMm,
    this.rainProb = 0,
    this.windKmh = 10,
    this.alert = WeatherAlert.none,
    this.alertFor = '',
  });

  final double tempMaxC;
  final double rainMm;

  /// 0-100.
  final int rainProb;
  final double windKmh;
  final WeatherAlert alert;

  /// What the alert is for: heat, heavy rain, thunderstorm or cyclone.
  final String alertFor;

  WeatherDay copyWith({double? tempMaxC, double? rainMm, int? rainProb, double? windKmh, WeatherAlert? alert, String? alertFor}) => WeatherDay(
    tempMaxC: tempMaxC ?? this.tempMaxC,
    rainMm: rainMm ?? this.rainMm,
    rainProb: rainProb ?? this.rainProb,
    windKmh: windKmh ?? this.windKmh,
    alert: alert ?? this.alert,
    alertFor: alertFor ?? this.alertFor,
  );

  /// IMD 24-hour rainfall class: 0 none, 1 light, 2 moderate, 3 heavy,
  /// 4 very heavy, 5 extremely heavy.
  int get rainLevel => rainMm >= 204.5
      ? 5
      : rainMm >= 115.6
      ? 4
      : rainMm >= 64.5
      ? 3
      : rainMm >= 15.6
      ? 2
      : rainMm >= 2.5
      ? 1
      : 0;

  /// 0 normal, 1 hot (36-39 °C), 2 heat wave (40-44), 3 severe (45+).
  int get heatLevel => tempMaxC >= 45
      ? 3
      : tempMaxC >= 40
      ? 2
      : tempMaxC >= 36
      ? 1
      : 0;

  /// 0 calm, 1 gusty (40-59 km/h), 2 storm (60+).
  int get windLevel => windKmh >= 60
      ? 2
      : windKmh >= 40
      ? 1
      : 0;

  static const rainClassNames = ['No rain', 'Light rain', 'Moderate rain', 'Heavy rain', 'Very heavy rain', 'Extremely heavy rain'];
  static const heatClassNames = ['Normal', 'Hot', 'Heat wave', 'Severe heat'];

  String get rainClass => rainClassNames[rainLevel];
  String get heatClass => heatClassNames[heatLevel];

  /// "max 34°C, rain 12.5 mm (60% chance), wind 18 km/h, alert: none", exactly
  /// as in the training data.
  String get promptLine {
    final a = alert == WeatherAlert.none ? 'none' : '${alert.name} for $alertFor';
    return 'max ${tempMaxC.round()}°C, rain ${_mm(rainMm)} mm ($rainProb% chance), wind ${windKmh.round()} km/h, alert: $a';
  }

  static String _mm(double v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? '${r.round()}' : r.toStringAsFixed(1);
  }

  String get summary {
    final parts = ['${tempMaxC.round()}°C', if (rainMm >= 0.5) '${_mm(rainMm)} mm rain', if (windKmh >= 40) '${windKmh.round()} km/h wind'];
    return parts.join(' · ');
  }
}

enum ImpactLevel {
  none,
  low,
  moderate,
  high,
  closed;

  static ImpactLevel parse(Object? v) => ImpactLevel.values.firstWhere((l) => l.name == '$v'.trim().toLowerCase(), orElse: () => ImpactLevel.none);
}

class PlaceImpact {
  const PlaceImpact({
    required this.level,
    this.sensitiveTo = const [],
    this.bestTime = 'any',
    this.reason = '',
    this.source = RiskSource.rules,
  });

  final ImpactLevel level;

  /// heat, rain, wind, flood.
  final List<String> sensitiveTo;

  /// morning, afternoon, evening, any, avoid.
  final String bestTime;
  final String reason;
  final RiskSource source;

  static const _times = {'morning', 'afternoon', 'evening', 'any', 'avoid'};

  Map<String, Object?> toJson() => {'impact': level.name, 'sensitive_to': sensitiveTo, 'best_time': bestTime, 'reason': reason, 'source': source.name};
}

// --- weather_event ---------------------------------------------------------------

enum EventSeverity {
  none,
  low,
  moderate,
  high;

  static EventSeverity parse(Object? v) => EventSeverity.values.firstWhere((s) => s.name == '$v'.trim().toLowerCase(), orElse: () => EventSeverity.none);
}

class WeatherEvent {
  const WeatherEvent({
    this.isEvent = false,
    this.type = 'none',
    this.place,
    this.severity = EventSeverity.none,
    this.affects = const [],
    this.source = RiskSource.rules,
  });

  final bool isEvent;

  /// waterlogging, flooding, heat, storm, landslide, road_closed,
  /// attraction_closed, power_cut, none.
  final String type;
  final String? place;
  final EventSeverity severity;

  /// roads, transport, attraction, hotel, power.
  final List<String> affects;
  final RiskSource source;

  static const types = {'waterlogging', 'flooding', 'heat', 'storm', 'landslide', 'road_closed', 'attraction_closed', 'power_cut', 'none'};

  String get label => type.replaceAll('_', ' ');

  Map<String, Object?> toJson() => {
    'is_weather_event': isEvent,
    'event': type,
    'place': place,
    'severity': severity.name,
    'affects': affects,
    'source': source.name,
  };
}

// --- prompts (identical to nugen/travel_risk_rules.py) -------------------------------

abstract final class TravelRiskPrompts {
  static const accessSchema =
      '{"step_free": "yes|no|unknown", "lift": "yes|no|unknown", "ramp": "yes|no|unknown", '
      '"accessible_toilet": "yes|no|unknown", "stairs": "number of steps or unknown", '
      '"evidence": "exact quotes from the snippet joined by | or none"}';

  static const impactSchema =
      '{"impact": "none|low|moderate|high|closed", "sensitive_to": "heat, rain, wind, flood or none", '
      '"best_time": "morning|afternoon|evening|any|avoid", "reason": "one short sentence"}';

  static const eventSchema =
      '{"is_weather_event": "yes|no", "event": "waterlogging|flooding|heat|storm|landslide|'
      'road_closed|attraction_closed|power_cut|none", "place": "name or none", '
      '"severity": "none|low|moderate|high", "affects": "roads, transport, attraction, hotel, power or none"}';

  /// [kind] is hotel, sight or restaurant.
  static String access({required String place, required String kind, required String city, required String snippet}) =>
      'TASK: access_claims\n'
      'Place: $place ($kind), $city\n'
      'Snippet: "${_oneLine(snippet)}"\n'
      'Answer with JSON only: $accessSchema';

  static String impact({required String place, required String category, required String city, required DateTime date, required WeatherDay weather}) =>
      'TASK: weather_impact\n'
      'Place: $place (category: $category), $city\n'
      'Date: ${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}\n'
      'Weather: ${weather.promptLine}\n'
      'Answer with JSON only: $impactSchema';

  static String event({required String city, required String post}) =>
      'TASK: weather_event\n'
      'City: $city\n'
      'Post: "${_oneLine(post)}"\n'
      'Answer with JSON only: $eventSchema';

  static String _oneLine(String s) => s.replaceAll('"', "'").replaceAll(RegExp(r'\s+'), ' ').trim();
}

// --- answers -------------------------------------------------------------------------

abstract final class TravelRiskAnswers {
  /// The first JSON object in a reply, after any `<think>` block.
  static Map<String, dynamic>? firstObject(String text) {
    final t = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    var start = t.indexOf('{');
    while (start != -1) {
      var depth = 0;
      var inStr = false;
      var esc = false;
      for (var i = start; i < t.length; i++) {
        final c = t[i];
        if (inStr) {
          if (esc) {
            esc = false;
          } else if (c == r'\') {
            esc = true;
          } else if (c == '"') {
            inStr = false;
          }
        } else if (c == '"') {
          inStr = true;
        } else if (c == '{') {
          depth++;
        } else if (c == '}') {
          depth--;
          if (depth == 0) {
            try {
              final v = jsonDecode(t.substring(start, i + 1));
              if (v is Map<String, dynamic>) return v;
            } catch (_) {
              // try the next object
            }
            break;
          }
        }
      }
      start = t.indexOf('{', start + 1);
    }
    return null;
  }

  static List<String> split(Object? v, String sep) {
    if (v is List) return [for (final x in v) if ('$x'.trim().isNotEmpty) '$x'.trim()];
    if (v == null) return const [];
    final s = '$v'.trim();
    if (s.isEmpty || const {'none', 'null', '[]', 'unknown'}.contains(s.toLowerCase())) return const [];
    return [for (final x in s.split(sep)) if (x.trim().isNotEmpty) x.trim()];
  }

  static AccessFacts? access(Map<String, dynamic>? j, RiskSource source) {
    if (j == null || !j.containsKey('step_free')) return null;
    final st = j['stairs'];
    final stairs = st is num ? st.toInt() : int.tryParse('$st'.trim());
    return AccessFacts(
      stepFree: Tri.parse(j['step_free']),
      lift: Tri.parse(j['lift']),
      ramp: Tri.parse(j['ramp']),
      accessibleToilet: Tri.parse(j['accessible_toilet']),
      stairs: stairs != null && stairs > 0 && stairs < 5000 ? stairs : null,
      evidence: split(j['evidence'], '|'),
      source: source,
    );
  }

  static PlaceImpact? impact(Map<String, dynamic>? j, RiskSource source) {
    if (j == null || !j.containsKey('impact')) return null;
    final raw = '${j['impact']}'.trim().toLowerCase();
    if (!ImpactLevel.values.any((l) => l.name == raw)) return null;
    final best = '${j['best_time'] ?? 'any'}'.trim().toLowerCase();
    return PlaceImpact(
      level: ImpactLevel.parse(raw),
      sensitiveTo: [for (final s in split(j['sensitive_to'], ',')) if (const {'heat', 'rain', 'wind', 'flood'}.contains(s.toLowerCase())) s.toLowerCase()],
      bestTime: PlaceImpact._times.contains(best) ? best : 'any',
      reason: '${j['reason'] ?? ''}'.trim(),
      source: source,
    );
  }

  static WeatherEvent? event(Map<String, dynamic>? j, RiskSource source) {
    if (j == null || !j.containsKey('is_weather_event')) return null;
    final ev = j['is_weather_event'];
    final isEvent = ev == true || const {'yes', 'true'}.contains('$ev'.trim().toLowerCase());
    final type = '${j['event'] ?? 'none'}'.trim().toLowerCase();
    final place = j['place'];
    final p = place == null || const {'none', 'null', ''}.contains('$place'.trim().toLowerCase()) ? null : '$place'.trim();
    return WeatherEvent(
      isEvent: isEvent && type != 'none',
      type: WeatherEvent.types.contains(type) ? type : (isEvent ? 'storm' : 'none'),
      place: p,
      severity: EventSeverity.parse(j['severity']),
      affects: [for (final a in split(j['affects'], ',')) a.toLowerCase()],
      source: source,
    );
  }
}

/// The three jobs, answered by the aligned model or by rules.
abstract class TravelRiskModel {
  /// Shown next to every answer in the app.
  String get label;

  /// True when answers come from the Nugen-aligned model.
  bool get isAligned;

  Future<AccessFacts> accessClaims({required String place, required String kind, required String city, required String snippet});

  Future<PlaceImpact> weatherImpact({required String place, required String category, required String city, required DateTime date, required WeatherDay weather});

  Future<WeatherEvent> weatherEvent({required String city, required String post});
}
