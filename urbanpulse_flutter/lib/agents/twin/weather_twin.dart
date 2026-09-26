import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../travel_risk/travel_risk.dart';
import '../travel_risk/travel_risk_rules.dart';
import 'social_signals.dart';
import 'twin_calibration.dart';

/// A what-if: weather that replaces the live forecast on some days, and
/// optionally a flooded area on the map. [durationDays] 0 with no flood is the
/// live forecast itself.
class TwinScenario {
  const TwinScenario({
    this.id = 'live',
    this.name = 'Live forecast',
    this.rainMm,
    this.tempMaxC,
    this.windKmh,
    this.alert,
    this.alertFor = '',
    this.startDay = 1,
    this.durationDays = 0,
    this.floodCenter,
    this.floodRadiusKm = 1.5,
    this.useSocial = true,
  });

  final String id;
  final String name;
  final double? rainMm;
  final double? tempMaxC;
  final double? windKmh;
  final WeatherAlert? alert;
  final String alertFor;
  final int startDay;
  final int durationDays;
  final LatLng? floodCenter;
  final double floodRadiusKm;

  /// Apply what people are reporting right now (social signals).
  final bool useSocial;

  bool get hasFlood => floodCenter != null && floodRadiusKm > 0;
  bool get isLive => durationDays == 0 && !hasFlood;

  bool covers(int day) => durationDays > 0 && day >= startDay && day < startDay + durationDays;

  WeatherDay weatherFor(int day, WeatherDay live) {
    if (!covers(day)) return live;
    final rain = rainMm;
    return live.copyWith(
      rainMm: rain,
      rainProb: rain == null ? null : (rain >= 2.5 ? math.max(live.rainProb, 95) : live.rainProb),
      tempMaxC: tempMaxC,
      windKmh: windKmh,
      alert: alert,
      alertFor: alert == null ? null : alertFor,
    );
  }

  TwinScenario copyWith({
    String? id,
    String? name,
    double? rainMm,
    double? tempMaxC,
    double? windKmh,
    WeatherAlert? alert,
    String? alertFor,
    int? startDay,
    int? durationDays,
    LatLng? floodCenter,
    bool clearFlood = false,
    double? floodRadiusKm,
    bool? useSocial,
  }) => TwinScenario(
    id: id ?? 'custom',
    name: name ?? 'Custom what-if',
    rainMm: rainMm ?? this.rainMm,
    tempMaxC: tempMaxC ?? this.tempMaxC,
    windKmh: windKmh ?? this.windKmh,
    alert: alert ?? this.alert,
    alertFor: alertFor ?? this.alertFor,
    startDay: startDay ?? this.startDay,
    durationDays: durationDays ?? this.durationDays,
    floodCenter: clearFlood ? null : (floodCenter ?? this.floodCenter),
    floodRadiusKm: floodRadiusKm ?? this.floodRadiusKm,
    useSocial: useSocial ?? this.useSocial,
  );

  /// Ready-made scenarios for a trip: normal, and several extremes.
  static List<TwinScenario> presets(Itinerary it) {
    final days = math.max(1, it.days.length);
    final second = days >= 2 ? 2 : 1;
    final flood = it.hotel?.location ??
        [for (final d in it.days) for (final s in d.slots) if (s.location != null) s.location!].firstOrNull;
    return [
      const TwinScenario(),
      TwinScenario(id: 'downpour', name: 'Monsoon downpour', rainMm: 90, windKmh: 30, alert: WeatherAlert.orange, alertFor: 'heavy rain', startDay: second, durationDays: 1),
      TwinScenario(id: 'cloudburst', name: 'Cloudburst, 3 days', rainMm: 180, windKmh: 45, alert: WeatherAlert.red, alertFor: 'heavy rain', startDay: 1, durationDays: math.min(3, days)),
      TwinScenario(id: 'heatwave', name: 'Heatwave 46°C', rainMm: 0, tempMaxC: 46, windKmh: 15, alert: WeatherAlert.red, alertFor: 'heat', startDay: 1, durationDays: days),
      TwinScenario(id: 'cyclone', name: 'Cyclone warning', rainMm: 150, windKmh: 95, alert: WeatherAlert.red, alertFor: 'cyclone', startDay: 1, durationDays: math.min(2, days)),
      if (flood != null)
        TwinScenario(id: 'flood', name: 'Flooding near the hotel', rainMm: 120, windKmh: 30, alert: WeatherAlert.orange, alertFor: 'heavy rain', startDay: 1, durationDays: 1, floodCenter: flood, floodRadiusKm: 1.5),
    ];
  }
}

