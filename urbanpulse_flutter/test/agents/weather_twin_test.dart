import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbanpulse/agents/travel_risk/travel_risk.dart';
import 'package:urbanpulse/agents/travel_risk/travel_risk_rules.dart';
import 'package:urbanpulse/agents/twin/social_signals.dart';
import 'package:urbanpulse/agents/twin/twin_calibration.dart';
import 'package:urbanpulse/agents/twin/twin_demo.dart';
import 'package:urbanpulse/agents/twin/weather_twin.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';
import 'package:urbanpulse/models/trip_brief.dart';

const _clear = WeatherDay(tempMaxC: 31, rainMm: 0, rainProb: 5, windKmh: 12);

WeatherTwin _twin(Itinerary it, {TwinCalibration? calibration}) =>
    WeatherTwin(itinerary: it, live: {for (final d in it.days) d.number: _clear}, forecastIsReal: {for (final d in it.days) d.number: true}, calibration: calibration);

TwinVisit _visit(TwinState s, String name) => s.visits.firstWhere((v) => v.name == name);

/// A one-day Goa trip: a beach, a waterfall, a boat cruise and a museum.
Itinerary _goa() {
  final d = DateTime(2026, 7, 14);
  DateTime at(int h, int m) => DateTime(d.year, d.month, d.day, h, m);
  ItinerarySlot visit(int h1, int h2, String name, LatLng p) => ItinerarySlot(kind: SlotKind.visit, start: at(h1, 0), end: at(h2, 0), title: name, location: p);
  const baga = LatLng(15.5553, 73.7517);
  const falls = LatLng(15.3144, 74.3143);
  const cruise = LatLng(15.5009, 73.8274);
  const museum = LatLng(15.4989, 73.8278);
  return Itinerary(
    id: 'goa',
    createdAt: d,
    destination: 'Goa',
    origin: 'Mumbai',
    start: at(8, 0),
    end: at(20, 0),
    days: [
      ItineraryDay(
        number: 1,
        date: d,
        title: 'Goa',
        slots: [
          visit(8, 10, 'Baga Beach', baga),
          ItinerarySlot(
            kind: SlotKind.transit,
            start: at(10, 0),
            end: at(11, 30),
            title: 'Cab',
            leg: const TransportLeg(id: 'l1', from: 'Baga Beach', to: 'Dudhsagar Falls', mode: TripTransportMode.carTaxi, distanceKm: 70, durationMin: 90, costInr: 2500, fromPoint: baga, toPoint: falls),
          ),
          visit(11, 14, 'Dudhsagar Falls', falls),
          visit(16, 17, 'Mandovi River Cruise', cruise),
          visit(17, 19, 'Goa State Museum', museum),
        ],
      ),
    ],
    budget: const Budget(lines: []),
  );
}

