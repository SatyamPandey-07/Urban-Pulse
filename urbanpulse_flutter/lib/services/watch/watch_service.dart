/// The watch feature as the rest of the app sees it: one object that owns the
/// link, the mirror, the two settings toggles, and the routing of everything the
/// watch says.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/emergency_sos_controller.dart';
import 'watch_link.dart';
import 'watch_mirror.dart';
import 'watch_plan_builder.dart';
import 'watch_protocol.dart';

/// The watch asked for an SOS, and what the phone did about it.
///
/// Carried as an event rather than a flag because the traveller pressed a button
/// and is owed an answer on the phone too — especially on iOS, where the honest
/// answer is that the phone cannot send the message on its own.
class WatchSosNotice {
  const WatchSosNotice({required this.started, required this.reason});

  /// Whether the phone actually began an SOS.
  final bool started;

  /// Why it did not, when [started] is false.
  final String reason;
}

class WatchService extends ChangeNotifier {
  WatchService({
    required this.link,
    required SharedPreferences prefs,
    EmergencySosController? sos,
    WatchSnapshot? Function()? snapshot,
    WatchMirrorLimits limits = const WatchMirrorLimits(),
    DateTime Function()? now,
  }) : _prefs = prefs,
       _sos = sos,
       _snapshot = snapshot,
       _now = now ?? DateTime.now {
    mirror = WatchMirror(link: link, limits: limits, now: _now)
      ..mirroring = mirrorAlerts;
    _status = link.currentStatus;
    if (_status.isConnected) {
      // Built against an already-live link: that still counts as having reached
      // a watch, and `_onStatus` will never see a transition to tell us.
      unawaited(_prefs.setBool(_kEverConnected, true));
    }
    _statuses = link.status.listen(_onStatus);
    _inbound = link.messages.listen(_onMessage);
    // The controller may outlive several mirrors; point its acks here.
    _sos?.ackSink = mirror.pushSosAck;
  }

  static const _kMirror = 'watch_mirror_live_alerts_v1';
  static const _kSosFromWatch = 'watch_sos_enabled_v1';

  /// Set once a watch has actually been reached, so later launches know it is
  /// worth starting the SDK without probing on behalf of travellers who have
  /// never paired one.
  static const _kEverConnected = 'watch_ever_connected_v1';

  final WatchLink link;
  final SharedPreferences _prefs;
  final EmergencySosController? _sos;

  /// Today's plan, from the itinerary alone. Supplied by the composition root so
  /// this service does not need to know about repositories.
  final WatchSnapshot? Function()? _snapshot;

  final DateTime Function() _now;

  late final WatchMirror mirror;
  late final StreamSubscription<WatchStatus> _statuses;
  late final StreamSubscription<Map<String, Object?>> _inbound;

  WatchStatus _status = WatchStatus.deviceNotConnected;
  WatchStatus get status => _status;

  /// The watch's own report of itself, once it has said hello.
  String? connectedDevice;

  /// Set when the watch asked for an SOS while the toggle was off, so the
  /// settings row can explain why nothing happened.
  bool sosFromWatchRefused = false;

  final _sosNotices = StreamController<WatchSosNotice>.broadcast();

  /// Every SOS the watch has asked for. Listened to by the app-wide overlay so
  /// the press is acknowledged on the phone wherever the traveller is.
  Stream<WatchSosNotice> get watchSosRequests => _sosNotices.stream;

  /// Settings → "Mirror Live Mode alerts to watch". Defaults on: a traveller who
  /// side-loads the watch app wants what it shows.
  bool get mirrorAlerts => _prefs.getBool(_kMirror) ?? true;

  /// Whether this platform can act on a watch SOS at all. False on iOS.
  bool get sosFromWatchSupported => link.supportsSosFromWatch;

  /// Settings → "SOS from watch". Defaults **off**: a three-second hold is easy
  /// to do by accident on a wrist, and the consequence is a message to five
  /// people.
  ///
  /// Always false where the platform cannot complete one, so a preference saved
  /// on an Android phone does not silently enable a dead button on an iPhone.
  bool get sosFromWatch =>
      sosFromWatchSupported && (_prefs.getBool(_kSosFromWatch) ?? false);

  Future<void> setMirrorAlerts(bool value) async {
    await _prefs.setBool(_kMirror, value);
    mirror.mirroring = value;
    if (!value) {
      mirror.reset();
    } else {
      // Switching mirroring back on should fill the watch straight away.
      unawaited(publishSnapshot());
    }
    notifyListeners();
  }

  /// Returns false, changing nothing, where the platform cannot support it.
  Future<bool> setSosFromWatch(bool value) async {
    if (value && !sosFromWatchSupported) return false;
    await _prefs.setBool(_kSosFromWatch, value);
    if (value) sosFromWatchRefused = false;
    notifyListeners();
    return true;
  }

  /// Whether a watch has been reached at some point in the past.
  bool get everConnected => _prefs.getBool(_kEverConnected) ?? false;

  /// Starts the SDK and probes for the watch.
  ///
  /// Publishes today's plan once the link is up, so the watch has something on it
  /// without the traveller having to start anything.
  Future<void> connect() async {
    await link.connect();
    await publishSnapshot();
  }

  /// Reconnects at app start, but only for a traveller who has paired a watch
  /// before.
  ///
  /// This is what lets the watch's SOS button reach the phone without the
  /// traveller first opening the Garmin screen: nothing inbound arrives until
  /// the link is listening. For everyone else it does nothing at all, so the
  /// Connect IQ SDK is never started on a phone that has no watch.
  Future<void> reconnectIfPaired() async {
    if (!everConnected) return;
    await connect();
  }