enum VisitState {
  ok,
  shifted,
  atRisk,
  closed,
  dropped;

  String get label => switch (this) {
    VisitState.ok => 'Fine',
    VisitState.shifted => 'Move time',
    VisitState.atRisk => 'At risk',
    VisitState.closed => 'Closed',
    VisitState.dropped => 'Dropped',
  };

  bool get disrupted => this == VisitState.closed || this == VisitState.dropped || this == VisitState.atRisk;
}

/// One planned visit, as the twin sees it.
class TwinVisit {
  const TwinVisit({
    required this.day,
    required this.name,
    required this.category,
    required this.start,
    required this.end,
    required this.impact,
    required this.state,
    this.location,
    this.why = '',
    this.queueExtraMin = 0,
    this.reportedBy,
  });

  final int day;
  final String name;
  final String category;
  final LatLng? location;
  final DateTime start;
  final DateTime end;
  final PlaceImpact impact;
  final VisitState state;
  final String why;

  /// Longer queues when visitors crowd into indoor places.
  final int queueExtraMin;

  /// The social post that closed it, when one did.
  final String? reportedBy;

  String get key => '$day:$name';
  bool get indoor => RuleTravelRisk.isIndoor(category);
  int get minutes => end.difference(start).inMinutes;
}

/// One leg between stops.
class TwinLeg {
  const TwinLeg({
    required this.day,
    required this.from,
    required this.to,
    required this.mode,
    required this.walking,
    required this.km,
    required this.baseMin,
    required this.simMin,
    required this.baseCostInr,
    required this.simCostInr,
    required this.baseCo2g,
    required this.simCo2g,
    this.becameCab = false,
    this.throughFlood = false,
    this.blocked = false,
    this.note,
    this.path = const [],
  });

  final int day;
  final String from;
  final String to;
  final String mode;
  final bool walking;
  final double km;
  final int baseMin;
  final int simMin;
  final int baseCostInr;
  final int simCostInr;
  final int baseCo2g;
  final int simCo2g;
  final bool becameCab;
  final bool throughFlood;
  final bool blocked;
  final String? note;
  final List<LatLng> path;

  int get extraMin => simMin - baseMin;
  bool get changed => simMin != baseMin || simCostInr != baseCostInr || becameCab || blocked;
}

/// How a day's weather moves demand across the destination: attractions,
/// cabs, restaurants, hotels and their staff. Percent changes against a
/// normal day; estimated elasticities, scaled by what the twin has learned.
class EcosystemImpact {
  const EcosystemImpact({
    this.outdoorDemandPct = 0,
    this.indoorDemandPct = 0,
    this.cabSurge = 1,
    this.dineInPct = 0,
    this.deliveryPct = 0,
    this.hotelExtensionsPct = 0,
    this.arrivalCancellationsPct = 0,
    this.coolingLoadPct = 0,
    this.staffAvailabilityPct = 0,
    this.powerRisk = 'low',
  });

  final double outdoorDemandPct;
  final double indoorDemandPct;
  final double cabSurge;
  final double dineInPct;
  final double deliveryPct;
  final double hotelExtensionsPct;
  final double arrivalCancellationsPct;
  final double coolingLoadPct;
  final double staffAvailabilityPct;
  final String powerRisk;

  static EcosystemImpact of(WeatherDay w, {double scale = 1}) {
    final rl = w.rainLevel, hl = w.heatLevel, wl = w.windLevel, al = w.alert.index;
    double s(num v) => v * scale;
    return EcosystemImpact(
      outdoorDemandPct: -s(math.min(90, 9 * rl + 10 * hl + 8 * wl + 8 * al)),
      indoorDemandPct: s(math.min(60, 7 * rl + 8 * hl) - (al >= 3 ? 25 : 0)),
      cabSurge: 1 + s(0.12 * rl + (hl >= 3 ? 0.1 : 0) + const [0.0, 0.0, 0.1, 0.25][al]),
      dineInPct: -s(math.min(70, 6 * rl + 3 * hl + 5 * al)),
      deliveryPct: s(math.min(80, 9 * rl + 5 * hl + 5 * al)),
      hotelExtensionsPct: s(math.min(40, 4 * rl + (al >= 2 ? 6 : 0))),
      arrivalCancellationsPct: s(math.min(60, 5 * rl + 8 * al)),
      coolingLoadPct: math.max(0, (w.tempMaxC - 30) * 3.5),
      staffAvailabilityPct: -s(math.min(50, 3 * rl + 7 * al)),
      powerRisk: (wl >= 2 || rl >= 4 || al >= 3)
          ? 'high'
          : (rl >= 3 || wl >= 1)
          ? 'moderate'
          : 'low',
    );
  }
}

