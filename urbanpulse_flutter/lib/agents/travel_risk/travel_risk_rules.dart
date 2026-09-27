import 'dart:math' as math;

import 'travel_risk.dart';

/// The offline answers: the same weather-impact rules the Nugen model was
/// aligned on (`nugen/travel_risk_rules.py`, kept in step by a parity test),
/// and simple keyword reading for reviews and posts. Used when no aligned
/// model is configured or it cannot answer, and for the twin's Monte Carlo
/// runs, which need hundreds of answers at once.
class RuleTravelRisk implements TravelRiskModel {
  const RuleTravelRisk();

  @override
  String get label => RiskSource.rules.label;

  @override
  bool get isAligned => false;

  @override
  Future<AccessFacts> accessClaims({required String place, required String kind, required String city, required String snippet}) async =>
      readAccess(snippet);

  @override
  Future<PlaceImpact> weatherImpact({required String place, required String category, required String city, required DateTime date, required WeatherDay weather}) async =>
      impactFor(category == 'unknown' ? categoryFromName(place) : category, weather);

  @override
  Future<WeatherEvent> weatherEvent({required String city, required String post}) async => readEvent(post);

  // --- weather_impact --------------------------------------------------------------

  static const profiles = <String, _Profile>{
    'fort': _Profile(exposure: 2, heat: 2, rain: 1, wind: 0, flood: 0, hill: true, water: false),
    'palace': _Profile(exposure: 1, heat: 1, rain: 0, wind: 0, flood: 0, hill: false, water: false),
    'museum': _Profile(exposure: 0, heat: 0, rain: 0, wind: 0, flood: 0, hill: false, water: false),
    'temple': _Profile(exposure: 1, heat: 2, rain: 1, wind: 0, flood: 0, hill: false, water: false),
    'monument': _Profile(exposure: 2, heat: 2, rain: 1, wind: 0, flood: 0, hill: false, water: false),
    'stepwell': _Profile(exposure: 2, heat: 2, rain: 1, wind: 0, flood: 1, hill: false, water: false),
    'beach': _Profile(exposure: 2, heat: 1, rain: 2, wind: 2, flood: 2, hill: false, water: true),
    'lake': _Profile(exposure: 2, heat: 1, rain: 1, wind: 2, flood: 1, hill: false, water: true),
    'boat_ride': _Profile(exposure: 2, heat: 1, rain: 2, wind: 2, flood: 2, hill: false, water: true),
    'garden': _Profile(exposure: 2, heat: 1, rain: 1, wind: 0, flood: 0, hill: false, water: false),
    'zoo': _Profile(exposure: 2, heat: 1, rain: 1, wind: 0, flood: 0, hill: false, water: false),
    'market': _Profile(exposure: 1, heat: 1, rain: 1, wind: 0, flood: 1, hill: false, water: false),
    'mall': _Profile(exposure: 0, heat: 0, rain: 0, wind: 0, flood: 0, hill: false, water: false),
    'waterfall': _Profile(exposure: 2, heat: 0, rain: 2, wind: 0, flood: 2, hill: true, water: true),
    'trek': _Profile(exposure: 2, heat: 2, rain: 2, wind: 1, flood: 1, hill: true, water: false),
    'viewpoint': _Profile(exposure: 2, heat: 1, rain: 1, wind: 1, flood: 0, hill: true, water: false),
    'tea_estate': _Profile(exposure: 2, heat: 0, rain: 1, wind: 0, flood: 0, hill: true, water: false),
    'restaurant': _Profile(exposure: 0, heat: 0, rain: 0, wind: 0, flood: 0, hill: false, water: false),
    'hotel': _Profile(exposure: 0, heat: 0, rain: 0, wind: 0, flood: 0, hill: false, water: false),
  };

