import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/sos/sos_backend.dart';
import '../services/sos/sos_locator.dart';
import '../services/sos/sos_models.dart';
import '../services/sos/sos_native.dart';

enum SosPhase { idle, sending, active, resolving }

/// How often things happen; shortened in tests.
class SosTimings {
  const SosTimings({
    this.heartbeat = const Duration(seconds: 60),
    this.noFixRetry = const Duration(seconds: 15),
    this.poll = const Duration(seconds: 60),
    this.presenceMaxAge = const Duration(minutes: 5),
    this.retryBase = const Duration(seconds: 5),
    this.retryMax = const Duration(seconds: 60),
  });

  final Duration heartbeat;
  final Duration noFixRetry;
  final Duration poll;
  final Duration presenceMaxAge;
  final Duration retryBase;
  final Duration retryMax;
}

/// Emergency SOS, end to end.
///
/// Your own SOS: [trigger] (three quick power-button presses, or the SOS
/// screen) records it on the phone first, takes a location fix and raises it in
/// Supabase; while it is active a heartbeat keeps its location current; it
/// stays active until you [resolve] it. Offline, every step is kept and retried.
///
/// Other people's: while signed in, this phone keeps its presence (location and
/// alert radius) up to date, so the database lets it see SOS events nearby;
/// they arrive over Supabase Realtime, with polling as the fallback.
class SosController extends ChangeNotifier {
  SosController({
    required SharedPreferences prefs,
    required String Function() myName,
    SosBackend? backend,
    SosLocator locator = const GeoSosLocator(),
    SosNative? native,
    DateTime Function()? now,
    this.timings = const SosTimings(),
  }) : _prefs = prefs,
       _myName = myName,
       _backend = backend,
       _locator = locator,
       _native = native ?? SosNative(),
       _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final String Function() _myName;
  final SosBackend? _backend;
  final SosLocator _locator;
  final SosNative _native;
  final DateTime Function() _now;
  final SosTimings timings;

  static const _keyLocal = 'sos.local.v1';
  static const _keyTrigger = 'sos.power_trigger';
  static const _keyRadius = 'sos.radius_km';

  /// An SOS nearby that this phone has not shown yet (for the in-app alert).
  final _alerts = StreamController<SosEvent>.broadcast();
  Stream<SosEvent> get newAlerts => _alerts.stream;

  /// Android asked to open the SOS screen (tapped a notification).
  final _openRequests = StreamController<void>.broadcast();
  Stream<void> get openRequests => _openRequests.stream;

  bool _disposed = false;

  // --- own SOS --------------------------------------------------------------------

  SosPhase phase = SosPhase.idle;
  SosEvent? mine;
  SosCategory category = SosCategory.general;
  SosSource _source = SosSource.app;
  DateTime? startedAt;
  SosPoint? lastFix;
  LocationIssue locationIssue = LocationIssue.none;

  /// Why the SOS has not reached (or left) the server yet, in plain words.
  String? syncProblem;
  int responders = 0;
  bool _cancelled = false;
  bool _sendInFlight = false;

  Timer? _heartbeat;
  Timer? _retry;
  int _retries = 0;
  DateTime? _lastMove;

  bool get signedIn => _backend?.userId != null;
  bool get hasAccounts => _backend != null;
  bool get isRaised => phase == SosPhase.sending || phase == SosPhase.active;

  // --- other people's -----------------------------------------------------------

  final Map<String, SosEvent> _nearby = {};
  final Set<String> _announced = {};
  bool watching = false;

  /// The live connection is up (false: polling only).
  bool live = false;
  DateTime? lastChecked;
  String? nearbyProblem;
  SosPoint? _presenceAt;
  DateTime? _presenceTime;
  SosSubscription? _sub;
  Timer? _poll;

  double get radiusKm => _prefs.getDouble(_keyRadius) ?? 5;

  /// Active, fresh SOS events nearby, closest first.
  List<SosEvent> get nearby {
    final now = _now();
    final here = _presenceAt ?? lastFix;
    final list = [for (final e in _nearby.values) if (e.isActive && !e.isStale(now)) e];
    if (here != null) {
      list.sort((a, b) => (distanceKm(a) ?? 1e9).compareTo(distanceKm(b) ?? 1e9));
    }
    return list;
  }