/// One link in the chain from weather to the trip. [order] 1 is the weather's
/// direct effect on a place, 2 what that does to travel and the stay, 3 the
/// knock-on effects (crowds, a day that runs out of time, cost).
class TwinEffect {
  const TwinEffect({required this.order, required this.day, required this.text, required this.kind});

  final int order;
  final int day;
  final String text;

  /// weather, visit, leg, hotel, crowd, time, social, cost.
  final String kind;
}

class TwinDay {
  const TwinDay({
    required this.number,
    required this.date,
    required this.live,
    required this.weather,
    required this.simulated,
    required this.forecastIsReal,
    required this.visits,
    required this.legs,
    required this.extraMinutes,
    required this.overflowMinutes,
    required this.ecosystem,
  });

  final int number;
  final DateTime date;
  final WeatherDay live;
  final WeatherDay weather;

  /// The scenario changed this day's weather.
  final bool simulated;

  /// The live weather is a real forecast (not a seasonal estimate).
  final bool forecastIsReal;
  final List<TwinVisit> visits;
  final List<TwinLeg> legs;
  final int extraMinutes;
  final int overflowMinutes;
  final EcosystemImpact ecosystem;
}

/// The twin's picture of the trip under one scenario. It is computed on a copy:
/// the traveller's itinerary is never changed.
class TwinState {
  const TwinState({
    required this.scenario,
    required this.days,
    required this.effects,
    this.hotelAtRisk = false,
    this.hotelNote,
    this.signalsApplied = 0,
    this.source = RiskSource.rules,
  });

  final TwinScenario scenario;
  final List<TwinDay> days;
  final List<TwinEffect> effects;
  final bool hotelAtRisk;
  final String? hotelNote;
  final int signalsApplied;

  /// Who judged the places: the aligned model or the rules.
  final RiskSource source;

  Iterable<TwinVisit> get visits => days.expand((d) => d.visits);
  Iterable<TwinLeg> get legs => days.expand((d) => d.legs);

  int get visitsTotal => visits.length;
  int get visitsKept => visits.where((v) => v.state != VisitState.closed && v.state != VisitState.dropped).length;
  int get disrupted => visits.where((v) => v.state.disrupted).length;
  int get extraTravelMin => legs.fold(0, (s, l) => s + l.extraMin) + visits.fold(0, (s, v) => s + v.queueExtraMin);
  int get extraCostInr => legs.fold(0, (s, l) => s + l.simCostInr - l.baseCostInr);
  double get extraCo2Kg => legs.fold(0, (s, l) => s + l.simCo2g - l.baseCo2g) / 1000;
}

/// Monte Carlo spread for one scenario: weather drawn around the scenario (or
/// the forecast's own rain chance), each run simulated.
class TwinOutlook {
  const TwinOutlook({
    required this.runs,
    required this.pDisrupted,
    required this.extraMin,
    required this.extraCostInr,
    required this.visitsKept,
    required this.co2KgP50,
    required this.pAnyDisruption,
  });

  final int runs;

  /// Chance each visit ([TwinVisit.key]) is closed, dropped or disrupted.
  final Map<String, double> pDisrupted;

  /// p10, p50, p90.
  final (int, int, int) extraMin;
  final (int, int, int) extraCostInr;
  final (int, int, int) visitsKept;
  final double co2KgP50;

  /// Chance at least one visit is disrupted.
  final double pAnyDisruption;
}

typedef ImpactLookup = PlaceImpact Function(String visitKey, String category, WeatherDay weather);