  static const _nameHints = <(String, List<String>)>[
    ('waterfall', ['falls', 'waterfall', 'jharna']),
    ('trek', ['trek', 'trail', 'peak', 'summit', 'hike']),
    ('beach', ['beach', 'shore']),
    ('boat_ride', ['boat', 'cruise', 'ferry', 'houseboat', 'backwater']),
    ('lake', ['lake', 'sagar', 'talab', 'ghat', 'sarovar', 'jheel']),
    ('stepwell', ['stepwell', 'baori', 'bawdi', 'baoli', 'vav']),
    ('fort', ['fort', 'garh', 'qila', 'killa']),
    ('palace', ['palace', 'mahal', 'haveli']),
    ('museum', ['museum', 'gallery', 'sangrahalaya', 'planetarium']),
    ('temple', ['temple', 'mandir', 'church', 'mosque', 'masjid', 'gurudwara', 'dargah', 'cathedral', 'basilica']),
    ('garden', ['garden', 'bagh', 'park', 'botanical']),
    ('zoo', ['zoo', 'safari', 'sanctuary', 'biological park']),
    ('market', ['market', 'bazaar', 'bazar', 'chowk', 'haat']),
    ('mall', ['mall', 'plaza', 'arcade']),
    ('viewpoint', ['viewpoint', 'view point', 'point', 'tower', 'top station', 'sunset']),
    ('tea_estate', ['tea estate', 'tea garden', 'plantation']),
    ('monument', ['gate', 'minar', 'tomb', 'memorial', 'mantar', 'observatory', 'ruins', 'stupa']),
    ('restaurant', ['restaurant', 'cafe', 'dhaba', 'kitchen', 'bistro']),
    ('hotel', ['hotel', 'resort', 'inn', 'lodge', 'homestay']),
  ];

  /// The place type a name gives away ("Nahargarh Fort" is a fort); an
  /// unrecognised sight counts as an open-air monument.
  static String categoryFromName(String name) {
    final n = name.toLowerCase();
    for (final (cat, words) in _nameHints) {
      for (final w in words) {
        if (n.contains(w)) return cat;
      }
    }
    return 'monument';
  }

  /// Indoors for the twin's crowd and walking effects.
  static bool isIndoor(String category) => (profiles[category] ?? profiles['monument']!).exposure == 0;

  static const _levels = [ImpactLevel.none, ImpactLevel.low, ImpactLevel.moderate, ImpactLevel.high];

