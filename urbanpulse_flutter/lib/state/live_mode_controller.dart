import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../agents/live/live_mode_engine.dart';
import '../core/formatting.dart';
import '../models/itinerary/itinerary.dart';
import '../services/live_location.dart';
import 'live_map_controller.dart' show distanceWords;

/// Live Mode: while a trip is under way, speaks what is coming up (through
/// whatever audio is connected, such as earbuds or a car) so the phone can stay
/// in a pocket. It watches the clock and the traveller's position against the
/// plan, and answers a few spoken questions.
class LiveModeController extends ChangeNotifier {
  LiveModeController({
    required this.location,
    required this.say,
    this.describe,
    this.onNavigate,
    this.keepAwake,
    DateTime Function()? now,
    this.checkEvery = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;

  final LiveLocation location;

  /// Speaks a line through the phone's audio output.
  final Future<void> Function(String text) say;

  /// A name for where a point is ("near MG Road"), or null.
  final Future<String?> Function(LatLng point)? describe;

  /// Sets off for a stop on the Live Map.
  final void Function(ItineraryDay day, String? refId)? onNavigate;

  /// Keeps the screen on (or lets it sleep) while Live Mode runs.
  final void Function(bool on)? keepAwake;

  final DateTime Function() _now;
  final Duration checkEvery;

  Itinerary? itinerary;
  ItineraryDay? day;
  LiveModeEngine? _engine;

  bool active = false;
  bool starting = false;

  /// Updates are paused until this time (the traveller asked for quiet).
  DateTime? quietUntil;

  UserFix? user;
  LocationStatus locationStatus = LocationStatus.unknown;

  /// What has been said, oldest first (shown on screen).
  final List<LiveUpdate> log = [];

  StreamSubscription<UserFix>? _watch;
  Timer? _timer;
  bool _disposed = false;
  String _lastSpoken = '';

  bool get quiet => quietUntil != null && _now().isBefore(quietUntil!);

  ItinerarySlot? get nextSlot => _engine?.nextSlot(_now());

  /// Metres to the next stop, if both are known.
  double? get metresToNext {
    final s = nextSlot;
    final u = user;
    if (s?.location == null || u == null) return null;
    return const Distance().as(LengthUnit.Meter, u.point, s!.location!);
  }

  /// The day of [it] that is today, or null if the trip is not on today.
  static ItineraryDay? dayForToday(Itinerary it, DateTime now) {
    for (final d in it.days) {
      if (d.date.year == now.year && d.date.month == now.month && d.date.day == now.day) return d;
    }
    return null;
  }

  // --- start and stop ----------------------------------------------------------------

  Future<void> start(Itinerary it, ItineraryDay chosen) async {
    if (active || starting) return;
    starting = true;
    itinerary = it;
    day = chosen;
    final iso = '${chosen.date.year.toString().padLeft(4, '0')}-${chosen.date.month.toString().padLeft(2, '0')}-${chosen.date.day.toString().padLeft(2, '0')}';
    _engine = LiveModeEngine(day: chosen, rainProbability: it.snapshot?.weather[iso]?.rainProbability);
    log.clear();
    quietUntil = null;
    _notify();

    LocationResult r;
    try {
      r = await location.request();
    } catch (_) {
      r = const LocationResult(LocationStatus.unavailable);
    }
    locationStatus = r.status;
    user = r.fix;

    active = true;
    starting = false;
    keepAwake?.call(true);
    _watch = location.watch(distanceFilterM: 10).listen((f) {
      user = f;
      locationStatus = LocationStatus.ok;
    }, onError: (_) {});
    _timer = Timer.periodic(checkEvery, (_) => tick());
    _notify();
    await _speak([_engine!.briefing(_now())]);
    if (r.fix == null) {
      await _speak([LiveUpdate(id: 'nogps', kind: UpdateKind.info, text: 'I cannot see your location, so I will only go by the clock. Turn on location for arrival and distance updates.', at: _now())]);
    }
    tick();
  }

  Future<void> stop({bool announce = true}) async {
    if (!active && !starting) return;
    _timer?.cancel();
    _timer = null;
    await _watch?.cancel();
    _watch = null;
    active = false;
    starting = false;
    keepAwake?.call(false);
    _notify();
    if (announce) await say('Live mode is off.');
  }

  // --- what to say ---------------------------------------------------------------------

  /// Looks at the clock and position against the plan; speaks anything due.
  Future<void> tick() async {
    final e = _engine;
    if (!active || e == null || quiet) return;
    final due = e.check(_now(), user?.point);
    if (due.isNotEmpty) await _speak(due);
    _notify();
  }

  Future<void> _speak(List<LiveUpdate> updates) async {
    if (updates.isEmpty) return;
    log.addAll(updates);
    if (log.length > 60) log.removeRange(0, log.length - 60);
    _lastSpoken = updates.map((u) => u.text).join(' ');
    _notify();
    try {
      await say(_lastSpoken);
    } catch (_) {
      // a speech engine that fails must not stop the trip
    }
  }

  // --- questions ---------------------------------------------------------------------------

  /// Answers something the traveller said.
  Future<String> ask(String words) async {
    final e = _engine;
    if (!active || e == null) return 'Live mode is not on.';
    final answer = await _answer(parseLiveCommand(words), e, words);
    if (answer.isNotEmpty) await _speak([LiveUpdate(id: 'ask:${log.length}', kind: UpdateKind.info, text: answer, at: _now())]);
    return answer;
  }

  Future<String> _answer(LiveCommand cmd, LiveModeEngine e, String words) async {
    final now = _now();
    final next = e.nextSlot(now);
    final metres = metresToNext;
    switch (cmd) {
      case LiveCommand.whatsNext:
        if (next == null) return 'There is nothing left in the plan for today.';
        final away = metres == null ? '' : ' It is ${distanceWords(metres)} from you.';
        return 'Next is ${next.title} at ${clock12(next.start)}.$away';
      case LiveCommand.howFar:
        if (next == null) return 'There is nothing left in the plan for today.';
        if (metres == null) return 'I cannot see your location, so I cannot tell how far ${next.title} is.';
        final (mins, how) = LiveModeEngine.travelEstimate(metres);
        return '${next.title} is ${distanceWords(metres)} away, roughly $mins minutes $how. That is an estimate.';
      case LiveCommand.whereAmI:
        final u = user;
        if (u == null) return 'I cannot see your location right now.';
        String? place;
        try {
          place = await describe?.call(u.point);
        } catch (_) {}
        return place == null ? 'I can see you, but I cannot name the place right now.' : 'You are near $place.';
      case LiveCommand.navigate:
        if (next == null) return 'There is nothing left in the plan to go to.';
        if (next.location == null) return '${next.title} has no map position, so I cannot navigate there.';
        final d = day;
        if (d == null || onNavigate == null) return 'Navigation is not available here.';
        onNavigate!(d, next.refId);
        return 'Taking you to ${next.title}. Directions will be spoken.';
      case LiveCommand.repeatLast:
        return _lastSpoken.isEmpty ? 'I have not said anything yet.' : _lastSpoken;
      case LiveCommand.today:
        final rest = [for (final s in e.slots) if (s.end.isAfter(now)) '${s.title} at ${clock12(s.start)}'];
        return rest.isEmpty ? 'The plan for today is done.' : 'Still to come today: ${rest.take(5).join(', ')}.';
      case LiveCommand.weather:
        final d = day;
        final rain = e.rainProbability;
        if (d?.weather == null && rain == null) return 'I do not have a forecast for today.';
        return 'Today: ${d?.weather ?? ''}${rain == null ? '' : ' Chance of rain about $rain percent.'}'.trim();
      case LiveCommand.quiet:
        quietUntil = now.add(const Duration(minutes: 30));
        _notify();
        return 'Quiet for thirty minutes. Say resume when you want updates again.';
      case LiveCommand.resume:
        quietUntil = null;
        _notify();
        return 'Updates are back on.';
      case LiveCommand.stop:
        unawaited(Future<void>.delayed(const Duration(milliseconds: 50), () => stop(announce: false)));
        return 'Turning live mode off.';
      case LiveCommand.unknown:
        return 'I can tell you what is next, how far it is, where you are, the weather, or take you there. To change the plan, use the edit screen.';
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _watch?.cancel();
    if (active) keepAwake?.call(false);
    super.dispose();
  }
}
