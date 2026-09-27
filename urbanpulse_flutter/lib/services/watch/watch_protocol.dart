/// The wire format between the phone and the Connect IQ watch app.
///
/// Connect IQ's [Communications.transmit] carries a dictionary, not a string,
/// so every message here is a `Map<String, Object?>` with short ASCII keys. The
/// constraints are the watch's, not ours:
///
/// * one protocol version (`v`), and anything that is not [protocolVersion] is
///   ignored rather than guessed at, in both directions;
/// * ASCII only — the watch has one bitmap font and renders nothing else;
/// * [maxLineChars] per line of text, because that is what fits on a 454 px
///   round screen at the size the alert view uses;
/// * [maxMessageBytes] per message, well under the ~1 kB a single Connect IQ
///   transmit reliably carries.
///
/// The phone sanitises; the watch truncates again on receipt. Neither trusts the
/// other to have done it.
library;

import 'dart:convert';

/// The only version either side speaks.
const int protocolVersion = 1;

/// Longest line of text the watch will lay out without clipping.
const int maxLineChars = 60;

/// Hard ceiling for one encoded message.
const int maxMessageBytes = 900;

// ---------------------------------------------------------------------------
// text

/// Reduces [input] to something the watch can actually draw: ASCII, single
/// spaces, no control characters, at most [max] characters.
///
/// Truncation prefers a word boundary and marks the cut with `...` so a clipped
/// line reads as clipped rather than as a different message.
String sanitiseWatchText(String input, {int max = maxLineChars}) {
  final ascii = StringBuffer();
  for (final rune in input.runes) {
    // Latin-1 punctuation and accents that show up in place names have ASCII
    // equivalents worth keeping; everything else becomes a space.
    final replacement = _asciiFolding[rune];
    if (replacement != null) {
      ascii.write(replacement);
    } else if (rune >= 0x20 && rune <= 0x7E) {
      ascii.writeCharCode(rune);
    } else {
      ascii.write(' ');
    }
  }
  final collapsed = ascii.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  return _truncate(collapsed, max);
}

String _truncate(String text, int max) {
  if (max <= 0) return '';
  if (text.length <= max) return text;
  if (max <= 3) return text.substring(0, max);
  final hard = text.substring(0, max - 3);
  final lastSpace = hard.lastIndexOf(' ');
  // Only break on a word if that leaves most of the budget used; otherwise a
  // long single word would collapse to "...".
  final body = lastSpace >= (max - 3) ~/ 2 ? hard.substring(0, lastSpace) : hard;
  return '${body.trimRight()}...';
}

const Map<int, String> _asciiFolding = {
  0x00A0: ' ', // nbsp
  0x2018: "'", 0x2019: "'", 0x201A: "'", // single quotes
  0x201C: '"', 0x201D: '"', // double quotes
  0x2013: '-', 0x2014: '-', 0x2212: '-', // dashes
  0x2026: '...', // ellipsis
  0x00B0: ' deg',
  0x20B9: 'Rs ', // rupee — the app is India-first
  0x00E0: 'a', 0x00E1: 'a', 0x00E2: 'a', 0x00E4: 'a', 0x00E5: 'a',
  0x00E8: 'e', 0x00E9: 'e', 0x00EA: 'e', 0x00EB: 'e',
  0x00EC: 'i', 0x00ED: 'i', 0x00EE: 'i', 0x00EF: 'i',
  0x00F2: 'o', 0x00F3: 'o', 0x00F4: 'o', 0x00F6: 'o',
  0x00F9: 'u', 0x00FA: 'u', 0x00FB: 'u', 0x00FC: 'u',
  0x00F1: 'n', 0x00E7: 'c',
};