  /// The reference answer for one place on one day.
  static PlaceImpact impactFor(String category, WeatherDay w) {
    final cat = profiles.containsKey(category) ? category : 'monument';
    final p = profiles[cat]!;
    final rl = w.rainLevel, hl = w.heatLevel, wl = w.windLevel;
    final alert = w.alert;
    final alertFor = alert == WeatherAlert.none ? '' : w.alertFor;
    final orangeOrRed = alert == WeatherAlert.orange || alert == WeatherAlert.red;
    final wetAlert = orangeOrRed && const {'heavy rain', 'thunderstorm', 'cyclone'}.contains(alertFor);
    final hotAlert = orangeOrRed && alertFor == 'heat';

    String? closedReason;
    if (p.water && (rl >= 3 || wl >= 2 || (wetAlert && alert == WeatherAlert.red) || (alertFor == 'cyclone' && alert != WeatherAlert.none))) {
      closedReason = 'Water activities and shores are usually shut in heavy rain or strong wind.';
    } else if ((cat == 'trek' || cat == 'waterfall') && (rl >= 3 || wetAlert)) {
      closedReason = 'Hill trails and falls are closed or unsafe in heavy rain: landslides and flash floods.';
    } else if (p.exposure == 2 && alert == WeatherAlert.red && alertFor == 'cyclone') {
      closedReason = 'Outdoor sites close during a cyclone warning.';
    }
    if (closedReason != null) {
      final sens = <String>[if (rl >= 1 || wetAlert) 'rain'];
      if (wl >= 1 || alertFor == 'cyclone' || alertFor == 'thunderstorm') sens.add('wind');
      if (p.flood > 0 && (rl >= 3 || wetAlert)) sens.add('flood');
      return PlaceImpact(level: ImpactLevel.closed, sensitiveTo: sens.isEmpty ? const ['rain'] : sens, bestTime: 'avoid', reason: closedReason);
    }

    final exp = p.exposure;
    var heat = 0;
    if (hl > 0 && exp > 0) {
      heat = p.heat > 0 ? math.min(3, hl + (p.heat - 1)) : 0;
      if (hotAlert) heat = math.min(3, heat + 1);
      if (exp == 1) heat = math.min(heat, 2);
    }
    var rain = 0;
    if (rl > 0) {
      if (exp == 0) {
        rain = rl >= 3 ? 1 : 0;
      } else {
        rain = math.min(3, math.max(0, rl - 1) + p.rain + (p.hill && rl >= 2 ? 1 : 0));
        if (exp == 1) rain = math.min(rain, 2);
      }
      if (wetAlert) rain = math.min(3, rain + 1);
    }
    var wind = 0;
    if (wl > 0 && exp > 0) {
      wind = p.wind > 0 ? math.min(3, wl + p.wind - 1) : (wl >= 2 ? 1 : 0);
    }
    var flood = 0;
    if (p.flood > 0 && rl >= 3) {
      flood = math.min(3, p.flood + rl - 3);
    } else if (exp == 0 && rl >= 4) {
      flood = 1;
    }

    final scores = {'heat': heat, 'rain': rain, 'wind': wind, 'flood': flood};
    final top = scores.values.reduce(math.max);
    final sens = [for (final k in const ['heat', 'rain', 'wind', 'flood']) if (scores[k]! > 0) k];

    if (top == 0) {
      if (hl >= 2 && exp == 0) {
        return const PlaceImpact(level: ImpactLevel.none, bestTime: 'afternoon', reason: 'Indoors, so a good place to spend the hottest hours.');
      }
      return const PlaceImpact(level: ImpactLevel.none, bestTime: 'any', reason: 'The weather should not affect this visit.');
    }

    // Ties go to heat, then rain, then wind, then flood.
    const tieOrder = ['flood', 'wind', 'rain', 'heat'];
    var dominant = 'flood';
    for (final k in tieOrder) {
      if (scores[k]! >= scores[dominant]!) dominant = k;
    }

    String best;
    String reason;
    switch (dominant) {
      case 'heat':
        if (top >= 3 && cat == 'trek') {
          best = 'avoid';
          reason = 'Severe heat on an exposed trail; heat stroke risk.';
        } else {
          best = const {'market', 'viewpoint', 'lake', 'beach'}.contains(cat) ? 'evening' : 'morning';
          reason = switch (cat) {
            'temple' => 'Stone floors get too hot to walk barefoot by midday; go early.',
            'fort' => 'An exposed climb with little shade; go before 10 am.',
            _ => 'Little shade and high heat; avoid 11 am to 4 pm.',
          };
          if (top >= 3) reason = 'Severe heat: ${reason[0].toLowerCase()}${reason.substring(1)}';
        }
      case 'rain':
        if (exp == 0) {
          best = 'any';
          reason = 'Indoors, but roads there may be waterlogged; allow extra travel time.';
        } else if (top >= 3) {
          best = 'avoid';
          reason = 'Heavy rain makes this outdoor visit slippery and unpleasant; move it to a drier day.';
        } else if (cat == 'fort' && rl >= 2) {
          best = 'morning';
          reason = 'Wet ramparts and stone paths get slippery; go early and carry rain gear.';
        } else if (p.hill && rl >= 2) {
          best = 'morning';
          reason = 'Rain makes the slopes slippery and brings fog; go early and carry rain gear.';
        } else {
          best = 'morning';
          reason = 'Showers are likely; go early and carry rain gear.';
        }
      case 'wind':
        best = top >= 3 ? 'avoid' : 'morning';
        reason = 'Strong wind; boats and exposed spots may be unsafe.';
      default:
        best = 'avoid';
        reason = 'Low-lying and likely to flood in this rain.';
    }
    return PlaceImpact(level: _levels[top], sensitiveTo: sens, bestTime: best, reason: reason);
  }

  // --- access_claims (keyword reading) ----------------------------------------------

  static final _stepsNumber = RegExp(r'(\d{1,4})\s*(?:steep\s+|stone\s+)?(?:steps|stairs|seedhiyan|seedhi)', caseSensitive: false);