void main() {
  final it = TwinDemo.jaipur(start: DateTime(2026, 10, 12));
  const risk = RuleTravelRisk();

  test('under a clear live forecast nothing changes', () async {
    final st = await _twin(it).simulate(const TwinScenario(), risk);
    expect(st.visitsTotal, 11);
    expect(st.visitsKept, 11);
    expect(st.disrupted, 0);
    expect(st.extraTravelMin, 0);
    expect(st.extraCostInr, 0);
    expect(st.effects, isEmpty);
  });

  test('a monsoon downpour on day 2 propagates: forts at risk, walks become cabs, fares surge', () async {
    final s = TwinScenario.presets(it).firstWhere((p) => p.id == 'downpour');
    final st = await _twin(it).simulate(s, risk);
    // 1st order: the outdoor places of day 2
    expect(_visit(st, 'Amber Fort').state, anyOf(VisitState.atRisk, VisitState.closed));
    expect(_visit(st, 'Amber Fort').impact.sensitiveTo, contains('rain'));
    // day 1 and 3 keep the live forecast
    expect(_visit(st, 'Hawa Mahal').state, VisitState.ok);
    expect(_visit(st, 'Albert Hall Museum').state, VisitState.ok);
    // 2nd order: the walk between Amber Fort and Panna Meena ka Kund becomes a cab; cabs surge
    final walk = st.legs.firstWhere((l) => l.from == 'Amber Fort');
    expect(walk.becameCab, isTrue);
    expect(walk.simCostInr, greaterThan(walk.baseCostInr));
    final cab = st.legs.firstWhere((l) => l.from == 'ITC Rajputana' && l.day == 2);
    expect(cab.simMin, greaterThan(cab.baseMin));
    expect(cab.simCostInr, greaterThan(cab.baseCostInr));
    // 3rd order: cost and time for the trip
    expect(st.extraCostInr, greaterThan(0));
    expect(st.extraTravelMin, greaterThan(0));
    expect(st.effects.map((e) => e.order).toSet(), containsAll([1, 2, 3]));
  });

  test('a cloudburst puts every outdoor place at risk and moves demand indoors', () async {
    const s = TwinScenario(id: 't', name: 'Cloudburst', rainMm: 220, windKmh: 50, alert: WeatherAlert.red, alertFor: 'heavy rain', startDay: 2, durationDays: 1);
    final st = await _twin(it).simulate(s, risk);
    for (final name in ['Amber Fort', 'Panna Meena ka Kund', 'Jal Mahal', 'Nahargarh Fort']) {
      expect(_visit(st, name).impact.level, ImpactLevel.high, reason: name);
    }
    for (final name in ['Amber Fort', 'Panna Meena ka Kund', 'Jal Mahal']) {
      expect(_visit(st, name).state, VisitState.atRisk, reason: name);
    }
    // 3rd order: every cab crawls, the day runs late and its last place is dropped
    expect(_visit(st, 'Nahargarh Fort').state, VisitState.dropped);
    expect(st.days[1].overflowMinutes, greaterThan(0));
    expect(st.effects.any((e) => e.kind == 'time' && e.order == 3), isTrue);
    final day2 = st.days[1];
    expect(day2.ecosystem.outdoorDemandPct, lessThan(-40));
    expect(day2.ecosystem.deliveryPct, greaterThan(30));
    expect(day2.ecosystem.powerRisk, 'high');
  });

  test('heavy rain closes beaches, waterfalls and boats; the museum stays open', () async {
    final goa = _goa();
    const s = TwinScenario(id: 't', name: 'Downpour', rainMm: 120, windKmh: 45, alert: WeatherAlert.orange, alertFor: 'heavy rain', durationDays: 1);
    final st = await _twin(goa).simulate(s, risk);
    expect(_visit(st, 'Baga Beach').state, VisitState.closed);
    expect(_visit(st, 'Dudhsagar Falls').state, VisitState.closed);
    expect(_visit(st, 'Mandovi River Cruise').state, VisitState.closed);
    expect(_visit(st, 'Goa State Museum').state, isNot(VisitState.closed));
    expect(st.visitsKept, 1);
    expect(st.legs.single.simMin, greaterThan(st.legs.single.baseMin));
  });

  test('a heatwave moves outdoor visits to the morning and sends people indoors', () async {
    final s = TwinScenario.presets(it).firstWhere((p) => p.id == 'heatwave');
    final st = await _twin(it).simulate(s, risk);
    final hawa = _visit(st, 'Hawa Mahal');
    expect(hawa.impact.sensitiveTo, contains('heat'));
    expect(hawa.state, isNot(VisitState.ok));
    final museum = _visit(st, 'Albert Hall Museum');
    expect(museum.impact.level, ImpactLevel.none);
    expect(museum.queueExtraMin, greaterThan(0));
    // too hot to walk: the old-city walks become cabs
    expect(st.legs.where((l) => l.becameCab && l.day == 1), isNotEmpty);
    expect(st.days.first.ecosystem.coolingLoadPct, greaterThan(40));
  });

  test('a flood around the hotel puts the stay at risk and slows the first leg of each day', () async {
    final s = TwinScenario.presets(it).firstWhere((p) => p.id == 'flood');
    final st = await _twin(it).simulate(s, risk);
    expect(st.hotelAtRisk, isTrue);
    final first = st.legs.firstWhere((l) => l.from == 'ITC Rajputana' && l.day == 1);
    expect(first.throughFlood, isTrue);
    expect(first.simMin, greaterThan(first.baseMin * 2));
    expect(st.effects.any((e) => e.kind == 'hotel'), isTrue);
  });

  test('simulating never changes the itinerary', () async {
    final before = jsonEncode(it.toJson());
    final twin = _twin(it);
    for (final s in TwinScenario.presets(it)) {
      await twin.simulate(s, risk);
      twin.monteCarlo(s, runs: 30);
    }
    expect(jsonEncode(it.toJson()), before);
  });

  test('Monte Carlo bands are ordered and repeatable', () {
    final s = TwinScenario.presets(it).firstWhere((p) => p.id == 'downpour');
    final a = _twin(it).monteCarlo(s, runs: 150, seed: 3);
    final b = _twin(it).monteCarlo(s, runs: 150, seed: 3);
    expect(a.extraMin.$1 <= a.extraMin.$2 && a.extraMin.$2 <= a.extraMin.$3, isTrue);
    expect(a.visitsKept.$1 <= a.visitsKept.$3, isTrue);
    expect(a.extraMin, b.extraMin);
    expect(a.pDisrupted, b.pDisrupted);
    expect(a.pDisrupted['2:Amber Fort'], greaterThan(0.3));
    expect(a.pDisrupted['1:Albert Hall Museum'] ?? 0, 0);
    expect(a.pAnyDisruption, greaterThan(0.5));
  });

  test('a social report of a closure closes that place on the reported day', () async {
    final signal = WeatherSignal(
      post: const SocialPost(text: 'Amber Fort closed today due to heavy rain, officials say', source: 'Google News'),
      event: RuleTravelRisk.readEvent('Amber Fort closed today due to heavy rain, officials say'),
      location: const LatLng(26.9855, 75.8513),
    );
    final st = await _twin(it).simulate(const TwinScenario(startDay: 2), risk, signals: [signal], now: DateTime(2026, 9, 1));
    expect(_visit(st, 'Amber Fort').state, VisitState.closed);
    expect(_visit(st, 'Amber Fort').reportedBy, 'Google News');
    expect(st.signalsApplied, 1);
    // switched off, the report is ignored
    final off = await _twin(it).simulate(const TwinScenario(startDay: 2, useSocial: false), risk, signals: [signal], now: DateTime(2026, 9, 1));
    expect(_visit(off, 'Amber Fort').state, VisitState.ok);
  });

  test('the twin learns: feedback moves the disruption chance and is kept', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cal = TwinCalibration(prefs);
    final before = cal.pDisrupt('fort', ImpactLevel.high);
    await cal.record('fort', disrupted: true);
    await cal.record('fort', disrupted: true);
    expect(cal.pDisrupt('fort', ImpactLevel.high), greaterThan(before));
    await cal.record('garden', disrupted: false);
    expect(cal.pDisrupt('garden', ImpactLevel.high), lessThan(before));
    final again = TwinCalibration(prefs);
    expect(again.observations, 3);
    expect(again.pDisrupt('fort', ImpactLevel.high), cal.pDisrupt('fort', ImpactLevel.high));
  });

  test('news and Reddit posts are parsed', () {
    const rss = '''<rss><channel>
<item><title>Heavy rain lashes Jaipur, waterlogging on MI Road &amp; Tonk Road - Times of India</title><link>https://news.google.com/x</link><pubDate>Sat, 26 Sep 2026 14:05:00 GMT</pubDate></item>
<item><title><![CDATA[Amber Fort closed for tourists after red alert]]></title><link>https://news.google.com/y</link><pubDate>Sat, 26 Sep 2026 09:00:00 GMT</pubDate></item>
</channel></rss>''';
    final news = SocialSignalFeed.parseGoogleNewsRss(rss);
    expect(news, hasLength(2));
    expect(news.first.text, 'Heavy rain lashes Jaipur, waterlogging on MI Road & Tonk Road');
    expect(news.first.source, 'Google News · Times of India');
    expect(news[1].text, 'Amber Fort closed for tourists after red alert');
    expect(news.first.at, DateTime.utc(2026, 9, 26, 14, 5));

    final reddit = SocialSignalFeed.parseReddit(
      jsonEncode({
        'data': {
          'children': [
            {
              'data': {'title': 'Knee-deep water near Sindhi Camp', 'selftext': 'Avoid if you can', 'permalink': '/r/jaipur/1', 'created_utc': 1790000000},
            },
          ],
        },
      }),
    );
    expect(reddit.single.text, 'Knee-deep water near Sindhi Camp. Avoid if you can');
    expect(reddit.single.url, 'https://www.reddit.com/r/jaipur/1');
  });
}
