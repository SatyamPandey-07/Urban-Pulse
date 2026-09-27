/// The watch feature as the rest of the app sees it: one object that owns the
/// link, the mirror, the two settings toggles, and the routing of everything the
/// watch says.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/sos_controller.dart';
import 'watch_link.dart';
import 'watch_mirror.dart';
import 'watch_protocol.dart';

class WatchService extends ChangeNotifier {
  WatchService({
    required this.link,
    required SharedPreferences prefs,
    SosController? sos,
    WatchMirrorLimits limits = const WatchMirrorLimits(),
    DateTime Function()? now,
  }) : _prefs = prefs,
       _sos = sos,
       _now = now ?? DateTime.now {
    mirror = WatchMirror(link: link, limits: limits, now: _now)
      ..mirroring = mirrorAlerts;
    _status = link.currentStatus;
    _statuses = link.status.listen(_onStatus);
    _inbound = link.messages.listen(_onMessage);
    // The controller may outlive several mirrors; point its acks here.
    _sos?.ackSink = mirror.pushSosAck;
  }

  static const _kMirror = 'watch_mirror_live_alerts_v1';
  static const _kSosFromWatch = 'watch_sos_enabled_v1';

  final WatchLink link;
  final SharedPreferences _prefs;
  final SosController? _sos;
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
    if (!value) mirror.reset();
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

  /// Starts the SDK and probes for the watch.
  Future<void> connect() => link.connect();

  /// Asks Garmin Connect to launch the watch app.
  Future<void> openWatchApp() => link.openWatchApp();

  /// The settings screen's test buzz. Returns whether it reached the link.
  Future<bool> sendTestBuzz() => mirror.pushPing();

  void _onStatus(WatchStatus next) {
    if (next == _status) return;
    _status = next;
    if (!next.isConnected) connectedDevice = null;
    notifyListeners();
  }

  void _onMessage(Map<String, Object?> raw) {
    final message = decodeWatchMessage(raw);
    // Unknown types and other protocol versions decode to null and are dropped.
    if (message == null) return;
    switch (message) {
      case WatchHello(:final device):
        connectedDevice = device;
        notifyListeners();
      case WatchAlertAck():
        mirror.onAck(message);
      case WatchSosRequest():
        unawaited(_onWatchSos());
      case WatchSosCancel():
        unawaited(_onWatchCancel());
    }
  }

  Future<void> _onWatchSos() async {
    final sos = _sos;
    if (sos == null) return;
    if (!sosFromWatch) {
      // Refusing is a real outcome, so the watch is told rather than left waiting
      // on a countdown that will never come. The two reasons are different and
      // the traveller can only act on one of them.
      sosFromWatchRefused = true;
      notifyListeners();
      await mirror.pushSosAck(SosAckMessage(
        status: SosAckStatus.failed,
        detail: sosFromWatchSupported
            ? 'SOS from watch is switched off in the phone settings'
            : 'Watch SOS is not available on iPhone - use the phone',
      ));
      return;
    }
    await sos.trigger(origin: SosOrigin.watch);
  }

  Future<void> _onWatchCancel() async {
    await _sos?.cancel();
  }

  @override
  Future<void> dispose() async {
    await _statuses.cancel();
    await _inbound.cancel();
    await link.dispose();
    super.dispose();
  }
}
