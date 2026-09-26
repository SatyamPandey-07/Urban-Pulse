import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../models/itinerary/itinerary.dart';
import '../../models/trip_brief.dart';
import '../../services/data/forecast_client.dart';
import '../travel_risk/travel_risk.dart';
import 'social_signals.dart';
import 'twin_calibration.dart';
import 'weather_twin.dart';

/// One line in the twin's history: a live update, a new report, something it
/// learned.
class TwinLogEntry {
  const TwinLogEntry(this.at, this.text, this.kind);

  final DateTime at;
  final String text;

  /// live, social, learn, scenario.
  final String kind;
}

/// Runs the weather twin of one itinerary for the screen: pulls the live
/// forecast and social signals, re-simulates whenever the scenario or the
/// world changes (the forecast every 15 minutes, reports every 20), and learns
/// from the traveller's feedback. The itinerary itself is never changed.
class TwinController extends ChangeNotifier {
  TwinController({
    required this.itinerary,
    required this.risk,
    required this.forecast,
    required this.calibration,
    this.feed,
    this.center,
    this.forecastEvery = const Duration(minutes: 15),
    this.signalsEvery = const Duration(minutes: 20),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Itinerary itinerary;
  final TravelRiskModel risk;
  final ForecastClient forecast;
  final TwinCalibration calibration;
  final SocialSignalFeed? feed;

  /// Where the trip is (the hotel, else the first place); null to work it out.
  final LatLng? center;
  final Duration forecastEvery;
  final Duration signalsEvery;
  final DateTime Function() _clock;

  TwinScenario scenario = const TwinScenario();
  Map<int, WeatherDay> live = {};
  Map<int, bool> forecastIsReal = {};
  DateTime? liveUpdatedAt;
  bool loadingLive = false;
  String? liveError;

  TwinState? baseline;
  TwinState? state;
  TwinOutlook? outlook;
  bool simulating = false;

  List<WeatherSignal> signals = [];
  bool loadingSignals = false;
  DateTime? signalsAt;
  final List<TwinLogEntry> timeline = [];

  Timer? _forecastTimer;
  Timer? _signalTimer;
  Timer? _debounce;
  int _simToken = 0;
  bool _disposed = false;

  Set<AccessibilityNeed> get needs => {for (final n in itinerary.brief?.accessibilityNeeds ?? const <AccessibilityNeed>{}) if (n != AccessibilityNeed.none) n};

  LatLng? get tripCenter =>
      center ?? itinerary.hotel?.location ?? [for (final d in itinerary.days) for (final s in d.slots) if (s.location != null) s.location!].firstOrNull;

  String get city => itinerary.destination.split(',').first.trim();

  WeatherTwin get twin => WeatherTwin(itinerary: itinerary, live: live, forecastIsReal: forecastIsReal, needs: needs, calibration: calibration);

  List<TwinScenario> get presets => TwinScenario.presets(itinerary);

  Future<void> start() async {
    await refreshLive();
    unawaited(refreshSignals());
    _forecastTimer = Timer.periodic(forecastEvery, (_) => refreshLive());
    _signalTimer = Timer.periodic(signalsEvery, (_) => refreshSignals());
  }

  void _log(String text, String kind) {
    timeline.insert(0, TwinLogEntry(_clock(), text, kind));
    if (timeline.length > 40) timeline.removeLast();
  }

  /// The live forecast for every trip day; a change from the last one is logged
  /// and re-simulated.
  Future<void> refreshLive() async {
    final c = tripCenter;
    if (c == null || _disposed) return;
    loadingLive = true;
    _notify();
    try {
      final days = await forecast.outlook(c.latitude, c.longitude, itinerary.start, itinerary.end, today: _clock());
      final byDate = {for (final f in days) f.date: f};
      final next = <int, WeatherDay>{};
      final real = <int, bool>{};
      for (final d in itinerary.days) {
        final f = byDate[_iso(d.date)];
        if (f == null) continue;
        next[d.number] = _fromForecast(f);
        real[d.number] = f.isForecast;
      }
      final changes = <String>[];
      for (final e in next.entries) {
        final before = live[e.key];
        if (before == null) continue;
        if ((before.rainMm - e.value.rainMm).abs() >= 2 || (before.tempMaxC - e.value.tempMaxC).abs() >= 1) {
          changes.add('Day ${e.key}: ${before.summary} → ${e.value.summary}');
        }
      }
      final first = live.isEmpty;
      live = next;
      forecastIsReal = real;
      liveUpdatedAt = _clock();
      liveError = next.isEmpty ? 'No forecast for these dates.' : null;
      if (first) {
        final n = real.values.where((r) => r).length;
        _log('Live weather loaded from Open-Meteo: $n day${n == 1 ? '' : 's'} forecast${next.length > n ? ', ${next.length - n} from past seasons' : ''}.', 'live');
      } else if (changes.isNotEmpty) {
        _log('Forecast changed. ${changes.join('; ')}', 'live');
      }
    } catch (e) {
      liveError = 'Live weather unavailable right now.';
    } finally {
      loadingLive = false;
    }
    await _simulate();
  }

  /// Reports people are posting about the weather at the destination.
  Future<void> refreshSignals() async {
    final f = feed;
    final c = tripCenter;
    if (f == null || c == null || _disposed) return;
    loadingSignals = true;
    _notify();
    try {
      final found = await f.signals(city, c, risk);
      final known = {for (final s in signals) s.post.text};
      final fresh = found.where((s) => !known.contains(s.post.text)).toList();
      final typed = signals.where((s) => s.post.source == 'You');
      signals = [...typed, ...found];
      signalsAt = _clock();
      if (fresh.isNotEmpty) {
        _log('${fresh.length} new report${fresh.length == 1 ? '' : 's'} (${f.lastSources.join(', ')}): ${fresh.first.event.label}${fresh.first.event.place == null ? '' : ' at ${fresh.first.event.place}'}.', 'social');
        await _learnFromReports(fresh);
      }
    } finally {
      loadingSignals = false;
    }
    await _simulate();
  }

  /// A report typed in the app, read by the same model as the real ones.
  Future<WeatherSignal?> addReport(String text) async {
    final f = feed ?? SocialSignalFeed();
    final c = tripCenter;
    if (c == null || text.trim().isEmpty) return null;
    final sig = await f.classify(text.trim(), city, c, risk);
    if (sig.event.isEvent) {
      signals = [sig, ...signals];
      _log('Your report read as ${sig.event.label} (${sig.event.severity.name})${sig.event.place == null ? '' : ' at ${sig.event.place}'}.', 'social');
      await _learnFromReports([sig]);
    } else {
      _log('Your report was not read as a travel disruption.', 'social');
    }
    await _simulate();
    return sig;
  }

  /// A closure reported where the forecast already expected trouble confirms
  /// the model: the twin learns from it.
  Future<void> _learnFromReports(List<WeatherSignal> fresh) async {
    final st = state;
    if (st == null) return;
    for (final sig in fresh) {
      if (sig.event.type != 'attraction_closed' || sig.event.place == null) continue;
      final p = sig.event.place!.toLowerCase();
      for (final v in st.visits) {
        if (v.name.toLowerCase().contains(p) || p.contains(v.name.toLowerCase())) {
          await calibration.record(v.category, disrupted: true, source: 'social');
          _log('Learned: ${v.name} (${v.category}) was reported closed; ${v.category} risk updated.', 'learn');
          break;
        }
      }
    }
  }

  /// The traveller says whether a warned-about visit really was disrupted.
  Future<void> feedback(TwinVisit v, {required bool disrupted}) async {
    final before = calibration.pDisrupt(v.category, ImpactLevel.high);
    await calibration.record(v.category, disrupted: disrupted);
    final after = calibration.pDisrupt(v.category, ImpactLevel.high);
    _log(
      'Learned from you: ${v.name} ${disrupted ? 'was' : 'was not'} disrupted. Chance a ${v.category.replaceAll('_', ' ')} is disrupted on a high-impact day: ${(before * 100).round()}% → ${(after * 100).round()}%.',
      'learn',
    );
    await _simulate();
  }

  void setScenario(TwinScenario s, {bool log = true}) {
    scenario = s;
    if (log) _log('What-if: ${s.name}.', 'scenario');
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _simulate);
    _notify();
  }

  Future<void> _simulate() async {
    if (_disposed) return;
    final token = ++_simToken;
    simulating = true;
    _notify();
    final t = twin;
    final now = _clock();
    final live0 = await t.simulate(const TwinScenario(), risk, signals: signals, now: now);
    final sim = scenario.isLive && scenario.useSocial ? live0 : await t.simulate(scenario, risk, signals: signals, now: now);
    if (token != _simToken || _disposed) return;
    baseline = live0;
    state = sim;
    outlook = t.monteCarlo(scenario, signals: signals, now: now);
    simulating = false;
    _notify();
  }

  static WeatherDay _fromForecast(DayForecast f) {
    final rain = f.rainMm ?? 0;
    return WeatherDay(
      tempMaxC: f.tempMaxC ?? 30,
      rainMm: rain,
      rainProb: f.rainProbability ?? (rain >= 1 ? 60 : 10),
      windKmh: 12,
    );
  }

  static String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _forecastTimer?.cancel();
    _signalTimer?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