  /// Sends today's plan and next stop, from the itinerary alone.
  ///
  /// This is what the watch shows when Live Mode is not running. Live Mode then
  /// overwrites it with the same fields plus a real distance. Safe to call
  /// often: the mirror drops an unchanged state and an unchanged plan.
  Future<void> publishSnapshot() async {
    final build = _snapshot;
    if (build == null || !_status.isConnected || !mirrorAlerts) return;
    final snapshot = build();
    if (snapshot == null) {
      // No trip today. Say so, so the watch stops saying "Waiting for phone" —
      // the phone is here, there is simply nothing planned.
      await mirror.pushState(WatchStateMessage(live: false, ts: _now()));
      return;
    }
    await mirror.pushPlan(snapshot.steps, day: snapshot.day);
    await mirror.pushState(WatchStateMessage(
      live: snapshot.live,
      day: snapshot.day,
      next: snapshot.next,
      ts: _now(),
    ));
  }

  /// Asks Garmin Connect to launch the watch app.
  Future<void> openWatchApp() => link.openWatchApp();

  /// The settings screen's test buzz. Returns whether it reached the link.
  Future<bool> sendTestBuzz() => mirror.pushPing();

  /// Forces today's plan onto the watch and reports what happened, in words the
  /// settings screen can show verbatim.
  ///
  /// The normal path publishes on connect; this exists because "nothing is on my
  /// watch" has several possible causes and the traveller deserves to be told
  /// which one it is rather than left guessing.
  Future<String> resendPlan() async {
    if (!_status.isConnected) return 'Not connected to the watch';
    if (!mirrorAlerts) return 'Mirroring is off - turn it on above';
    final build = _snapshot;
    if (build == null) return 'No itinerary source wired up';

    final snapshot = build();
    if (snapshot == null) {
      await mirror.pushState(WatchStateMessage(live: false, ts: _now()));
      return 'No upcoming trip found, so there is no plan to send';
    }
    // Force it: the mirror skips an unchanged plan, which is right for a tick
    // but wrong for a button the traveller pressed on purpose.
    mirror.reset();
    final sent = await mirror.pushPlan(snapshot.steps, day: snapshot.day);
    await mirror.pushState(WatchStateMessage(
      live: snapshot.live,
      day: snapshot.day,
      next: snapshot.next,
      ts: _now(),
    ));
    if (sent == 0) return 'The watch refused the plan';
    return 'Sent ${snapshot.steps.length} steps'
        '${snapshot.day == null ? '' : ' for ${snapshot.day}'}';
  }

  void _onStatus(WatchStatus next) {
    if (next == _status) return;
    final was = _status;
    _status = next;
    if (!next.isConnected) connectedDevice = null;
    notifyListeners();
    // Becoming reachable is the moment to fill the watch.
    if (next.isConnected && !was.isConnected) {
      unawaited(_prefs.setBool(_kEverConnected, true));
      mirror.reset();
      unawaited(publishSnapshot());
    }
  }

  void _onMessage(Map<String, Object?> raw) {
    final message = decodeWatchMessage(raw);
    // Unknown types and other protocol versions decode to null and are dropped.
    if (message == null) return;
    switch (message) {
      case WatchHello(:final device):
        connectedDevice = device;
        notifyListeners();
        // The watch app just started and has nothing. Give it the day.
        unawaited(publishSnapshot());
      case WatchAlertAck():
        mirror.onAck(message);
      case WatchSosRequest():
        unawaited(_onWatchSos());
      case WatchSosCancel():
        unawaited(_onWatchCancel());
    }
  }

  Future<void> _onWatchSos() async {
    // The refusal below needs no SOS controller, and the traveller held a button
    // for three seconds either way: answering comes before anything else.
    if (!sosFromWatch) {
      // Refusing is a real outcome, so the watch is told rather than left waiting
      // on a countdown that will never come. The two reasons are different and
      // the traveller can only act on one of them.
      sosFromWatchRefused = true;
      notifyListeners();
      final reason = sosFromWatchSupported
          ? 'SOS from watch is switched off in the phone settings'
          : 'iOS does not let an app send a message on its own, so the watch '
                'cannot complete an SOS by itself.';
      await mirror.pushSosAck(SosAckMessage(
        status: SosAckStatus.failed,
        detail: sosFromWatchSupported
            ? 'SOS from watch is switched off in the phone settings'
            : 'Watch SOS is not available on iPhone - use the phone',
      ));
      // Tell the phone too: the traveller held a button for three seconds and
      // deserves to know here as well as on the wrist.
      _sosNotices.add(WatchSosNotice(started: false, reason: reason));
      return;
    }

    final sos = _sos;
    if (sos == null) {
      // Nothing wired to act on it. Say so rather than leave the wrist waiting.
      await mirror.pushSosAck(const SosAckMessage(
        status: SosAckStatus.failed,
        detail: 'The phone could not start an SOS',
      ));
      _sosNotices.add(const WatchSosNotice(
        started: false,
        reason: 'The phone could not start an SOS.',
      ));
      return;
    }
    final started = await sos.trigger(origin: SosOrigin.watch);
    _sosNotices.add(WatchSosNotice(
      started: started,
      reason: started ? '' : 'No emergency contacts are saved, so nothing was sent.',
    ));
  }

  Future<void> _onWatchCancel() async {
    await _sos?.cancel();
  }

  @override
  Future<void> dispose() async {
    await _statuses.cancel();
    await _inbound.cancel();
    await _sosNotices.close();
    await link.dispose();
    super.dispose();
  }
}