/// The weather digital twin of one itinerary: its places, legs, stay and days,
/// and how weather (live or imagined) propagates through them.
class WeatherTwin {
  WeatherTwin({
    required this.itinerary,
    required this.live,
    this.forecastIsReal = const {},
    this.needs = const {},
    TwinCalibration? calibration,
    this.dayEndHour = 21,
    this.dayEndMinute = 30,
  }) : calibration = calibration ?? TwinCalibration.memory();

  final Itinerary itinerary;

  /// Day number -> live forecast.
  final Map<int, WeatherDay> live;
  final Map<int, bool> forecastIsReal;
  final Set<AccessibilityNeed> needs;
  final TwinCalibration calibration;
  final int dayEndHour;
  final int dayEndMinute;

  static const _defaultWeather = WeatherDay(tempMaxC: 30, rainMm: 0, rainProb: 10, windKmh: 12);
  static const _rainTimeFactor = [1.0, 1.1, 1.25, 1.5, 1.9, 2.4];

  bool get _mobility => needs.any((n) => n == AccessibilityNeed.wheelchair || n == AccessibilityNeed.limitedMobility || n == AccessibilityNeed.elderlyCare);

  String get city => itinerary.destination.split(',').first.trim();

  WeatherDay liveFor(int day) => live[day] ?? _defaultWeather;

  /// The simulated weather for every day.
  Map<int, WeatherDay> weatherOf(TwinScenario s) => {for (final d in itinerary.days) d.number: s.weatherFor(d.number, liveFor(d.number))};

  /// The day the live social reports are applied to: today when the trip is
  /// under way, otherwise the scenario's first day (as a what-if).
  int socialDay(TwinScenario s, DateTime now) {
    for (final d in itinerary.days) {
      if (d.date.year == now.year && d.date.month == now.month && d.date.day == now.day) return d.number;
    }
    return s.startDay.clamp(1, math.max(1, itinerary.days.length));
  }

  /// Simulates [s], asking [risk] (the aligned model, or rules) how each place
  /// fares in its day's weather.
  Future<TwinState> simulate(TwinScenario s, TravelRiskModel risk, {List<WeatherSignal> signals = const [], DateTime? now}) async {
    final weather = weatherOf(s);
    final impacts = <String, PlaceImpact>{};
    final jobs = <Future<void>>[];
    for (final d in itinerary.days) {
      for (final slot in d.slots) {
        if (slot.kind != SlotKind.visit) continue;
        final category = RuleTravelRisk.categoryFromName(slot.title);
        final key = '${d.number}:${slot.title}';
        jobs.add(
          risk
              .weatherImpact(place: slot.title, category: category, city: city, date: d.date, weather: weather[d.number]!)
              .then((i) => impacts[key] = i)
              .catchError((_) => impacts[key] = RuleTravelRisk.impactFor(category, weather[d.number]!)),
        );
      }
    }
    await Future.wait(jobs);
    return run(
      s,
      (key, category, w) => impacts[key] ?? RuleTravelRisk.impactFor(category, w),
      signals: signals,
      now: now,
      source: risk.isAligned ? RiskSource.aligned : RiskSource.rules,
    );
  }