  double? distanceKm(SosEvent e) {
    final here = _presenceAt ?? lastFix;
    if (here == null || !e.hasLocation) return null;
    return here.kmTo(e.lat!, e.lng!);
  }

  // --- power button -------------------------------------------------------------

  bool get triggerSupported => _native.supported;
  bool get triggerEnabled => _prefs.getBool(_keyTrigger) ?? true;
  bool triggerRunning = false;
  Map<String, bool> nativeStatus = const {};

  // =============================================================================

  /// Restores an SOS left over from before a restart and connects to Android.
  Future<void> init() async {
    _loadLocal();
    final pending = await _native.ready(_onNative);
    await refreshNativeStatus();
    if (!_initialized.isCompleted) _initialized.complete();
    notifyListeners();
    if (pending != null) {
      // The power button fired before the app had started.
      unawaited(trigger(source: SosSource.powerButton));
      _openRequests.add(null);
    }
  }

  final _initialized = Completer<void>();

  /// Signed in (or a kept session at start): picks up any active SOS, sends or
  /// closes what was waiting, starts the power-button watch and nearby alerts.
  Future<void> onSignedIn() async {
    await _initialized.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    final b = _backend;
    if (b == null || b.userId == null) return;
    try {
      final server = await b.myActive();
      if (server != null && phase == SosPhase.idle) {
        // Raised from another session (or before the app was reinstalled).
        mine = server;
        category = server.category;
        startedAt = server.createdAt;
        phase = SosPhase.active;
        _saveLocal();
        unawaited(_native.setActive(true, detail: _activeDetail()));
        _startHeartbeat();
      } else if (server != null && phase == SosPhase.sending) {
        mine = server;
        phase = SosPhase.active;
        _saveLocal();
        _startHeartbeat();
      }
    } catch (_) {
      // offline: whatever is waiting is retried below
    }
    if (phase == SosPhase.sending) unawaited(_send());
    if (phase == SosPhase.resolving) unawaited(resolve(cancelled: _cancelled));
    if (triggerEnabled) unawaited(_startTrigger());
    unawaited(startWatching());
    notifyListeners();
  }

  Future<void> onSignedOut() async {
    await stopWatching();
    await _native.stopTrigger();
    triggerRunning = false;
    notifyListeners();
  }

  Future<void> _onNative(String method, Map<String, dynamic> args) async {
    switch (method) {
      case 'trigger':
        await trigger(source: args['source'] == 'notification' ? SosSource.notification : SosSource.powerButton);
        _openRequests.add(null);
      case 'cancel':
        await resolve(cancelled: true);
      case 'openSos':
        _openRequests.add(null);
    }
  }

  // --- raising --------------------------------------------------------------------

  /// Raises an SOS. A second trigger while one is being sent or is active does
  /// not raise another (it refreshes the location instead).
  Future<void> trigger({SosSource source = SosSource.app, SosCategory? category}) async {
    if (isRaised) {
      if (phase == SosPhase.active) unawaited(_beat(force: true));
      return;
    }
    _retry?.cancel();
    _retries = 0;
    this.category = category ?? SosCategory.general;
    _source = source;
    startedAt = _now();
    mine = null;
    responders = 0;
    syncProblem = null;
    _cancelled = false;
    phase = SosPhase.sending;
    _saveLocal();
    notifyListeners();
    unawaited(_native.setActive(true, detail: 'Sending your SOS…'));

    final (fix, issue) = await _locator.locate(precise: true);
    if (fix != null) lastFix = fix;
    locationIssue = issue;
    _saveLocal();
    notifyListeners();
    await _send();
  }

