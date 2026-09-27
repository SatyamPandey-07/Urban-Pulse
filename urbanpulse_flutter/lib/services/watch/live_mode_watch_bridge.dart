/// Turns Live Mode into the two messages the watch understands.
///
/// [LiveModeController] is the authority on what is happening on the trip: it
/// holds the current day, the next slot, the metres to it, and the log of
/// [LiveUpdate]s it has spoken. This bridge listens to it and:
///
/// * publishes a `state` on every change — the next stop's title, its start time
///   and the distance when the phone actually knows one (the mirror drops
///   anything that changed nothing);
/// * publishes an `alert` for each newly spoken [LiveUpdate], mapping
///   [UpdateKind] onto the five wire kinds the watch renders.
///
/// It never invents an update. `UpdateKind.briefing`, `upcoming`, `dayDone` and
/// `info` have no wire kind of their own and are deliberately not buzzed: a watch
/// alert costs the traveller attention, and those are screen-only lines.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../agents/live/live_mode_engine.dart';
import '../../state/live_mode_controller.dart';
import 'watch_mirror.dart';
import 'watch_plan_builder.dart';
import 'watch_protocol.dart';

class LiveModeWatchBridge {
  LiveModeWatchBridge({
    required this.controller,
    required this.mirror,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    controller.addListener(_onChange);
  }

  final LiveModeController controller;
  final WatchMirror mirror;
  final DateTime Function() _now;

  /// Ids already forwarded, so a controller notification that changed something
  /// else does not re-buzz the whole log.
  final Set<String> _sentUpdateIds = {};

  bool _wasActive = false;

  /// Which day's plan has been sent, so it goes once per day rather than per
  /// tick. The mirror also de-duplicates, but not building the steps at all is
  /// cheaper than building them to throw away.
  int? _planSentForDay;

  /// Which [UpdateKind]s the watch has a buzz for.
  ///
  /// Anything absent here is shown on the phone only. `late` is the wire value
  /// for [WatchAlertKind.runningBehind].
  static const Map<UpdateKind, WatchAlertKind> _kinds = {
    UpdateKind.leaveNow: WatchAlertKind.leave,
    UpdateKind.arrived: WatchAlertKind.arrived,
    UpdateKind.late: WatchAlertKind.runningBehind,
    UpdateKind.meal: WatchAlertKind.meal,
  };

  void _onChange() => unawaited(sync());

  /// Pushes the state, and any alert not yet forwarded.
  @visibleForTesting
  Future<void> sync() async {
    if (!controller.active) {
      if (_wasActive) {
        // Live Mode stopped: say so once, so the watch stops showing a stop it is
        // no longer heading to.
        _wasActive = false;
        _sentUpdateIds.clear();
        _planSentForDay = null;
        await mirror.pushState(WatchStateMessage(live: false, ts: _now()));
      }
      return;
    }
    _wasActive = true;

    final slot = controller.nextSlot;
    final day = controller.day;
    final metres = controller.metresToNext;

    // The whole trip from today on, so the watch can be scrolled through it.
    //
    // Built from the controller's own itinerary rather than just the day Live
    // Mode is running: sending one day here would replace the multi-day plan the
    // phone published on connect, and the traveller would lose tomorrow the
    // moment they switched Live Mode on.
    final trip = controller.itinerary;
    if (day != null && trip != null && _planSentForDay != day.number) {
      _planSentForDay = day.number;
      final snapshot = buildWatchSnapshot([trip], _now());
      if (snapshot != null) {
        await mirror.pushPlan(snapshot.steps, day: snapshot.day);
      }
    }

    await mirror.pushState(WatchStateMessage(
      live: true,
      day: day == null ? null : 'Day ${day.number}',
      next: slot == null
          ? null
          : WatchNextStop(
              title: slot.title,
              at: watchClock(slot.start),
              // Absent rather than guessed when there is no position.
              distanceM: metres?.round(),
            ),
      ts: _now(),
    ));

    // The log is oldest first; forward in that order so the newest buzz is last.
    for (final update in controller.log) {
      if (_sentUpdateIds.contains(update.id)) continue;
      _sentUpdateIds.add(update.id);
      final kind = _kinds[update.kind];
      if (kind == null) continue;
      await mirror.pushAlert(WatchAlertMessage(
        id: update.id,
        kind: kind,
        text: update.text,
        ts: update.at,
      ));
    }
  }

  void dispose() => controller.removeListener(_onChange);
}
