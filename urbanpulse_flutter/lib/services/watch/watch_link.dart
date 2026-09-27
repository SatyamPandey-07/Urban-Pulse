/// The phone's end of the link to a Garmin watch.
library;

import 'dart:async';

/// Every reason the watch may not be reachable, worst first, plus the one good
/// case. The settings row shows exactly this and never a friendlier guess: a
/// paired watch with the app missing is a different problem from no watch.
enum WatchStatus {
  /// No Connect IQ SDK on this platform build (iOS today — see the README).
  notSupported,

  /// Garmin Connect Mobile is not installed, so nothing can reach the watch.
  garminAppMissing,

  /// Garmin Connect knows of no watch.
  noDevicePaired,

  /// A watch is paired but out of range or its Bluetooth link is down.
  deviceNotConnected,

  /// The watch is connected but the Urban Pulse watch app is not side-loaded.
  watchAppNotInstalled,

  /// Messages will get through.
  connected;

  bool get isConnected => this == WatchStatus.connected;

  /// What the settings row says.
  String get label => switch (this) {
    WatchStatus.notSupported => 'Not supported on this device',
    WatchStatus.garminAppMissing => 'Garmin Connect app missing',
    WatchStatus.noDevicePaired => 'No watch paired',
    WatchStatus.deviceNotConnected => 'Not connected',
    WatchStatus.watchAppNotInstalled => 'Watch app not installed',
    WatchStatus.connected => 'Connected',
  };

  /// Whether offering a "Connect" button would do anything useful.
  bool get canRetry => this != WatchStatus.notSupported;
}

/// A transport to the watch app.
///
/// Implementations are expected to be honest about [status]: it reflects what
/// the Connect IQ SDK reports, and [send] throwing is preferred to pretending a
/// message left the phone.
abstract class WatchLink {
  /// The live connection state. Broadcast, and it replays the current value to
  /// each new listener so a freshly built widget is never blank.
  Stream<WatchStatus> get status;

  /// The most recent value of [status], available synchronously.
  WatchStatus get currentStatus;

  /// Whether this platform can act on an SOS raised from the watch.
  ///
  /// False on iOS, and the reason is a platform limit rather than a missing
  /// feature: no iOS API sends an SMS without the traveller tapping send, so a
  /// wrist SOS could never complete on its own. Offering the button anyway would
  /// promise something the phone cannot deliver, so the settings toggle is hidden
  /// and the watch is told plainly if it asks.
  bool get supportsSosFromWatch;

  /// Everything the watch has said, already decoded from the channel but not
  /// yet parsed — see `decodeWatchMessage`.
  Stream<Map<String, Object?>> get messages;

  /// Starts the SDK, finds the watch and subscribes to its app. Safe to call
  /// again; it re-probes rather than duplicating listeners.
  Future<void> connect();

  /// Transmits one protocol message. Throws if it could not be handed to the
  /// SDK, so callers can report a real failure.
  Future<void> send(Map<String, Object?> message);

  /// Asks Garmin Connect to start the watch app on the watch, which is the only
  /// way to clear [WatchStatus.watchAppNotInstalled] guesswork on some devices.
  Future<void> openWatchApp();

  /// Releases the SDK and closes both streams.
  Future<void> dispose();
}

/// A [WatchLink] driven by the test, not by a watch.
///
/// It records what was sent, lets the test push statuses and inbound messages,
/// and can be told to fail the next [send] so the honest-acknowledgement paths
/// are reachable without a Garmin.
class ScriptedWatchLink implements WatchLink {
  ScriptedWatchLink({WatchStatus initial = WatchStatus.connected}) : _status = initial {
    _statuses.add(initial);
  }

  WatchStatus _status;
  final _statuses = StreamController<WatchStatus>.broadcast();
  final _messages = StreamController<Map<String, Object?>>.broadcast();

  /// Every message [send] was given, oldest first.
  final List<Map<String, Object?>> sent = [];

  /// How many times [connect] was called.
  int connectCalls = 0;

  /// How many times [openWatchApp] was called.
  int openCalls = 0;

  /// When set, the next [send] throws this instead of recording.
  Object? failNextSend;

  /// When true, every [send] throws [failNextSend] (or a default).
  bool failAllSends = false;

  @override
  WatchStatus get currentStatus => _status;

  /// Tests exercise both platforms, so this is settable.
  @override
  bool supportsSosFromWatch = true;

  @override
  Stream<WatchStatus> get status async* {
    yield _status;
    yield* _statuses.stream;
  }

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  /// Moves the link to [next] and notifies listeners.
  void setStatus(WatchStatus next) {
    _status = next;
    _statuses.add(next);
  }

  /// Delivers [message] as though the watch had sent it.
  void receive(Map<String, Object?> message) => _messages.add(message);

  /// Messages sent so far whose `t` is [type].
  List<Map<String, Object?>> sentOfType(String type) =>
      sent.where((m) => m['t'] == type).toList();

  @override
  Future<void> connect() async {
    connectCalls++;
  }

  @override
  Future<void> send(Map<String, Object?> message) async {
    if (failAllSends || failNextSend != null) {
      final error = failNextSend ?? StateError('watch send failed');
      failNextSend = null;
      throw error;
    }
    sent.add(message);
  }

  @override
  Future<void> openWatchApp() async {
    openCalls++;
  }

  @override
  Future<void> dispose() async {
    await _statuses.close();
    await _messages.close();
  }
}
