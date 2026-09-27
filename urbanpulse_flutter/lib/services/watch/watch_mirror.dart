/// What the phone chooses to put on the wrist.
///
/// [WatchMirror] sits between the app and a [WatchLink]. It exists so that no
/// caller has to think about the two things a watch is unforgiving about:
///
/// * **buzzing too often.** A vibration the traveller did not ask for is worse
///   than a missed line of text, so alerts are rate limited and de-duplicated
///   here rather than at each call site.
/// * **sending a `state` nothing has changed in.** Each transmit costs radio on
///   both sides, so an unchanged state is dropped unless it has gone quiet long
///   enough that the watch would otherwise grey it out.
library;

import 'dart:async';

import 'watch_link.dart';
import 'watch_protocol.dart';

/// The limits the mirror enforces. Defaults are deliberately conservative; the
/// tests set them shorter.
class WatchMirrorLimits {
  const WatchMirrorLimits({
    this.minAlertGap = const Duration(seconds: 20),
    this.alertWindow = const Duration(minutes: 5),
    this.maxAlertsPerWindow = 5,
    this.duplicateWindow = const Duration(minutes: 2),
    this.stateRefresh = const Duration(minutes: 2),
  });

  /// Never buzz twice inside this.
  final Duration minAlertGap;

  /// At most [maxAlertsPerWindow] alerts in this rolling window.
  final Duration alertWindow;
  final int maxAlertsPerWindow;

  /// The same kind and text inside this is the same alert, not a new one.
  final Duration duplicateWindow;

  /// Resend an unchanged `state` this often, so the watch's freshness dot and
  /// its "stale after 5 minutes" rule stay meaningful.
  final Duration stateRefresh;
}

/// Why an alert was not sent. Returned rather than thrown: dropping an alert is
/// normal operation, and the caller usually only wants to log it.
enum WatchAlertOutcome {
  sent,

  /// Mirroring is switched off in settings.
  mirroringOff,

  /// The watch is not reachable.
  notConnected,

  /// An alert with this id has already gone out.
  duplicateId,

  /// The same kind and text went out inside the duplicate window.
  duplicateText,

  /// Inside the minimum gap, or over the per-window budget.
  rateLimited,

  /// The link refused it. The mirror does not retry or pretend.
  failed,
}

class WatchMirror {
  WatchMirror({
    required this.link,
    WatchMirrorLimits limits = const WatchMirrorLimits(),
    DateTime Function()? now,
  }) : _limits = limits,
       _now = now ?? DateTime.now;

  final WatchLink link;
  final WatchMirrorLimits _limits;
  final DateTime Function() _now;

  /// Settings → "Mirror Live Mode alerts to watch". Off means the mirror sends
  /// neither `state` nor `alert`; the SOS path is governed separately.
  bool mirroring = false;

  final _sentIds = <String>{};
  final _recentText = <String, DateTime>{};
  final _alertTimes = <DateTime>[];
  DateTime? _lastAlertAt;

  Map<String, Object?>? _lastStateWire;
  DateTime? _lastStateAt;

  /// Alert ids the watch has confirmed it displayed.
  final Set<String> acknowledged = {};

  /// Sends [message] as a `state`, unless it is the same as the last one and the
  /// last one is still fresh.
  ///
  /// Returns true when something went out.
  Future<bool> pushState(WatchStateMessage message) async {
    if (!mirroring || !link.currentStatus.isConnected) return false;
    final wire = message.toWire();
    final at = _now();
    // `ts` changes on every tick by design, so compare everything but it.
    final comparable = Map<String, Object?>.from(wire)..remove('ts');
    final unchanged = _lastStateWire != null && _mapEquals(_lastStateWire!, comparable);
    final stale = _lastStateAt == null || at.difference(_lastStateAt!) >= _limits.stateRefresh;
    if (unchanged && !stale) return false;
    try {
      await link.send(wire);
    } catch (_) {
      // Leave `_lastStateWire` alone so the next tick tries again.
      return false;
    }
    _lastStateWire = comparable;
    _lastStateAt = at;
    return true;
  }

  /// Buzzes the watch, if all of the gates above allow it.
  Future<WatchAlertOutcome> pushAlert(WatchAlertMessage message) async {
    if (!mirroring) return WatchAlertOutcome.mirroringOff;
    if (!link.currentStatus.isConnected) return WatchAlertOutcome.notConnected;
    if (_sentIds.contains(message.id)) return WatchAlertOutcome.duplicateId;

    final at = _now();
    final fingerprint = '${message.kind.wire}|${sanitiseWatchText(message.text)}';
    final seenAt = _recentText[fingerprint];
    if (seenAt != null && at.difference(seenAt) < _limits.duplicateWindow) {
      return WatchAlertOutcome.duplicateText;
    }
    if (_lastAlertAt != null && at.difference(_lastAlertAt!) < _limits.minAlertGap) {
      return WatchAlertOutcome.rateLimited;
    }
    _alertTimes.removeWhere((t) => at.difference(t) >= _limits.alertWindow);
    if (_alertTimes.length >= _limits.maxAlertsPerWindow) {
      return WatchAlertOutcome.rateLimited;
    }

    try {
      await link.send(message.toWire());
    } catch (_) {
      return WatchAlertOutcome.failed;
    }
    _sentIds.add(message.id);
    _recentText[fingerprint] = at;
    _alertTimes.add(at);
    _lastAlertAt = at;
    return WatchAlertOutcome.sent;
  }

  /// SOS acknowledgements bypass mirroring and the rate limiter: they are the
  /// answer to something the traveller did, and dropping one would leave the
  /// watch showing a status that is no longer true.
  ///
  /// Returns true when it reached the link.
  Future<bool> pushSosAck(SosAckMessage message) async {
    if (!link.currentStatus.isConnected) return false;
    try {
      await link.send(message.toWire());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A test buzz from settings.
  Future<bool> pushPing() async {
    if (!link.currentStatus.isConnected) return false;
    try {
      await link.send(watchPing());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Records that the watch displayed an alert.
  void onAck(WatchAlertAck ack) => acknowledged.add(ack.id);

  /// Forgets the send history, so a new trip starts with a clean budget.
  void reset() {
    _sentIds.clear();
    _recentText.clear();
    _alertTimes.clear();
    _lastAlertAt = null;
    _lastStateWire = null;
    _lastStateAt = null;
    acknowledged.clear();
  }

  static bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      final other = b[entry.key];
      if (entry.value is Map && other is Map) {
        if (!_mapEquals(
          (entry.value as Map).cast<String, Object?>(),
          other.cast<String, Object?>(),
        )) {
          return false;
        }
      } else if (entry.value != other) {
        return false;
      }
    }
    return true;
  }
}
