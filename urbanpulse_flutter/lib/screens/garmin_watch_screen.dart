import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/watch/watch_link.dart';
import '../services/watch/watch_service.dart';
import '../state/app_scope.dart';
import '../state/emergency_sos_controller.dart';
import '../widgets/common.dart';
import 'emergency_contacts_screen.dart';

/// Settings → Garmin watch.
///
/// The status shown here is whatever the Connect IQ SDK last reported, verbatim.
/// There is no "connecting…" that hides a failure and no optimistic "Connected":
/// each of the six [WatchStatus] values has its own line and its own next step,
/// because "no watch paired" and "watch app not installed" need different actions
/// from the traveller.
class GarminWatchScreen extends StatefulWidget {
  const GarminWatchScreen({super.key});

  @override
  State<GarminWatchScreen> createState() => _GarminWatchScreenState();
}

class _GarminWatchScreenState extends State<GarminWatchScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Probing on open is what makes the row truthful; nothing is cached from a
    // previous session.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).startWatchLink();
    });
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (done != null && mounted) showToast(context, done);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final services = AppScope.of(context);
    final watch = services.watch;

    return Scaffold(
      appBar: const ScreenHeader(
        title: 'Garmin watch',
        subtitle: 'Mirror your trip to your wrist',
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([watch, services.emergencyContacts, services.emergencySos]),
        builder: (context, _) {
          final status = watch.status;
          final sos = services.emergencySos;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              // A watch-raised SOS is cancellable from either side, so its
              // countdown has to be reachable on the phone too.
              if (sos.state.phase != EmergencySosPhase.idle) ...[
                _sosProgressCard(theme, sos),
                const SizedBox(height: 16),
              ],
              _statusCard(theme, watch, status),
              const SizedBox(height: 16),
              _mirrorCard(theme, watch, status),
              const SizedBox(height: 16),
              _sosCard(theme, watch, services),
              const SizedBox(height: 16),
              _helpCard(theme, status),
            ],
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------------------


  /// The live state of an SOS raised from the watch: its countdown, a phone-side
  /// cancel, and afterwards the true outcome.
  ///
  /// Worded so it never over-claims - "sent" only where the OS accepted a
  /// message, "ready" where a composer was merely opened.
  Widget _sosProgressCard(ThemeData theme, EmergencySosController sos) {
    final state = sos.state;
    final (String title, String body, Color colour) = switch (state.phase) {
      EmergencySosPhase.armed => (
        'Sending in ${state.secondsLeft}s',
        state.origin == SosOrigin.watch
            ? 'Raised from your watch. Cancel here or on the watch.'
            : 'Cancel before your emergency contacts are messaged.',
        const Color(0xFFDC2626),
      ),
      EmergencySosPhase.locating => ('Getting your location', 'One moment.', const Color(0xFFDC2626)),
      EmergencySosPhase.sending => ('Messaging your contacts', 'Sending now.', const Color(0xFFDC2626)),
      EmergencySosPhase.sent => (
        'Message sent',
        state.detail ?? 'Your emergency contacts have been messaged.',
        const Color(0xFF16A34A),
      ),
      EmergencySosPhase.prepared => (
        'Ready to send',
        state.detail ?? 'Your messaging app is open with the message ready. Tap send.',
        const Color(0xFFD97706),
      ),
      EmergencySosPhase.failed => (
        'Could not send',
        state.detail ?? 'Nothing was sent.',
        const Color(0xFFDC2626),
      ),
      EmergencySosPhase.cancelled => (
        'Cancelled',
        'No message was sent.',
        theme.colorScheme.onSurfaceVariant,
      ),
      EmergencySosPhase.idle => ('', '', theme.colorScheme.onSurfaceVariant),
    };

    return SectionCard(
      borderColor: colour,
      borderWidth: 1.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (state.isActive)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: colour),
                )
              else
                Icon(
                  state.phase == EmergencySosPhase.sent
                      ? Icons.check_circle_rounded
                      : state.phase == EmergencySosPhase.cancelled
                      ? Icons.cancel_rounded
                      : Icons.error_rounded,
                  color: colour,
                  size: 20,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colour,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body, style: theme.textTheme.bodySmall),
          if (state.positionAgeS != null) ...[
            const SizedBox(height: 6),
            Text(
              'The position sent was ${state.positionAgeS}s old - there was no fresh GPS fix.',
              style: theme.textTheme.bodySmall?.copyWith(color: colour),
            ),
          ],
          const SizedBox(height: 12),
          if (state.phase == EmergencySosPhase.armed)
            FilledButton.icon(
              onPressed: sos.cancel,
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancel SOS'),
            )
          else if (state.isFinished)
            TextButton(onPressed: sos.acknowledge, child: const Text('Dismiss')),
        ],
      ),
    );
  }

  Widget _statusCard(ThemeData theme, WatchService watch, WatchStatus status) {
    final good = status.isConnected;
    final colour = good
        ? const Color(0xFF16A34A)
        : status == WatchStatus.notSupported
        ? theme.colorScheme.onSurfaceVariant
        : const Color(0xFFD97706);

    return SectionCard(
      borderColor: colour,
      borderWidth: good ? 1.5 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colour,
                  ),
                ),
              ),
              if (_busy)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          Text(_explain(status, watch), style: theme.textTheme.bodySmall),
          if (watch.connectedDevice != null) ...[
            const SizedBox(height: 6),
            Text(
              'Watch reports: ${watch.connectedDevice}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (status.canRetry)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(watch.connect),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      status == WatchStatus.noDevicePaired ? 'Choose watch' : 'Connect',
                    ),
                  ),
                ),
              if (status.canRetry) const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy || !status.canRetry
                      ? null
                      : () => _run(watch.openWatchApp),
                  icon: const Icon(Icons.watch_rounded, size: 18),
                  label: const Text('Open on watch'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            // "Nothing is on my watch" has several causes; this says which.
            onPressed: _busy || !status.isConnected
                ? null
                : () async {
                    setState(() => _busy = true);
                    final outcome = await watch.resendPlan();
                    if (mounted) {
                      setState(() => _busy = false);
                      showToast(context, outcome);
                    }
                  },
            icon: const Icon(Icons.download_done_rounded, size: 18),
            label: const Text("Send today's plan to watch"),
          ),
          TextButton.icon(
            // A test buzz is the only way to prove the whole chain end to end
            // without waiting for a real Live Mode update.
            onPressed: _busy || !status.isConnected
                ? null
                : () async {
                    final sent = await watch.sendTestBuzz();
                    if (mounted) {
                      showToast(
                        context,
                        sent ? 'Buzz sent to the watch' : 'Could not reach the watch',
                      );
                    }
                  },
            icon: const Icon(Icons.vibration_rounded, size: 18),
            label: const Text('Send a test buzz'),
          ),
        ],
      ),
    );
  }

  String _explain(WatchStatus status, WatchService watch) => switch (status) {
    WatchStatus.connected =>
      'Messages will reach the watch. Live Mode updates appear on your wrist.',
    WatchStatus.watchAppNotInstalled =>
      'Your watch is connected, but the Urban Pulse watch app is not on it. '
          'Side-load it with the Connect IQ SDK, then tap Open on watch.',
    WatchStatus.deviceNotConnected =>
      'A watch is known but not reachable right now. Check it is on your wrist, '
          'in range, and its Bluetooth is on.',
    WatchStatus.noDevicePaired =>
      Platform.isIOS
          ? 'Tap Choose watch. Garmin Connect will open so you can pick which '
                'watch to share with Urban Pulse, then return here.'
          : 'Garmin Connect knows of no watch. Pair one there first.',
    WatchStatus.garminAppMissing =>
      'Garmin Connect is not installed, so nothing can reach the watch. '
          'Install it and sign in, then come back.',
    WatchStatus.notSupported =>
      'This build has no Connect IQ SDK for this platform.',
  };

  // --------------------------------------------------------------------------

  Widget _mirrorCard(ThemeData theme, WatchService watch, WatchStatus status) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SwitchListTile(
        value: watch.mirrorAlerts,
        onChanged: (v) => _run(() => watch.setMirrorAlerts(v)),
        title: const Text('Mirror Live Mode alerts to watch'),
        subtitle: Text(
          watch.mirrorAlerts
              ? 'Next stop, arrival time and distance, plus a buzz for each update.'
              : 'The watch shows nothing while this is off.',
          style: theme.textTheme.bodySmall,
        ),
        secondary: const Icon(Icons.notifications_active_outlined),
      ),
    );
  }

  Widget _sosCard(ThemeData theme, WatchService watch, AppServices services) {
    final contacts = services.emergencyContacts;
    final supported = watch.sosFromWatchSupported;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: watch.sosFromWatch,
            // Disabled where the platform cannot complete an SOS, rather than
            // shown as an option that quietly does nothing.
            onChanged: !supported || contacts.isEmpty
                ? null
                : (v) => _run(() => watch.setSosFromWatch(v)),
            title: const Text('SOS from watch'),
            subtitle: Text(
              !supported
                  ? 'Not available on iPhone: iOS cannot send an SMS without you '
                        'tapping send, so a wrist SOS could not complete on its own. '
                        'Use the SOS button in the app.'
                  : contacts.isEmpty
                  ? 'Add an emergency contact first - there is nobody to alert.'
                  : watch.sosFromWatch
                  ? 'Hold START on the watch for 3 seconds. You get 10 seconds to cancel.'
                  : 'Off by default: a 3 second hold is easy to trigger by accident.',
              style: theme.textTheme.bodySmall,
            ),
            secondary: Icon(
              Icons.sos_rounded,
              color: watch.sosFromWatch ? const Color(0xFFDC2626) : null,
            ),
          ),
          if (watch.sosFromWatchRefused) ...[
            const SizedBox(height: 4),
            Text(
              'Your watch asked for an SOS while this was off, so nothing was sent.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const Divider(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.contact_emergency_outlined),
            title: const Text('Emergency contacts'),
            subtitle: Text(
              contacts.isEmpty
                  ? 'None yet - SOS cannot send anything'
                  : '${contacts.contacts.length} of ${5} saved',
              style: theme.textTheme.bodySmall?.copyWith(
                color: contacts.isEmpty ? theme.colorScheme.error : null,
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const EmergencyContactsScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _helpCard(ThemeData theme, WatchStatus status) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What the watch shows',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...[
            'Next stop, its time, and its distance when the phone knows one.',
            'A buzz and one line for each Live Mode update.',
            'Nothing invented: with no data it says "Waiting for phone", and '
                'anything older than 5 minutes is greyed with its age.',
          ].map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('- '),
                  Expanded(child: Text(line, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
          ),
          if (kDebugMode) ...[
            const Divider(height: 20),
            Text(
              'Debug build. On Android the Connect IQ simulator can stand in for a '
                  'watch over ADB; iOS has no such mode and needs real hardware.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
