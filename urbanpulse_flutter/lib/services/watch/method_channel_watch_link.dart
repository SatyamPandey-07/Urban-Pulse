/// The real [WatchLink], talking to the Connect IQ SDK through a platform
/// channel. See `android/app/src/garmin/kotlin` and `garmin/README.md`.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'watch_link.dart';

/// Names shared with the Kotlin and Swift sides. Changing one means changing
/// both.
abstract final class WatchChannels {
  static const method = 'com.urbanpulse.app/garmin';
  static const events = 'com.urbanpulse.app/garmin_events';
}

/// The port the Connect IQ simulator listens on for a tethered Android SDK.
const int tetheredPort = 7381;

class MethodChannelWatchLink implements WatchLink {
  MethodChannelWatchLink({
    MethodChannel? method,
    EventChannel? events,
    bool? supported,
    bool? sosFromWatch,
    bool? tethered,
  }) : _method = method ?? const MethodChannel(WatchChannels.method),
       _events = events ?? const EventChannel(WatchChannels.events),
       // Both platforms carry a real Connect IQ SDK: the Mobile SDK for Android
       // from Maven, and ConnectIQ.xcframework on iOS (see
       // ios/scripts/fetch_connectiq_sdk.sh). Web has neither.
       _supported = supported ?? (!kIsWeb && (Platform.isAndroid || Platform.isIOS)),
       // Android can send an SMS itself once SEND_SMS is granted, so a wrist SOS
       // can complete hands-free. iOS cannot, at any permission level.
       _sosFromWatch = sosFromWatch ?? (!kIsWeb && Platform.isAndroid),
       // Tethered mode points the Android SDK at the Connect IQ simulator over
       // ADB instead of a real watch. There is no iOS equivalent.
       _tethered = tethered ?? false;

  final MethodChannel _method;
  final EventChannel _events;
  final bool _supported;
  final bool _sosFromWatch;
  final bool _tethered;

  WatchStatus _status = WatchStatus.deviceNotConnected;
  final _statuses = StreamController<WatchStatus>.broadcast();
  final _messages = StreamController<Map<String, Object?>>.broadcast();
  StreamSubscription<dynamic>? _events$;
  bool _disposed = false;

  @override
  WatchStatus get currentStatus => _supported ? _status : WatchStatus.notSupported;

  @override
  bool get supportsSosFromWatch => _supported && _sosFromWatch;

  @override
  Stream<WatchStatus> get status async* {
    yield currentStatus;
    yield* _statuses.stream;
  }

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  Future<void> connect() async {
    if (!_supported || _disposed) return;
    _listen();
    try {
      final reported = await _method.invokeMethod<String>('connect', {
        'tethered': _tethered,
        'adbPort': tetheredPort,
      });
      _emit(_statusFrom(reported));
    } on PlatformException catch (e) {
      // A channel that answers with an error still tells us something real:
      // the plugin is there, the watch is not.
      _emit(_statusFrom(e.code));
    } on MissingPluginException {
      _emit(WatchStatus.notSupported);
    }
  }

  void _listen() {
    _events$ ??= _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (_) => _emit(WatchStatus.deviceNotConnected),
      cancelOnError: false,
    );
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    // One channel carries both kinds; a status event has no protocol `t`.
    final statusName = event['status'];
    if (statusName is String && event['t'] == null) {
      _emit(_statusFrom(statusName));
      return;
    }
    _messages.add(event.map((k, v) => MapEntry(k.toString(), v as Object?)));
  }

  void _emit(WatchStatus next) {
    if (_disposed || next == _status) return;
    _status = next;
    _statuses.add(next);
  }

  static WatchStatus _statusFrom(String? name) => switch (name) {
    'connected' => WatchStatus.connected,
    'watchAppNotInstalled' => WatchStatus.watchAppNotInstalled,
    'deviceNotConnected' => WatchStatus.deviceNotConnected,
    'noDevicePaired' => WatchStatus.noDevicePaired,
    'garminAppMissing' => WatchStatus.garminAppMissing,
    'notSupported' => WatchStatus.notSupported,
    // An unrecognised code is not a connection.
    _ => WatchStatus.deviceNotConnected,
  };

  @override
  Future<void> send(Map<String, Object?> message) async {
    if (!_supported) {
      throw const WatchSendException('The Connect IQ SDK is not available on this platform');
    }
    try {
      await _method.invokeMethod<void>('send', message);
    } on PlatformException catch (e) {
      throw WatchSendException(e.message ?? e.code);
    } on MissingPluginException {
      throw const WatchSendException('The Garmin bridge is missing from this build');
    }
  }

  @override
  Future<void> openWatchApp() async {
    if (!_supported) return;
    try {
      final reported = await _method.invokeMethod<String>('openWatchApp');
      _emit(_statusFrom(reported));
    } on PlatformException catch (e) {
      _emit(_statusFrom(e.code));
    } on MissingPluginException {
      _emit(WatchStatus.notSupported);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _events$?.cancel();
    try {
      await _method.invokeMethod<void>('shutdown');
    } catch (_) {
      // Tearing down is best effort; the platform side also releases on detach.
    }
    await _statuses.close();
    await _messages.close();
  }
}

/// Thrown when a message could not be handed to the SDK.
class WatchSendException implements Exception {
  const WatchSendException(this.message);

  final String message;

  @override
  String toString() => 'WatchSendException: $message';
}
