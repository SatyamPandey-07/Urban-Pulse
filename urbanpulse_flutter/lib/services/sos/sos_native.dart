import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The Android side of SOS (`SosTriggerService` and `SosBridge` in the app's
/// Kotlin code): a foreground service that notices three quick presses of the
/// power button (the screen turning off and on), and the SOS notifications.
/// On the web and other platforms every call is a quiet no-op.
class SosNative {
  SosNative({MethodChannel? channel}) : _ch = channel ?? const MethodChannel('urbanpulse/sos');

  final MethodChannel _ch;

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Receives 'trigger' {source}, 'cancel' and 'openSos' from Android. Returns
  /// a trigger that happened before Dart was ready (a cold start), if any.
  Future<String?> ready(Future<void> Function(String method, Map<String, dynamic> args) handler) async {
    if (!supported) return null;
    _ch.setMethodCallHandler((call) async {
      final args = call.arguments is Map ? Map<String, dynamic>.from(call.arguments as Map) : const <String, dynamic>{};
      await handler(call.method, args);
      return null;
    });
    try {
      final r = await _ch.invokeMethod<Map<Object?, Object?>>('ready');
      return r?['pending'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Starts watching the power button. False when Android refused (for
  /// example no location permission yet).
  Future<bool> startTrigger() async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('startTrigger') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopTrigger() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<void>('stopTrigger');
    } catch (_) {}
  }

  /// {running, notifications, batteryUnrestricted}.
  Future<Map<String, bool>> status() async {
    if (!supported) return const {};
    try {
      final r = await _ch.invokeMethod<Map<Object?, Object?>>('status');
      return {for (final e in (r ?? const {}).entries) '${e.key}': e.value == true};
    } catch (_) {
      return const {};
    }
  }

  /// Shows (or clears) the ongoing "SOS active" notification with its cancel action.
  Future<void> setActive(bool active, {String? detail}) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<void>('setActive', {'active': active, 'detail': detail});
    } catch (_) {}
  }

  /// A heads-up notification about an SOS nearby (used while the app is in the background).
  Future<void> notifyNearby({required String id, required String title, required String body}) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<void>('notifyNearby', {'id': id, 'title': title, 'body': body});
    } catch (_) {}
  }

  Future<void> clearNearby(String id) async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<void>('clearNearby', {'id': id});
    } catch (_) {}
  }

  /// Asks for the notification permission (Android 13+).
  Future<bool> requestNotifications() async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('requestNotifications') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system screen to let the app run unrestricted in the background.
  Future<void> openBatterySettings() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<void>('openBatterySettings');
    } catch (_) {}
  }
}