  Future<void> _send() async {
    if (phase != SosPhase.sending) return;
    final b = _backend;
    if (b == null || b.userId == null) {
      syncProblem = b == null
          ? 'This build has no accounts, so the SOS cannot reach anyone. Call 112.'
          : 'Sign in so your SOS reaches people nearby. Until then, call 112.';
      notifyListeners();
      return;
    }
    try {
      _sendInFlight = true;
      final SosEvent e;
      try {
        e = await b.raise(name: _firstName(), category: category, source: _source, at: lastFix);
      } finally {
        _sendInFlight = false;
      }
      mine = e;
      if (phase == SosPhase.resolving) {
        // Cancelled while it was on its way: close it at once.
        await resolve(cancelled: _cancelled);
        return;
      }
      phase = SosPhase.active;
      syncProblem = null;
      _retries = 0;
      _lastMove = _now();
      _saveLocal();
      unawaited(_native.setActive(true, detail: _activeDetail()));
      _startHeartbeat();
    } catch (_) {
      syncProblem = 'No connection. Your SOS is saved on this phone and will be sent as soon as there is a network.';
      _scheduleRetry(_send);
    }
    notifyListeners();
  }

  // --- while active ---------------------------------------------------------------

  void _startHeartbeat() {
    _heartbeat?.cancel();
    // Quick retries until there is a first fix, then once a minute.
    final every = lastFix == null ? timings.noFixRetry : timings.heartbeat;
    _heartbeat = Timer.periodic(every, (_) => _beat());
  }

  Future<void> _beat({bool force = false}) async {
    final id = mine?.id;
    final b = _backend;
    if (phase != SosPhase.active || id == null || b == null) return;
    final hadFix = lastFix != null;
    final (fix, issue) = await _locator.locate(precise: !hadFix);
    locationIssue = issue;
    final moved = fix != null && (lastFix == null || lastFix!.kmTo(fix.lat, fix.lng) * 1000 >= 25);
    final due = _lastMove == null || _now().difference(_lastMove!) >= timings.heartbeat;
    if (fix != null) lastFix = fix;
    if (moved || due || force) {
      try {
        await b.move(id, moved || !hadFix ? fix : null);
        _lastMove = _now();
        syncProblem = null;
        responders = await b.responders(id);
      } catch (_) {
        syncProblem = 'No connection. Your SOS is still active; its location will update when the network is back.';
      }
    }
    // Once there is a fix, slow down to the normal heartbeat.
    if (!hadFix && lastFix != null) _startHeartbeat();
    _saveLocal();
    notifyListeners();
  }

  // --- resolving ------------------------------------------------------------------

  /// Ends your SOS ("I'm safe"). Kept and retried when offline.
  Future<void> resolve({bool cancelled = false}) async {
    if (phase == SosPhase.idle) return;
    _cancelled = cancelled;
    final wasSending = phase == SosPhase.sending;
    phase = SosPhase.resolving;
    _heartbeat?.cancel();
    _retry?.cancel();
    _saveLocal();
    notifyListeners();
    final id = mine?.id;
    if (id == null) {
      // On its way: _send closes it the moment it arrives.
      if (wasSending && _sendInFlight) return;
      // Not known here, but a send may have reached the server with its reply
      // lost: close whatever is active there.
      final b = _backend;
      if (b != null && b.userId != null) {
        try {
          final server = await b.myActive();
          if (server != null) await b.close(server.id, cancelled: cancelled);
        } catch (_) {
          syncProblem = 'No connection. Your SOS will be closed as soon as there is a network.';
          _scheduleRetry(() => resolve(cancelled: cancelled));
          notifyListeners();
          return;
        }
      }
      _finish();
      return;
    }
    try {
      await _backend!.close(id, cancelled: cancelled);
      _finish();
    } catch (_) {
      syncProblem = 'No connection. Your SOS will be closed as soon as there is a network.';
      _scheduleRetry(() => resolve(cancelled: cancelled));
      notifyListeners();
    }
  }

  void _finish() {
    phase = SosPhase.idle;
    mine = null;
    startedAt = null;
    syncProblem = null;
    responders = 0;
    _retries = 0;
    _heartbeat?.cancel();
    _retry?.cancel();
    _saveLocal();
    unawaited(_native.setActive(false));
    notifyListeners();
  }