  /// One deterministic pass (or one Monte Carlo draw when [rng] is given:
  /// then at-risk places are disrupted with the learned probability).
  TwinState run(
    TwinScenario s,
    ImpactLookup impactOf, {
    List<WeatherSignal> signals = const [],
    Map<int, WeatherDay>? weather,
    math.Random? rng,
    DateTime? now,
    RiskSource source = RiskSource.rules,
  }) {
    final dist = const Distance();
    final effects = <TwinEffect>[];
    final hotel = itinerary.hotel?.location;
    final flood = s.hasFlood ? s.floodCenter : null;
    bool flooded(LatLng? p) => flood != null && p != null && dist.as(LengthUnit.Meter, flood, p) <= s.floodRadiusKm * 1000;

    final socialOn = s.useSocial && signals.isNotEmpty;
    final sDay = socialDay(s, now ?? DateTime.now());
    var signalsApplied = 0;

    final hotelAtRisk = flooded(hotel);
    String? hotelNote;
    if (hotelAtRisk) {
      hotelNote = 'Your hotel is inside the simulated flood area; getting in and out is slow and may need a vehicle that can handle water.';
      effects.add(TwinEffect(order: 2, day: s.startDay, kind: 'hotel', text: 'Stay at risk: ${itinerary.hotel!.name} is inside the flooded area.'));
    }
    if (socialOn && hotel != null) {
      for (final sig in signals) {
        if (sig.event.type == 'power_cut' && sig.location != null && dist.as(LengthUnit.Kilometer, sig.location!, hotel) <= 3) {
          hotelNote = 'People report a power cut near your hotel: ${sig.post.text}';
          effects.add(TwinEffect(order: 2, day: sDay, kind: 'social', text: 'Reported power cut near ${itinerary.hotel!.name}; hotels run on generators.'));
          signalsApplied++;
        }
      }
    }

    final days = <TwinDay>[];
    for (final d in itinerary.days) {
      final live = liveFor(d.number);
      final w = weather?[d.number] ?? s.weatherFor(d.number, live);
      final simulated = weather != null || s.covers(d.number);
      final rl = w.rainLevel, hl = w.heatLevel;
      if (simulated && (rl >= 2 || hl >= 2 || w.windLevel >= 1 || w.alert.index >= 2) && rng == null) {
        final alert = w.alert == WeatherAlert.none ? '' : ', ${w.alert.name} alert for ${w.alertFor}';
        effects.add(TwinEffect(order: 1, day: d.number, kind: 'weather', text: 'Day ${d.number}: ${w.summary} (${rl >= hl ? w.rainClass : w.heatClass}$alert).'));
      }
      final applySocial = socialOn && d.number == sDay;

      final visits = <TwinVisit>[];
      final legs = <TwinLeg>[];
      var freed = 0;
      var extra = 0;
      DateTime? lastEnd;
      var firstLeg = true;

      for (final slot in d.slots) {
        if (lastEnd == null || slot.end.isAfter(lastEnd)) lastEnd = slot.end;
        if (slot.kind == SlotKind.visit) {
          final category = RuleTravelRisk.categoryFromName(slot.title);
          final key = '${d.number}:${slot.title}';
          final impact = impactOf(key, category, w);
          var state = VisitState.ok;
          var why = impact.level == ImpactLevel.none ? '' : impact.reason;
          String? reported;

          final report = applySocial ? _closureReport(slot.title, slot.location, signals) : null;
          if (flooded(slot.location)) {
            state = VisitState.closed;
            why = 'Inside the simulated flood area.';
          } else if (report != null) {
            state = VisitState.closed;
            why = 'Reported closed: “${report.post.text}”';
            reported = report.post.source;
            signalsApplied++;
          } else {
            switch (impact.level) {
              case ImpactLevel.closed:
                state = VisitState.closed;
              case ImpactLevel.high:
                state = rng == null || rng.nextDouble() < calibration.pDisrupt(category, ImpactLevel.high) ? VisitState.atRisk : VisitState.ok;
              case ImpactLevel.moderate:
                final slotTime = _timeOfDay(slot.start);
                final better = impact.bestTime;
                if (rng != null && rng.nextDouble() < calibration.pDisrupt(category, ImpactLevel.moderate)) {
                  state = VisitState.atRisk;
                } else if (better != 'any' && better != 'avoid' && better != slotTime) {
                  state = VisitState.shifted;
                  why = 'Better in the $better: ${impact.reason}';
                }
              case ImpactLevel.low:
                if (rng != null && rng.nextDouble() < calibration.pDisrupt(category, ImpactLevel.low)) state = VisitState.atRisk;
              case ImpactLevel.none:
                break;
            }
          }

          // Crowds move indoors on bad days: longer queues there.
          var queue = 0;
          if (state != VisitState.closed && RuleTravelRisk.isIndoor(category) && (rl >= 2 || hl >= 2)) {
            queue = ((rl >= 3 || hl >= 3 ? 25 : 15) * calibration.demandScale).round();
            extra += queue;
          }
          if (state == VisitState.closed) freed += slot.end.difference(slot.start).inMinutes;

          if (rng == null) {
            if (state == VisitState.closed) {
              effects.add(TwinEffect(order: 1, day: d.number, kind: reported != null ? 'social' : 'visit', text: '${slot.title} closed: $why'));
            } else if (state == VisitState.atRisk) {
              effects.add(TwinEffect(order: 1, day: d.number, kind: 'visit', text: '${slot.title} at risk (${impact.level.name} impact): ${impact.reason}'));
            } else if (state == VisitState.shifted) {
              effects.add(TwinEffect(order: 1, day: d.number, kind: 'visit', text: '${slot.title}: $why'));
            }
            if (queue > 0) {
              effects.add(TwinEffect(order: 3, day: d.number, kind: 'crowd', text: 'Visitors crowd into indoor places: about $queue min longer at ${slot.title}.'));
            }
          }
          visits.add(
            TwinVisit(
              day: d.number,
              name: slot.title,
              category: category,
              location: slot.location,
              start: slot.start,
              end: slot.end,
              impact: impact,
              state: state,
              why: why,
              queueExtraMin: queue,
              reportedBy: reported,
            ),
          );
        } else if (slot.kind == SlotKind.transit && slot.leg != null) {
          final leg = _leg(d.number, slot.leg!, w, flooded, applySocial ? signals : const [], hotelAtRisk && firstLeg, rng);
          firstLeg = false;
          extra += leg.extraMin;
          legs.add(leg);
          if (rng == null && leg.changed) {
            final what = leg.blocked
                ? 'no safe route (${leg.note})'
                : leg.becameCab
                ? 'walk becomes a cab (${leg.note}), +₹${leg.simCostInr - leg.baseCostInr}'
                : '+${leg.extraMin} min${leg.simCostInr > leg.baseCostInr ? ', +₹${leg.simCostInr - leg.baseCostInr}' : ''}${leg.note == null ? '' : ' (${leg.note})'}';
            effects.add(TwinEffect(order: 2, day: d.number, kind: 'leg', text: '${leg.from} → ${leg.to}: $what.'));
          }
        }
      }

      // A day that runs out of time drops its last places.
      var overflow = 0;
      if (lastEnd != null) {
        final limit = DateTime(d.date.year, d.date.month, d.date.day, dayEndHour, dayEndMinute);
        final baseEnd = lastEnd.isAfter(limit) ? lastEnd : limit;
        overflow = lastEnd.add(Duration(minutes: extra - freed)).difference(baseEnd).inMinutes;
        if (overflow > 0) {
          var remaining = overflow;
          for (var i = visits.length - 1; i >= 0 && remaining > 0; i--) {
            final v = visits[i];
            if (v.state == VisitState.closed || v.state == VisitState.dropped) continue;
            visits[i] = TwinVisit(
              day: v.day,
              name: v.name,
              category: v.category,
              location: v.location,
              start: v.start,
              end: v.end,
              impact: v.impact,
              state: VisitState.dropped,
              why: 'The day runs about $overflow min late with the slower travel; dropped to keep the evening free.',
              queueExtraMin: v.queueExtraMin,
            );
            remaining -= v.minutes;
            if (rng == null) {
              effects.add(TwinEffect(order: 3, day: d.number, kind: 'time', text: 'Day ${d.number} runs ~$overflow min over: ${v.name} dropped.'));
            }
          }
        }
      }

      days.add(
        TwinDay(
          number: d.number,
          date: d.date,
          live: live,
          weather: w,
          simulated: simulated,
          forecastIsReal: forecastIsReal[d.number] ?? false,
          visits: visits,
          legs: legs,
          extraMinutes: extra - freed,
          overflowMinutes: math.max(0, overflow),
          ecosystem: EcosystemImpact.of(w, scale: calibration.demandScale),
        ),
      );
    }

    final state = TwinState(
      scenario: s,
      days: days,
      effects: effects,
      hotelAtRisk: hotelAtRisk,
      hotelNote: hotelNote,
      signalsApplied: signalsApplied,
      source: source,
    );
    if (rng == null && state.extraCostInr > 0) {
      effects.add(TwinEffect(order: 3, day: s.startDay, kind: 'cost', text: 'Trip cost +₹${state.extraCostInr} and +${state.extraCo2Kg.toStringAsFixed(1)} kg CO₂ from cabs and surge fares.'));
    }
    return state;
  }

