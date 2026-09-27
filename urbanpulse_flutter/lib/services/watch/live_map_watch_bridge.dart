/// Turns Live Map navigation into the two messages the watch understands.
///
/// This is the whole of "Live Mode mirroring" that the app can honestly support
/// today. [LiveMapController] is the only thing in the repo that knows where the
/// traveller is going and when they will get there: while `navigating` it
/// publishes a [NavProgress] on every position fix, with metres and seconds
/// remaining and an `arrived` flag.
///
/// So:
/// * every tick becomes a `state` with the destination, the arrival clock time
///   and the distance left — the mirror drops the ones that changed nothing;
/// * the `arrived` edge becomes an `arrived` alert, once per destination.
///
/// The other alert kinds in the protocol (`leave`, `late`, `meal`, `rain`) have
/// no producer in the app yet. They are carried, sanitised, rate limited and
/// tested end to end, and [pushAlert] is the entry point for whatever comes to
/// emit them; nothing fabricates them here.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../state/live_map_controller.dart';
import 'watch_mirror.dart';
import 'watch_protocol.dart';

class LiveMapWatchBridge {
  LiveMapWatchBridge({
    required this.controller,
    required this.mirror,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    controller.addListener(_onChange);
  }

  final LiveMapController controller;
  final WatchMirror mirror;
  final DateTime Function() _now;

  bool _wasNavigating = false;
  String? _arrivedFor;
  int _alertSeq = 0;

  /// Sends whatever the current controller state implies. Called on every
  /// notification, and directly by the tests.
  void _onChange() {
    unawaited(sync());
  }

  /// Visible for tests: pushes the state (and any alert) for right now.
  @visibleForTesting
  Future<void> sync() async {
    final navigating = controller.navigating;
    final progress = controller.progress;
    final destination = controller.selected;

    if (!navigating || progress == null || destination == null) {
      if (_wasNavigating) {
        // Navigation stopped: say so once, so the watch stops showing a stop it
        // is no longer heading to.
        _wasNavigating = false;
        _arrivedFor = null;
        await mirror.pushState(WatchStateMessage(live: false, ts: _now()));
      }
      return;
    }
    _wasNavigating = true;

    final at = _now();
    if (progress.arrived) {
      await mirror.pushState(WatchStateMessage(
        live: true,
        next: WatchNextStop(title: destination.name, at: watchClock(at), distanceM: 0),
        ts: at,
      ));
      if (_arrivedFor != destination.name) {
        _arrivedFor = destination.name;
        await mirror.pushAlert(WatchAlertMessage(
          id: 'arrived-${destination.name}-${watchEpoch(at)}-${_alertSeq++}',
          kind: WatchAlertKind.arrived,
          text: 'Arrived at ${destination.name}',
          ts: at,
        ));
      }
      return;
    }

    _arrivedFor = null;
    await mirror.pushState(WatchStateMessage(
      live: true,
      next: WatchNextStop(
        title: destination.name,
        at: watchClock(at.add(Duration(seconds: progress.remainingS))),
        distanceM: progress.remainingM.round(),
      ),
      ts: at,
    ));
  }

  void dispose() => controller.removeListener(_onChange);
}