  void _scheduleRetry(Future<void> Function() action) {
    _retry?.cancel();
    final ms = math.min(timings.retryMax.inMilliseconds, timings.retryBase.inMilliseconds * (1 << math.min(_retries, 5)));
    _retries++;
    _retry = Timer(Duration(milliseconds: ms), () => unawaited(action()));
  }

  // --- nearby ---------------------------------------------------------------------

  /// Keeps presence current and listens for SOS events nearby.
  Future<void> startWatching() async {
    final b = _backend;
    if (watching || b == null || b.userId == null) return;
    watching = true;
    await _updatePresence(force: true);
    _sub = b.listen(
      onEvent: _onEvent,
      onResponse: (sosId) {
        if (sosId == mine?.id) unawaited(_refreshResponders());
      },
      onHealth: (ok) {
        live = ok;
        notifyListeners();
      },
    );
    await refreshNearby();
    _poll = Timer.periodic(timings.poll, (_) async {
      await _updatePresence();
      await refreshNearby();
    });
  }

  Future<void> stopWatching() async {
    watching = false;
    _poll?.cancel();
    await _sub?.close();
    _sub = null;
    live = false;
    _nearby.clear();
  }

  Future<void> refreshNearby() async {
    final b = _backend;
    if (b == null || b.userId == null) return;
    try {
      final list = await b.nearby();
      final seen = <String>{};
      for (final e in list) {
        seen.add(e.id);
        _onEvent(e, notify: false);
      }
      // Gone from the query: out of range, closed or stale.
      for (final id in [..._nearby.keys]) {
        if (!seen.contains(id)) {
          _nearby.remove(id);
          unawaited(_native.clearNearby(id));
        }
      }
      lastChecked = _now();
      nearbyProblem = _presenceAt == null ? _presenceHint() : null;
    } catch (_) {
      nearbyProblem = 'Offline: alerts from people nearby resume when the network is back.';
    }
    notifyListeners();
  }

  void _onEvent(SosEvent e, {bool notify = true}) {
    if (e.userId == _backend?.userId) {
      // Your own, closed from another session.
      if (e.id == mine?.id && !e.isActive && phase != SosPhase.idle) _finish();
      return;
    }
    if (e.isActive && !e.isStale(_now())) {
      _nearby[e.id] = e;
      if (_announced.add(e.id)) {
        _alerts.add(e);
        final away = distanceKm(e);
        unawaited(
          _native.notifyNearby(
            id: e.id,
            title: '${e.name} needs help nearby',
            body: '${e.category.label}${away == null ? '' : ' · ${_distanceLabel(away)} away'}. Open UrbanPulse to see where.',
          ),
        );
      }
    } else {
      _nearby.remove(e.id);
      unawaited(_native.clearNearby(e.id));
    }
    if (notify) notifyListeners();
  }

  Future<void> _updatePresence({bool force = false}) async {
    final b = _backend;
    if (b == null || b.userId == null) return;
    final (fix, issue) = await _locator.locate(precise: false);
    if (fix == null) {
      if (_presenceAt == null) nearbyProblem = issue == LocationIssue.denied ? 'Allow location to receive SOS alerts from people near you.' : _presenceHint();
      return;
    }
    final moved = _presenceAt == null || _presenceAt!.kmTo(fix.lat, fix.lng) >= 0.3;
    final old = _presenceTime == null || _now().difference(_presenceTime!) >= timings.presenceMaxAge;
    if (!force && !moved && !old) return;
    try {
      await b.presence(fix, radiusKm);
      _presenceAt = fix;
      _presenceTime = _now();
    } catch (_) {
      nearbyProblem = 'Offline: alerts from people nearby resume when the network is back.';
    }
  }

  String _presenceHint() => 'Waiting for your location to show SOS alerts near you.';

  Future<void> _refreshResponders() async {
    final id = mine?.id;
    final b = _backend;
    if (id == null || b == null) return;
    try {
      responders = await b.responders(id);
      unawaited(_native.setActive(true, detail: _activeDetail()));
      notifyListeners();
    } catch (_) {}
  }

