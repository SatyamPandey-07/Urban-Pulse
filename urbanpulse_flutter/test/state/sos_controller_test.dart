import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbanpulse/services/sos/sos_backend.dart';
import 'package:urbanpulse/services/sos/sos_locator.dart';
import 'package:urbanpulse/services/sos/sos_models.dart';
import 'package:urbanpulse/services/sos/sos_native.dart';
import 'package:urbanpulse/state/sos_controller.dart';

class _Offline implements Exception {}

class FakeBackend implements SosBackend {
  FakeBackend({this.me = 'me'});

  String? me;
  bool offline = false;
  final events = <String, SosEvent>{};
  final presences = <SosPoint>[];
  final moves = <SosPoint?>[];
  final responses = <String>[];
  int raises = 0;
  void Function(SosEvent)? onEvent;

  @override
  String? get userId => me;

  void _net() {
    if (offline) throw _Offline();
  }

  @override
  Future<SosEvent> raise({required String name, required SosCategory category, required SosSource source, SosPoint? at}) async {
    _net();
    final active = events.values.where((e) => e.userId == me && e.isActive).firstOrNull;
    if (active != null) return active;
    raises++;
    final now = DateTime.now();
    final e = SosEvent(
      id: 'sos$raises',
      userId: me!,
      name: name,
      category: category,
      status: SosStatus.active,
      createdAt: now,
      updatedAt: now,
      lat: at?.lat,
      lng: at?.lng,
      source: source.wire,
    );
    events[e.id] = e;
    return e;
  }

  @override
  Future<SosEvent?> myActive() async {
    _net();
    return events.values.where((e) => e.userId == me && e.isActive).firstOrNull;
  }

  @override
  Future<void> move(String id, SosPoint? at) async {
    _net();
    moves.add(at);
  }

  @override
  Future<void> close(String id, {bool cancelled = false}) async {
    _net();
    final e = events[id]!;
    events[id] = SosEvent(
      id: e.id,
      userId: e.userId,
      name: e.name,
      category: e.category,
      status: cancelled ? SosStatus.cancelled : SosStatus.resolved,
      createdAt: e.createdAt,
      updatedAt: DateTime.now(),
      resolvedAt: DateTime.now(),
      lat: e.lat,
      lng: e.lng,
    );
  }

  @override
  Future<void> presence(SosPoint at, double radiusKm) async {
    _net();
    presences.add(at);
  }

  @override
  Future<List<SosEvent>> nearby() async {
    _net();
    return [for (final e in events.values) if (e.userId != me) e];
  }

  @override
  Future<int> responders(String id) async => responses.length;

  @override
  Future<void> respond(String id, String name) async {
    _net();
    responses.add(name);
  }

  @override
  SosSubscription listen({required void Function(SosEvent e) onEvent, required void Function(String sosId) onResponse, required void Function(bool ok) onHealth}) {
    this.onEvent = onEvent;
    onHealth(true);
    return _NoSub();
  }
}

class _NoSub implements SosSubscription {
  @override
  Future<void> close() async {}
}

class FakeLocator implements SosLocator {
  SosPoint? fix = const SosPoint(18.9905, 73.1282, accuracyM: 12);
  LocationIssue issue = LocationIssue.none;

  @override
  Future<(SosPoint?, LocationIssue)> locate({bool precise = true}) async => (fix, issue);

  @override
  Future<bool> askPermission() async => true;
}

class FakeNative extends SosNative {
  String? pending;
  final active = <bool>[];
  final nearbyShown = <String>[];

  @override
  bool get supported => false;

  @override
  Future<String?> ready(Future<void> Function(String method, Map<String, dynamic> args) handler) async => pending;

  @override
  Future<void> setActive(bool a, {String? detail}) async => active.add(a);

  @override
  Future<void> notifyNearby({required String id, required String title, required String body}) async => nearbyShown.add(id);
}

const _fast = SosTimings(
  heartbeat: Duration(hours: 1),
  noFixRetry: Duration(hours: 1),
  poll: Duration(hours: 1),
  retryBase: Duration(milliseconds: 10),
  retryMax: Duration(milliseconds: 40),
);