  TwinLeg _leg(int day, TransportLeg l, WeatherDay w, bool Function(LatLng?) flooded, List<WeatherSignal> signals, bool fromFloodedHotel, math.Random? rng) {
    final path = [if (l.fromPoint != null) l.fromPoint!, if (l.toPoint != null) l.toPoint!];
    final mid = path.length == 2 ? LatLng((path[0].latitude + path[1].latitude) / 2, (path[0].longitude + path[1].longitude) / 2) : null;
    final throughFlood = flooded(l.fromPoint) || flooded(l.toPoint) || flooded(mid);
    // Both ends under water: no safe road route between them.
    final blocked = !l.walking && flooded(l.fromPoint) && flooded(l.toPoint);
    var factor = _rainTimeFactor[w.rainLevel] * (w.windLevel >= 2 ? 1.2 : 1.0);
    final notes = <String>[];
    if (w.rainLevel >= 2) notes.add(w.rainClass.toLowerCase());
    if (throughFlood) {
      factor *= 2.5;
      notes.add('through the flooded area');
    }
    if (fromFloodedHotel) {
      factor *= 1.5;
      notes.add('leaving a flooded area');
    }
    // What people are reporting on this route.
    if (signals.isNotEmpty && path.isNotEmpty) {
      const dist = Distance();
      for (final sig in signals) {
        final loc = sig.location;
        if (loc == null || !const {'waterlogging', 'flooding', 'road_closed', 'landslide', 'storm'}.contains(sig.event.type)) continue;
        final near = [...path, ?mid].any((p) => dist.as(LengthUnit.Kilometer, loc, p) <= 1.2);
        if (!near) continue;
        factor *= switch (sig.event.severity) {
          EventSeverity.high => 2.2,
          EventSeverity.moderate => 1.6,
          _ => 1.3,
        };
        notes.add('reported ${sig.event.label}${sig.event.place == null ? '' : ' at ${sig.event.place}'}');
      }
    }
    if (rng != null) factor *= 0.9 + rng.nextDouble() * 0.25;

    final km = l.distanceKm;
    final surge = 1 + (0.12 * w.rainLevel + (w.heatLevel >= 3 ? 0.1 : 0) + const [0.0, 0.0, 0.1, 0.25][w.alert.index]) * calibration.surgeScale;
    final mustRide = w.rainLevel >= 2 || w.heatLevel >= 2 || throughFlood || (_mobility && (w.rainLevel >= 1 || w.heatLevel >= 1));

    if (l.walking && mustRide) {
      final minutes = math.max(8, (km / 18 * 60 * _rainTimeFactor[w.rainLevel] * (throughFlood ? 2.5 : 1)).round());
      final cost = (math.max(60, 22 * km) * surge).round();
      final why = w.heatLevel >= 2 && w.rainLevel < 2
          ? 'too hot to walk'
          : throughFlood
          ? 'flooded streets'
          : _mobility && w.rainLevel < 2 && w.heatLevel < 2
          ? 'wet or hot paths, reduced mobility'
          : 'rain';
      return TwinLeg(
        day: day,
        from: l.from,
        to: l.to,
        mode: 'Cab',
        walking: false,
        km: km,
        baseMin: l.durationMin,
        simMin: minutes,
        baseCostInr: l.costInr,
        simCostInr: l.costInr + cost,
        baseCo2g: l.co2Grams,
        simCo2g: l.co2Grams + (TripTransportMode.carTaxi.gCo2PerPaxKm * km).round(),
        becameCab: true,
        throughFlood: throughFlood,
        note: why,
        path: path,
      );
    }
    final isCab = !l.walking && const {TripTransportMode.carTaxi, TripTransportMode.sharedEv, TripTransportMode.selfDriveEv}.contains(l.mode);
    final isRail = l.mode == TripTransportMode.metroLocal || l.mode == TripTransportMode.train;
    final f = isRail ? 1 + (factor - 1) * 0.5 : factor;
    final sim = blocked ? l.durationMin * 3 : (l.durationMin * f).round();
    final cost = isCab && surge > 1.001 ? (l.costInr * surge).round() : l.costInr;
    if (isCab && surge > 1.05) notes.add('surge ×${surge.toStringAsFixed(2)}');
    return TwinLeg(
      day: day,
      from: l.from,
      to: l.to,
      mode: l.modeLabel,
      walking: l.walking,
      km: km,
      baseMin: l.durationMin,
      simMin: sim,
      baseCostInr: l.costInr,
      simCostInr: cost,
      baseCo2g: l.co2Grams,
      simCo2g: l.co2Grams,
      throughFlood: throughFlood,
      blocked: blocked,
      note: notes.isEmpty ? null : notes.join(', '),
      path: path,
    );
  }