/// `HH:MM` on a 24-hour clock — the watch prints this verbatim rather than
/// carrying a timezone database to format an epoch.
String watchClock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// Epoch seconds, the one time format the watch parses.
int watchEpoch(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

// ---------------------------------------------------------------------------
// phone -> watch

/// Why the watch is buzzing. Wire values are the lowercase names; `late` is a
/// Dart keyword, so the enum constant is [runningBehind].
enum WatchAlertKind {
  leave('leave'),
  arrived('arrived'),
  runningBehind('late'),
  meal('meal'),
  rain('rain');

  const WatchAlertKind(this.wire);

  final String wire;

  static WatchAlertKind? fromWire(String? wire) {
    for (final kind in values) {
      if (kind.wire == wire) return kind;
    }
    return null;
  }
}

/// How far the phone has got with an SOS. The watch shows exactly this and
/// invents nothing: [sent] means the OS accepted a message, [prepared] means a
/// composer was opened for the traveller to tap send.
enum SosAckStatus { countdown, cancelled, sent, prepared, failed }

/// The next stop on the plan.
class WatchNextStop {
  const WatchNextStop({required this.title, required this.at, this.distanceM});

  /// Where to be next. Sanitised on the way out.
  final String title;

  /// `HH:MM` local wall-clock time.
  final String at;

  /// Metres to it, when the phone actually knows. Omitted rather than guessed.
  final int? distanceM;

  Map<String, Object?> toWire() => {
    'title': sanitiseWatchText(title),
    'at': at,
    if (distanceM != null && distanceM! >= 0) 'dist': distanceM,
  };
}

/// `{t:"state", ...}` — the mirror of what the phone is showing.
class WatchStateMessage {
  const WatchStateMessage({required this.live, required this.ts, this.next, this.day});

  /// Whether Live Mode is running. With `live:false` and no [next] the watch
  /// shows "Waiting for phone".
  final bool live;
  final WatchNextStop? next;

  /// A label such as "Day 2", or null when there is no multi-day plan.
  final String? day;

  /// When the phone built this, so the watch can grey it out once stale.
  final DateTime ts;

  Map<String, Object?> toWire() => {
    't': 'state',
    'v': protocolVersion,
    'live': live,
    if (next != null) 'next': next!.toWire(),
    if (day != null && day!.isNotEmpty) 'day': sanitiseWatchText(day!, max: 16),
    'ts': watchEpoch(ts),
  };
}

/// `{t:"alert", ...}` — buzz the watch and show one line.
class WatchAlertMessage {
  const WatchAlertMessage({required this.id, required this.kind, required this.text, required this.ts});

  /// Stable per alert, so the watch can acknowledge it and drop duplicates.
  final String id;
  final WatchAlertKind kind;
  final String text;
  final DateTime ts;

  Map<String, Object?> toWire() => {
    't': 'alert',
    'v': protocolVersion,
    'id': id,
    'kind': kind.wire,
    'text': sanitiseWatchText(text),
    'ts': watchEpoch(ts),
  };
}

/// `{t:"sosAck", ...}` — the true state of an SOS, pushed as it changes.
class SosAckMessage {
  const SosAckMessage({required this.status, this.detail, this.secondsLeft});

  final SosAckStatus status;

  /// Why, for [SosAckStatus.failed], or which contacts for [SosAckStatus.sent].
  final String? detail;

  /// Only meaningful for [SosAckStatus.countdown].
  final int? secondsLeft;

  Map<String, Object?> toWire() => {
    't': 'sosAck',
    'v': protocolVersion,
    'status': status.name,
    if (detail != null && detail!.isNotEmpty) 'detail': sanitiseWatchText(detail!),
    if (secondsLeft != null) 'secondsLeft': secondsLeft,
  };
}

/// `{t:"ping"}` — a test buzz from the settings screen.
Map<String, Object?> watchPing() => {'t': 'ping', 'v': protocolVersion};

// ---------------------------------------------------------------------------
// watch -> phone

/// Anything the watch can say. Unknown and future messages decode to null, so
/// the phone never acts on something it does not understand.
sealed class WatchInbound {
  const WatchInbound();
}

/// The watch app started and is listening.
class WatchHello extends WatchInbound {
  const WatchHello({required this.device, required this.appVersion});

  final String device;
  final String appVersion;
}

/// The traveller held the SOS button for its full three seconds.
class WatchSosRequest extends WatchInbound {
  const WatchSosRequest({required this.ts});

  final DateTime ts;
}

/// The traveller cancelled during the countdown, from the watch.
class WatchSosCancel extends WatchInbound {
  const WatchSosCancel();
}

/// The watch displayed alert [id].
class WatchAlertAck extends WatchInbound {
  const WatchAlertAck({required this.id});

  final String id;
}

/// Parses one message from the watch.
///
/// Returns null — deliberately, and without throwing — for a message that is
/// not a map, carries no or a different `v`, or has a `t` this version does not
/// know. A newer watch app talking a newer protocol is silence, not a crash.
WatchInbound? decodeWatchMessage(Object? raw) {
  if (raw is! Map) return null;
  final map = raw;
  if (map['v'] != protocolVersion) return null;
  switch (map['t']) {
    case 'hello':
      return WatchHello(
        device: _str(map['device']) ?? 'unknown',
        appVersion: _str(map['appVersion']) ?? '0',
      );
    case 'sos':
      final ts = map['ts'];
      return WatchSosRequest(
        ts: ts is int
            ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
            : DateTime.now(),
      );
    case 'sosCancel':
      return const WatchSosCancel();
    case 'ack':
      final id = _str(map['id']);
      return id == null ? null : WatchAlertAck(id: id);
    default:
      return null;
  }
}

String? _str(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

// ---------------------------------------------------------------------------
// size

/// The encoded size of [message] in bytes, as the channel will carry it.
int watchMessageBytes(Map<String, Object?> message) => utf8.encode(jsonEncode(message)).length;

/// True when [message] is small enough to transmit in one go.
bool fitsOneTransmit(Map<String, Object?> message) => watchMessageBytes(message) <= maxMessageBytes;