SosEvent _other(String id, {SosStatus status = SosStatus.active, Duration age = Duration.zero}) {
  final t = DateTime.now().subtract(age);
  return SosEvent(id: id, userId: 'them', name: 'Asha', category: SosCategory.medical, status: status, createdAt: t, updatedAt: t, lat: 18.999, lng: 73.128);
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  late SharedPreferences prefs;
  late FakeBackend backend;
  late FakeLocator locator;
  late FakeNative native;

  SosController make() => SosController(prefs: prefs, myName: () => 'Priya Sharma', backend: backend, locator: locator, native: native, timings: _fast);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    backend = FakeBackend();
    locator = FakeLocator();
    native = FakeNative();
  });

  test('a trigger raises one SOS with the location and a first name; repeats do not raise another', () async {
    final c = make();
    await c.init();
    await c.trigger(source: SosSource.powerButton, category: SosCategory.safety);
    expect(c.phase, SosPhase.active);
    expect(backend.raises, 1);
    final e = backend.events.values.single;
    expect(e.name, 'Priya');
    expect(e.lat, 18.9905);
    expect(e.category, SosCategory.safety);
    expect(e.source, 'power_button');
    expect(native.active.last, isTrue);
    await c.trigger(source: SosSource.powerButton);
    await c.trigger();
    expect(backend.raises, 1);
    c.dispose();
  });

  test('offline: the SOS is kept and sent when the network is back', () async {
    backend.offline = true;
    final c = make();
    await c.init();
    await c.trigger();
    expect(c.phase, SosPhase.sending);
    expect(c.syncProblem, contains('No connection'));
    expect(prefs.getString('sos.local.v1'), isNotNull);
    backend.offline = false;
    await _settle();
    expect(c.phase, SosPhase.active);
    expect(backend.raises, 1);
    c.dispose();
  });

  test('without a location the SOS is still raised, and says so', () async {
    locator
      ..fix = null
      ..issue = LocationIssue.denied;
    final c = make();
    await c.init();
    await c.trigger();
    expect(c.phase, SosPhase.active);
    expect(backend.events.values.single.hasLocation, isFalse);
    expect(c.locationIssue, LocationIssue.denied);
    c.dispose();
  });

  test('resolving closes it on the server, clears the phone and the notification', () async {
    final c = make();
    await c.init();
    await c.trigger();
    await c.resolve();
    expect(c.phase, SosPhase.idle);
    expect(backend.events.values.single.status, SosStatus.resolved);
    expect(prefs.getString('sos.local.v1'), isNull);
    expect(native.active.last, isFalse);
    c.dispose();
  });

  test('resolving offline is retried until it reaches the server', () async {
    final c = make();
    await c.init();
    await c.trigger();
    backend.offline = true;
    await c.resolve();
    expect(c.phase, SosPhase.resolving);
    backend.offline = false;
    await _settle();
    expect(c.phase, SosPhase.idle);
    expect(backend.events.values.single.status, SosStatus.resolved);
    c.dispose();
  });

  test('an SOS survives a restart: raised offline, sent after the app restarts', () async {
    backend.offline = true;
    final first = make();
    await first.init();
    await first.trigger();
    first.dispose();
    backend.offline = false;
    final second = make();
    await second.init();
    expect(second.phase, SosPhase.sending);
    await second.onSignedIn();
    await _settle();
    expect(second.phase, SosPhase.active);
    expect(backend.raises, 1);
    second.dispose();
  });

  test('a power-button press before the app started is not lost', () async {
    native.pending = 'power_button';
    final c = make();
    await c.init();
    await _settle();
    expect(c.phase, SosPhase.active);
    expect(backend.events.values.single.source, 'power_button');
    c.dispose();
  });

  test('nearby: an SOS arrives once, is announced once, and disappears when resolved', () async {
    final c = make();
    await c.init();
    await c.onSignedIn();
    await _settle();
    expect(backend.presences, isNotEmpty);
    final alerts = <SosEvent>[];
    final sub = c.newAlerts.listen(alerts.add);
    backend.onEvent!(_other('x1'));
    backend.onEvent!(_other('x1'));
    await _settle();
    expect(c.nearby.map((e) => e.id), ['x1']);
    expect(alerts, hasLength(1));
    expect(native.nearbyShown, ['x1']);
    expect(c.distanceKm(c.nearby.single), closeTo(0.94, 0.05));
    backend.onEvent!(_other('x1', status: SosStatus.resolved));
    expect(c.nearby, isEmpty);
    // stale: no heartbeat for over two hours
    backend.onEvent!(_other('x2', age: const Duration(hours: 3)));
    expect(c.nearby, isEmpty);
    await sub.cancel();
    c.dispose();
  });

  test('your own SOS closed from another session ends here too', () async {
    final c = make();
    await c.init();
    await c.onSignedIn();
    await c.trigger();
    final id = c.mine!.id;
    await backend.close(id);
    backend.onEvent!(backend.events[id]!);
    expect(c.phase, SosPhase.idle);
    c.dispose();
  });

  test('signed out: the SOS waits and tells the traveller to call 112', () async {
    backend.me = null;
    final c = make();
    await c.init();
    await c.trigger();
    expect(c.phase, SosPhase.sending);
    expect(c.syncProblem, contains('112'));
    expect(backend.raises, 0);
    c.dispose();
  });
}