  static WeatherSignal? _closureReport(String name, LatLng? at, List<WeatherSignal> signals) {
    final n = name.toLowerCase();
    const dist = Distance();
    for (final s in signals) {
      if (s.event.type != 'attraction_closed' && !(s.event.type == 'flooding' && s.event.affects.contains('attraction'))) continue;
      final p = s.event.place?.toLowerCase();
      final byName = p != null && p.length >= 4 && (n.contains(p) || p.contains(n) || _sharedWords(n, p) >= 2);
      // A geocoded report on the very spot (neighbours a few hundred metres
      // away are separate places).
      final byPlace = at != null && s.location != null && s.event.place != null && dist.as(LengthUnit.Meter, at, s.location!) <= 200;
      if (byName || byPlace) return s;
    }
    return null;
  }

  static int _sharedWords(String a, String b) {
    final wa = a.split(RegExp(r'\W+')).where((w) => w.length > 2).toSet();
    return b.split(RegExp(r'\W+')).where((w) => w.length > 2 && wa.contains(w)).length;
  }

  static String _timeOfDay(DateTime t) => t.hour < 12
      ? 'morning'
      : t.hour < 16
      ? 'afternoon'
      : 'evening';

  // --- uncertainty -----------------------------------------------------------------

  /// [runs] draws of the weather around [s] (the forecast's rain chance on
  /// live days; ±35% rain and ±1 °C on simulated days), each run through the
  /// rules and the learned chance that an at-risk place really is disrupted.
  TwinOutlook monteCarlo(TwinScenario s, {int runs = 200, int seed = 11, List<WeatherSignal> signals = const [], DateTime? now}) {
    final rng = math.Random(seed);
    final counts = <String, int>{};
    final extraMin = <int>[];
    final extraCost = <int>[];
    final kept = <int>[];
    final co2 = <double>[];
    var any = 0;
    for (var r = 0; r < runs; r++) {
      final weather = <int, WeatherDay>{};
      for (final d in itinerary.days) {
        final base = s.weatherFor(d.number, liveFor(d.number));
        double rain;
        if (s.covers(d.number) && s.rainMm != null) {
          rain = base.rainMm * _logNormal(rng, 0.35);
        } else {
          var p = base.rainProb / 100;
          if (base.rainMm >= 1 && p < 0.3) p = 0.5;
          rain = rng.nextDouble() < p ? math.max(base.rainMm, 3) * _logNormal(rng, 0.6) : 0;
        }
        weather[d.number] = base.copyWith(
          rainMm: rain,
          tempMaxC: base.tempMaxC + _normal(rng) * (s.covers(d.number) ? 1.0 : 1.5),
          windKmh: math.max(0, base.windKmh + _normal(rng) * 6),
        );
      }
      final st = run(s, (key, category, w) => RuleTravelRisk.impactFor(category, w), signals: signals, weather: weather, rng: rng, now: now);
      var disruptedHere = false;
      for (final v in st.visits) {
        if (v.state.disrupted) {
          counts[v.key] = (counts[v.key] ?? 0) + 1;
          disruptedHere = true;
        }
      }
      if (disruptedHere) any++;
      extraMin.add(st.extraTravelMin);
      extraCost.add(st.extraCostInr);
      kept.add(st.visitsKept);
      co2.add(st.extraCo2Kg);
    }
    (int, int, int) pct(List<int> xs) {
      xs.sort();
      int at(double q) => xs[((xs.length - 1) * q).round()];
      return (at(0.1), at(0.5), at(0.9));
    }

    co2.sort();
    return TwinOutlook(
      runs: runs,
      pDisrupted: {for (final e in counts.entries) e.key: e.value / runs},
      extraMin: pct(extraMin),
      extraCostInr: pct(extraCost),
      visitsKept: pct(kept),
      co2KgP50: co2[co2.length ~/ 2],
      pAnyDisruption: any / runs,
    );
  }

  static double _normal(math.Random rng) {
    final u1 = math.max(1e-9, rng.nextDouble());
    final u2 = rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  static double _logNormal(math.Random rng, double sigma) => math.exp(_normal(rng) * sigma - sigma * sigma / 2);
}
