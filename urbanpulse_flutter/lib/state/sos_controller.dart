/// The one place an SOS happens, whether it was started on the phone or on the
/// watch.
///
/// The sequence is fixed, and every step reports what actually happened:
///
/// 1. **armed** -> a 10 second cancel window. The watch is told the seconds
///    remaining once a second; either side can cancel.
/// 2. **locating** -> one fresh GPS fix. If there is none, the last known fix is
///    used *and said to be old*; with neither, the message says the position is
///    unknown rather than inventing one.
/// 3. **sending** -> one message per contact, with a maps link.
/// 4. **sent / prepared / failed** -> pushed to the watch as a `sosAck` with the
///    true outcome. `sent` only ever means the OS accepted the message.
///
/// With no contacts stored the controller refuses at step 1 and says so: there
/// is nobody to tell, and a countdown that ends in nothing would be a lie.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/emergency/emergency_contacts.dart';
import '../services/emergency/emergency_sms.dart';
import '../services/live_location.dart';
import '../services/watch/watch_protocol.dart';

/// How far the controller has got.
enum SosPhase {
  idle,

  /// Counting down, cancellable.
  armed,
  locating,
  sending,

  /// The OS accepted the message.
  sent,

  /// A composer was opened; the traveller must tap send.
  prepared,
  cancelled,
  failed,
}

/// Where the SOS was raised, so the UI can say "from your watch".
enum SosOrigin { phone, watch }

/// Everything the SOS screen and the watch need to render. Immutable, so a
/// listener can tell one update from the next.
@immutable
class SosState {
  const SosState({
    this.phase = SosPhase.idle,
    this.origin = SosOrigin.phone,
    this.secondsLeft = 0,
    this.detail,
    this.positionAgeS,
    this.mapsUrl,
    this.reached = const [],
  });

  final SosPhase phase;
  final SosOrigin origin;

  /// Seconds left in the cancel window, 0 outside [SosPhase.armed].
  final int secondsLeft;

  /// A sentence for the traveller: why it failed, or who it reached.
  final String? detail;

  /// How old the position in the message is, when it was not fresh.
  final int? positionAgeS;

  /// The link that went into the message, for the in-app screen to show.
  final String? mapsUrl;

  /// Numbers the OS accepted a message for.
  final List<String> reached;

  bool get isActive =>
      phase == SosPhase.armed || phase == SosPhase.locating || phase == SosPhase.sending;

  bool get isFinished =>
      phase == SosPhase.sent ||
      phase == SosPhase.prepared ||
      phase == SosPhase.failed ||
      phase == SosPhase.cancelled;

  SosState copyWith({
    SosPhase? phase,
    SosOrigin? origin,
    int? secondsLeft,
    String? detail,
    int? positionAgeS,
    String? mapsUrl,
    List<String>? reached,
  }) => SosState(
    phase: phase ?? this.phase,
    origin: origin ?? this.origin,
    secondsLeft: secondsLeft ?? this.secondsLeft,
    detail: detail ?? this.detail,
    positionAgeS: positionAgeS ?? this.positionAgeS,
    mapsUrl: mapsUrl ?? this.mapsUrl,
    reached: reached ?? this.reached,
  );
}

/// Pushes `sosAck` to the watch. Kept as a function so the controller does not
/// depend on the mirror, and tests can record the acks directly.
typedef SosAckSink = Future<void> Function(SosAckMessage ack);

class SosController extends ChangeNotifier {
  SosController({
    required this.contacts,
    required this.sms,
    required this.location,
    SosAckSink? ackSink,
    Duration cancelWindow = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : _ack = ackSink ?? _noAck,
       _cancelWindow = cancelWindow,
       _now = now ?? DateTime.now;

  static Future<void> _noAck(SosAckMessage _) async {}

  final EmergencyContactsRepository contacts;
  final EmergencySms sms;
  final LiveLocation location;
  final Duration _cancelWindow;
  final DateTime Function() _now;

  SosAckSink _ack;

  /// Replaces the ack sink once the watch mirror exists (the composition root
  /// builds the controller first).
  set ackSink(SosAckSink sink) => _ack = sink;

  /// Raised when an SOS starts, so the app can show the emergency screen and
  /// sound the alarm. Set by whatever owns the UI.
  void Function(SosOrigin origin)? onRaised;

  /// Called when the sequence ends, so the alarm can be silenced.
  void Function(SosState state)? onFinished;

  SosState _state = const SosState();
  SosState get state => _state;

  Timer? _countdown;

  /// The fix the location service last gave us, with when it gave it.
  UserFix? _lastFix;
  DateTime? _lastFixAt;

  /// Records a position seen elsewhere in the app, so an SOS with no signal has
  /// something honest to fall back on.
  void noteFix(UserFix fix) {
    _lastFix = fix;
    _lastFixAt = _now();
  }

  /// Starts the cancel window. Does nothing if one is already running.
  ///
  /// Returns false, with [SosPhase.failed] and a reason, when there is nobody to
  /// send to.
  Future<bool> trigger({SosOrigin origin = SosOrigin.phone}) async {
    if (_state.isActive) return true;
    if (contacts.isEmpty) {
      _set(const SosState(
        phase: SosPhase.failed,
        detail: 'No emergency contacts yet - add one in Settings first',
      ));
      await _push(const SosAckMessage(
        status: SosAckStatus.failed,
        detail: 'No emergency contacts on the phone',
      ));
      onFinished?.call(_state);
      return false;
    }

    final total = _cancelWindow.inSeconds;
    _set(SosState(phase: SosPhase.armed, origin: origin, secondsLeft: total));
    onRaised?.call(origin);
    await _push(SosAckMessage(status: SosAckStatus.countdown, secondsLeft: total));

    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = _state.secondsLeft - 1;
      if (_state.phase != SosPhase.armed) {
        timer.cancel();
        return;
      }
      if (left <= 0) {
        timer.cancel();
        unawaited(_dispatch());
        return;
      }
      _set(_state.copyWith(secondsLeft: left));
      unawaited(_push(SosAckMessage(status: SosAckStatus.countdown, secondsLeft: left)));
    });
    return true;
  }