  /// "I'm on my way" to someone's SOS.
  Future<bool> respond(SosEvent e) async {
    final b = _backend;
    if (b == null) return false;
    try {
      await b.respond(e.id, _firstName());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> setRadius(double km) async {
    await _prefs.setDouble(_keyRadius, km.clamp(0.5, 50));
    await _updatePresence(force: true);
    await refreshNearby();
  }

  // --- power button -------------------------------------------------------------

  Future<void> setTriggerEnabled(bool on) async {
    await _prefs.setBool(_keyTrigger, on);
    if (on) {
      await _locator.askPermission();
      await _native.requestNotifications();
      await _startTrigger();
    } else {
      await _native.stopTrigger();
      triggerRunning = false;
    }
    await refreshNativeStatus();
    notifyListeners();
  }

  Future<void> _startTrigger() async {
    if (!_native.supported) return;
    triggerRunning = await _native.startTrigger();
    notifyListeners();
  }

  Future<void> refreshNativeStatus() async {
    nativeStatus = await _native.status();
    triggerRunning = nativeStatus['running'] ?? triggerRunning;
  }

  Future<bool> askLocation() async {
    final ok = await _locator.askPermission();
    if (ok) {
      final (fix, issue) = await _locator.locate(precise: false);
      locationIssue = issue;
      if (fix != null) lastFix = fix;
      await _updatePresence(force: true);
      await refreshNearby();
    }
    notifyListeners();
    return ok;
  }

  Future<void> openBatterySettings() => _native.openBatterySettings();

  Future<void> requestNotifications() async {
    await _native.requestNotifications();
    await refreshNativeStatus();
    notifyListeners();
  }

  // --- local record ---------------------------------------------------------------

  void _saveLocal() {
    if (phase == SosPhase.idle) {
      unawaited(_prefs.remove(_keyLocal));
      return;
    }
    unawaited(
      _prefs.setString(
        _keyLocal,
        jsonEncode({
          'phase': phase.name,
          'id': mine?.id,
          'category': category.name,
          'source': _source.wire,
          'startedAt': startedAt?.toIso8601String(),
          'fix': lastFix?.toJson(),
          'cancelled': _cancelled,
        }),
      ),
    );
  }

  void _loadLocal() {
    final raw = _prefs.getString(_keyLocal);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      phase = SosPhase.values.firstWhere((p) => p.name == j['phase'], orElse: () => SosPhase.idle);
      category = SosCategory.parse(j['category']);
      _source = SosSource.values.firstWhere((s) => s.wire == j['source'], orElse: () => SosSource.app);
      startedAt = DateTime.tryParse('${j['startedAt']}');
      lastFix = SosPoint.fromJson(j['fix']);
      _cancelled = j['cancelled'] == true;
      final id = j['id'];
      if (id is String) {
        mine = SosEvent(
          id: id,
          userId: _backend?.userId ?? '',
          name: _firstName(),
          category: category,
          status: SosStatus.active,
          createdAt: startedAt ?? _now(),
          updatedAt: _now(),
          lat: lastFix?.lat,
          lng: lastFix?.lng,
        );
      }
      if (phase == SosPhase.active) {
        _startHeartbeat();
        unawaited(_native.setActive(true, detail: _activeDetail()));
      }
    } catch (_) {
      unawaited(_prefs.remove(_keyLocal));
    }
  }

  // --- words ----------------------------------------------------------------------

  String _firstName() {
    final n = _myName().trim().split(RegExp(r'\s+')).first;
    if (n.isEmpty) return 'Someone';
    return n.length > 40 ? n.substring(0, 40) : n;
  }

  String _activeDetail() {
    final who = responders == 0 ? 'Nearby UrbanPulse users can see it.' : '$responders ${responders == 1 ? 'person is' : 'people are'} on the way.';
    return 'SOS active. $who Tap "I\'m safe" when you are.';
  }

  static String _distanceLabel(double km) => km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

  static String distanceLabel(double km) => _distanceLabel(km);

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    _retry?.cancel();
    _poll?.cancel();
    unawaited(_sub?.close());
    unawaited(_alerts.close());
    unawaited(_openRequests.close());
    super.dispose();
  }
}
