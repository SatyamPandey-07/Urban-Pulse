/// Getting the SOS message off the phone, and being truthful about whether it
/// left.
///
/// There are only two outcomes worth distinguishing, and the app must never
/// collapse them into "sent":
///
/// * **[SmsOutcome.sent]** — the OS accepted the message for delivery. Android
///   only, and only when `SEND_SMS` has been granted. Accepted is still not
///   *delivered*, and the wording everywhere says "sent" rather than "received".
/// * **[SmsOutcome.prepared]** — a composer was opened with the message and the
///   recipients filled in, and the traveller has to tap send. This is the only
///   thing iOS allows an app to do, and the Android fallback when the permission
///   is refused.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'emergency_contacts.dart';

enum SmsOutcome { sent, prepared, failed }

@immutable
class SmsResult {
  const SmsResult(this.outcome, {this.detail, this.reached = const []});

  const SmsResult.failed(String reason) : outcome = SmsOutcome.failed, detail = reason, reached = const [];

  final SmsOutcome outcome;

  /// Why it failed, or which contacts it reached.
  final String? detail;

  /// The numbers the OS accepted a message for. Empty for [SmsOutcome.prepared],
  /// because nothing has been sent yet.
  final List<String> reached;
}

abstract class EmergencySms {
  /// Whether this platform can send without the traveller tapping send, and has
  /// permission to. False means an SOS can only ever reach [SmsOutcome.prepared].
  Future<bool> canSendDirectly();

  /// Asks for the permission that would make [canSendDirectly] true. Returns
  /// whether it is now granted. A no-op where the permission does not exist.
  Future<bool> requestDirectPermission();

  Future<SmsResult> send({required List<EmergencyContact> to, required String body});
}

/// The real sender.
class PlatformEmergencySms implements EmergencySms {
  PlatformEmergencySms({MethodChannel? channel, bool? androidLike})
    : _channel = channel ?? const MethodChannel(channelName),
      _android = androidLike ?? (!kIsWeb && Platform.isAndroid);

  static const channelName = 'com.urbanpulse.app/sms';

  final MethodChannel _channel;
  final bool _android;

  @override
  Future<bool> canSendDirectly() async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('canSendSms') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> requestDirectPermission() async {
    if (!_android) return false;
    try {
      return await _channel.invokeMethod<bool>('requestSmsPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<SmsResult> send({required List<EmergencyContact> to, required String body}) async {
    if (to.isEmpty) return const SmsResult.failed('No emergency contacts');

    if (await canSendDirectly()) {
      try {
        final accepted = await _channel.invokeListMethod<String>('sendSms', {
          'numbers': to.map((c) => c.dialable).toList(),
          'body': body,
        });
        if (accepted != null && accepted.isNotEmpty) {
          return SmsResult(
            SmsOutcome.sent,
            detail: 'Sent to ${accepted.length} contact${accepted.length == 1 ? '' : 's'}',
            reached: accepted,
          );
        }
        // The platform ran but accepted nothing: fall through to the composer
        // rather than report a send that did not happen.
      } on PlatformException catch (e) {
        debugPrint('SOS: direct SMS failed (${e.code}), opening the composer instead');
      } on MissingPluginException {
        debugPrint('SOS: no SMS bridge in this build, opening the composer instead');
      }
    }

    return _openComposer(to, body);
  }

  Future<SmsResult> _openComposer(List<EmergencyContact> to, String body) async {
    // Multiple recipients: Android wants them semicolon-separated, iOS comma.
    final separator = _android ? ';' : ',';
    final recipients = to.map((c) => c.dialable).join(separator);
    final uri = Uri(
      scheme: 'sms',
      path: recipients,
      queryParameters: {'body': body},
    );
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) return const SmsResult.failed('No messaging app would open');
      return SmsResult(
        SmsOutcome.prepared,
        detail: 'Message ready in your SMS app - tap send',
      );
    } catch (e) {
      return SmsResult.failed('Could not open a messaging app: $e');
    }
  }
}