  /// Stops the countdown. Only possible while [SosPhase.armed]: once the message
  /// is on its way there is nothing left to cancel, and saying otherwise would
  /// be the same lie in the other direction.
  Future<bool> cancel() async {
    if (_state.phase != SosPhase.armed) return false;
    _countdown?.cancel();
    _countdown = null;
    _set(_state.copyWith(phase: SosPhase.cancelled, secondsLeft: 0, detail: 'Cancelled'));
    await _push(const SosAckMessage(status: SosAckStatus.cancelled));
    onFinished?.call(_state);
    return true;
  }

  Future<void> _dispatch() async {
    _set(_state.copyWith(phase: SosPhase.locating, secondsLeft: 0));

    // One fresh fix, then the last one we saw, then neither.
    String where;
    String? mapsUrl;
    int? ageS;
    final result = await location.request();
    final fresh = result.status == LocationStatus.ok ? result.fix : null;
    if (fresh != null) {
      noteFix(fresh);
      mapsUrl = _mapsUrl(fresh);
      where = 'My location: $mapsUrl';
    } else if (_lastFix != null && _lastFixAt != null) {
      ageS = _now().difference(_lastFixAt!).inSeconds;
      mapsUrl = _mapsUrl(_lastFix!);
      where = 'Last known location (${_ageText(ageS)} old): $mapsUrl';
    } else {
      where = 'Location unknown - GPS unavailable.';
    }

    _set(_state.copyWith(phase: SosPhase.sending, mapsUrl: mapsUrl, positionAgeS: ageS));

    final body = buildSosMessage(where: where, at: _now(), origin: _state.origin);
    final outcome = await sms.send(to: contacts.contacts, body: body);

    switch (outcome.outcome) {
      case SmsOutcome.sent:
        _set(_state.copyWith(
          phase: SosPhase.sent,
          detail: outcome.detail,
          reached: outcome.reached,
        ));
        await _push(SosAckMessage(status: SosAckStatus.sent, detail: outcome.detail));
      case SmsOutcome.prepared:
        _set(_state.copyWith(phase: SosPhase.prepared, detail: outcome.detail));
        await _push(SosAckMessage(
          status: SosAckStatus.prepared,
          detail: outcome.detail ?? 'Tap send on the phone',
        ));
      case SmsOutcome.failed:
        _set(_state.copyWith(phase: SosPhase.failed, detail: outcome.detail));
        await _push(SosAckMessage(
          status: SosAckStatus.failed,
          detail: outcome.detail ?? 'Could not send',
        ));
    }
    onFinished?.call(_state);
  }

  /// Clears a finished SOS so the screen goes back to its resting state.
  void acknowledge() {
    if (_state.isActive) return;
    _set(const SosState());
  }

  static String _mapsUrl(UserFix fix) {
    final lat = fix.point.latitude.toStringAsFixed(5);
    final lng = fix.point.longitude.toStringAsFixed(5);
    return 'https://maps.google.com/?q=$lat,$lng';
  }

  static String _ageText(int seconds) {
    if (seconds < 90) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}min';
    return '${minutes ~/ 60}h ${minutes % 60}min';
  }

  Future<void> _push(SosAckMessage ack) async {
    try {
      await _ack(ack);
    } catch (_) {
      // The watch being unreachable must not stop the message to the contacts.
    }
  }

  void _set(SosState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }
}

/// The text the contacts receive. Plain ASCII-ish, short enough for one or two
/// SMS segments, and it never claims more than it knows.
String buildSosMessage({
  required String where,
  required DateTime at,
  SosOrigin origin = SosOrigin.phone,
}) {
  final clock = watchClock(at);
  final from = origin == SosOrigin.watch ? ' (raised from my Garmin watch)' : '';
  return 'SOS from UrbanPulse$from. I need help. Sent $clock. $where';
}