  /// What a snippet plainly states, sentence by sentence. Weaker than the
  /// model (no paraphrase, little Hinglish), but it never guesses either.
  static AccessFacts readAccess(String snippet) {
    var stepFree = Tri.unknown, lift = Tri.unknown, ramp = Tri.unknown, toilet = Tri.unknown;
    int? stairs;
    final evidence = <String>[];
    for (final raw in snippet.split(RegExp(r'(?<=[.!?])\s+'))) {
      final s = raw.trim().replaceAll(RegExp(r'[.!?]+$'), '');
      if (s.isEmpty) continue;
      final l = s.toLowerCase();
      var used = false;
      final noSteps = RegExp(r'(step-free|step free|no steps|koi seedhi nahi|level entry|entry level|level with the road|flat paved|without any trouble|used a wheelchair|wheelchair users can (enter|go)|easy to get in with a wheelchair)').hasMatch(l);
      final hasSteps = RegExp(r'(steps|stairs|staircase|seedhi|climb|cobbled|steep|sand everywhere|upstairs|flight of)').hasMatch(l);
      if (noSteps) {
        stepFree = Tri.yes;
        used = true;
      } else if (hasSteps && !RegExp(r'lift|elevator').hasMatch(l)) {
        if (stepFree != Tri.yes) stepFree = Tri.no;
        used = true;
      } else if (hasSteps) {
        stepFree = Tri.no;
        used = true;
      }
      final n = _stepsNumber.firstMatch(s);
      if (n != null) {
        stairs = int.tryParse(n.group(1)!);
        used = true;
      }
      if (RegExp(r'\b(no|not a single|without)\s+(ramp)').hasMatch(l)) {
        ramp = Tri.no;
        used = true;
      } else if (RegExp(r'\bramp').hasMatch(l) && !RegExp(r'(planned|being built|will be|next year)').hasMatch(l)) {
        ramp = Tri.yes;
        if (stepFree == Tri.unknown && RegExp(r'(entrance|entry|gate)').hasMatch(l)) stepFree = Tri.yes;
        used = true;
      }
      if (RegExp(r'(no lift|no elevator|lift was (out of order|not working)|lift (is )?broken|only (be reached )?by (narrow )?stairs|spiral staircase only)').hasMatch(l)) {
        lift = Tri.no;
        used = true;
      } else if (RegExp(r'\b(lift|elevator)').hasMatch(l)) {
        lift = Tri.yes;
        used = true;
      }
      if (RegExp(r'(accessible (toilet|washroom|bathroom)|wheelchair[- ]friendly (bathroom|toilet)|roll-in shower|grab bars|toilets for disabled)').hasMatch(l)) {
        toilet = Tri.yes;
        used = true;
      } else if (RegExp(r'(washrooms? (are|is) (down|up)|washroom is tiny|high step into the shower|no accessible toilet)').hasMatch(l)) {
        toilet = Tri.no;
        used = true;
      }
      if (used) evidence.add(s);
    }
    return AccessFacts(stepFree: stepFree, lift: lift, ramp: ramp, accessibleToilet: toilet, stairs: stairs, evidence: evidence);
  }

  // --- weather_event (keyword reading) ------------------------------------------------

  static WeatherEvent readEvent(String post) {
    final l = post.toLowerCase();
    String type = 'none';
    if (RegExp(r'landslide|land slide|mudslide').hasMatch(l)) {
      type = 'landslide';
    } else if (RegExp(r'(closed|shut|band hai|band kar|suspended for tourists)').hasMatch(l) && RegExp(r'(fort|beach|falls|temple|park|museum|ferry|caves|boat|zoo|palace|ropeway|memorial|attraction|tourists|visitors|mahal|garh|qila|mandir|masjid|dargah|church|gate|minar|tomb|ghat|lake|garden|bagh|market|bazaar|monument|sanctuary|dam|point|mantar|baori|kund|stepwell|trek|cruise)').hasMatch(l)) {
      type = 'attraction_closed';
    } else if (RegExp(r'(road (closed|caved|blocked)|closed .*(road|bridge|underpass|subway)|diversion|caved in)').hasMatch(l)) {
      type = 'road_closed';
    } else if (RegExp(r'(power cut|bijli|outage|no electricity|power supply)').hasMatch(l)) {
      type = 'power_cut';
    } else if (RegExp(r'(flooded|flood|waist|water entered|trains? (are )?suspended|water on (the )?tracks)').hasMatch(l)) {
      type = 'flooding';
    } else if (RegExp(r'(waterlog|water-log|paani bhar|knee-deep|ankle-deep|knee deep|ankle deep|water up to)').hasMatch(l)) {
      type = 'waterlogging';
    } else if (RegExp(r'(tree fell|uprooted|hoarding|thunderstorm|storm|cyclone|strong wind)').hasMatch(l)) {
      type = 'storm';
    } else if (RegExp(r'(\b4[3-9] ?(°|degrees)|heatwave|heat wave|scorching|heat stroke|burning)').hasMatch(l)) {
      type = 'heat';
    }
    if (type == 'none') return const WeatherEvent();

    final high = RegExp(r'(waist|suspended|red alert|blocked|landslide|till further notice|completely|evacuat|caved)').hasMatch(l);
    final low = RegExp(r'(ankle|slow|crawling|drizzle|minor)').hasMatch(l);
    final severity = high
        ? EventSeverity.high
        : low
        ? EventSeverity.low
        : EventSeverity.moderate;
    final affects = switch (type) {
      'attraction_closed' || 'heat' => ['attraction'],
      'power_cut' => ['power', 'hotel'],
      'flooding' => RegExp(r'train|track|bus').hasMatch(l) ? ['roads', 'transport'] : (RegExp(r'hotel|lobby').hasMatch(l) ? ['hotel'] : ['roads', 'transport']),
      'landslide' => ['roads', 'transport'],
      _ => ['roads'],
    };
    return WeatherEvent(isEvent: true, type: type, place: _placeIn(post), severity: severity, affects: affects);
  }

  /// A capitalised place named after "at", "on", "near", "around" or before
  /// "mein" / "closed" / "shut".
  static String? _placeIn(String post) {
    for (final after in RegExp(r"\b(?:at|on|near|around|in)\s+((?:[A-Z][\w'-]*\s?){1,4})").allMatches(post)) {
      final p = _nameOnly(after.group(1)!);
      if (p != null) return p;
    }
    final before = RegExp(r"^((?:[A-Z][\w'-]*\s?){1,5})\s*(?:mein|completely|closed|shut|is|flooded)").firstMatch(post.trim());
    if (before != null) return _nameOnly(before.group(1)!);
    final band = RegExp(r"Aaj\s+((?:[A-Z][\w'-]*\s?){1,4})\s+band").firstMatch(post);
    return band == null ? null : _nameOnly(band.group(1)!);
  }

  /// Capitalised words that are not part of a place name in a headline
  /// ("Rain expected in East From September 27" names no place).
  static const _notPlace = {
    'the', 'it', 'i', 'a', 'an', 'from', 'for', 'till', 'until', 'after', 'before', 'today', 'tomorrow', 'tonight', 'this', 'next',
    'east', 'west', 'north', 'south', 'parts', 'several', 'many', 'some', 'rain', 'heavy', 'alert', 'weather', 'imd', 'update', 'live',
    'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december',
    'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday',
  };

  /// The leading run of words that can be a place, or null.
  static String? _nameOnly(String words) {
    final kept = <String>[];
    for (final w in words.trim().split(RegExp(r'\s+'))) {
      if (_notPlace.contains(w.toLowerCase())) break;
      kept.add(w);
    }
    return kept.isEmpty ? null : kept.join(' ');
  }
}

class _Profile {
  const _Profile({required this.exposure, required this.heat, required this.rain, required this.wind, required this.flood, required this.hill, required this.water});

  /// 0 indoors, 1 partly outdoors, 2 outdoors.
  final int exposure;
  final int heat;
  final int rain;
  final int wind;
  final int flood;
  final bool hill;
  final bool water;
}
