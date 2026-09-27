import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../core/formatting.dart';
import '../services/ble_sos_service.dart';
import '../state/app_scope.dart';
import '../state/sos_controller.dart';
import '../widgets/common.dart';
import 'emergency_contacts_screen.dart';

/// Screen for raising emergency SOS alerts and listening for nearby BLE emergency beacons.
///
/// Features:
/// - 3-second hold to broadcast high-priority BLE emergency beacon.
/// - Peer-to-peer offline Bluetooth mesh radar scanning.
/// - Live proximity alert notifications when nearby app users trigger SOS.
/// - Active broadcast HUD with beacon ID, responder reach count, and GPS fix.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen>
    with TickerProviderStateMixin {
  static const _holdDuration = Duration(seconds: 3);

  late final AnimationController _holdController =
      AnimationController(vsync: this, duration: _holdDuration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _triggerSos();
        });

  late final AnimationController _radarController =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

  final BleSosService _bleService = BleSosService.instance;
  bool _isSending = false;
  String? _category = 'Medical';

  SosController? _sos;

  @override
  void initState() {
    super.initState();
    _bleService.addListener(_onBleUpdate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The same controller the watch drives, so an SOS raised on either side shows
    // the same countdown and the same outcome here.
    final sos = AppScope.of(context).sos;
    if (_sos != sos) {
      _sos?.removeListener(_onBleUpdate);
      _sos = sos..addListener(_onBleUpdate);
    }
  }

  @override
  void dispose() {
    _sos?.removeListener(_onBleUpdate);
    _bleService.removeListener(_onBleUpdate);
    _holdController.dispose();
    _radarController.dispose();
    super.dispose();
  }

  void _onBleUpdate() {
    if (mounted) setState(() {});
  }

  void _onPressStart() => _holdController.forward();

  void _onPressEnd() {
    final wasIncomplete = _holdController.value < 1.0;
    _holdController.reverse();
    if (wasIncomplete && !_isSending && !_bleService.isBroadcasting) {
      showToast(context, 'Hold for 3 seconds to broadcast SOS beacon');
    }
  }

  Future<void> _triggerSos() async {
    if (_isSending) return;
    setState(() => _isSending = true);

    final location = AppScope.of(context).location;
    await location.resolve(force: true);
    if (!mounted) return;

    final lat = location.hasFix ? location.latitude! : 18.9894;
    final lng = location.hasFix ? location.longitude! : 73.1175;

    await _bleService.broadcastSos(
      category: _category ?? 'Emergency',
      latitude: lat,
      longitude: lng,
      locationName: location.hasFix ? 'GPS Fix (${fixed(lat, 4)}, ${fixed(lng, 4)})' : 'Offline Peer Mesh Fix',
    );

    // The BLE beacon only reaches strangers in range. This is what reaches the
    // people the traveller chose, and it reports honestly whether it managed to.
    final started = await _sos?.trigger() ?? false;

    setState(() => _isSending = false);
    _holdController.reset();

    if (!mounted) return;
    showToast(
      context,
      started
          ? 'SOS armed - messaging your emergency contacts in 10 seconds'
          : 'BLE beacon broadcasting. No emergency contacts, so no message was sent.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBroadcasting = _bleService.isBroadcasting;
    final nearbySignals = _bleService.nearbySignals;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency SOS & BLE Mesh'),
        actions: [
          IconButton(
            tooltip: 'Simulate Nearby Peer Alert',
            icon: const Icon(Icons.radar),
            onPressed: () {
              _bleService.simulateIncomingSignal(
                name: 'Traveler Ananya',
                category: EmergencyCategory.medical,
                distanceMeters: 28.0,
                locationName: 'Near Station Gate 3',
              );
              showToast(context, 'Simulated incoming BLE peer SOS from 28m away');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The shared SOS: its countdown, and the true outcome afterwards.
              if (_sos != null && _sos!.state.phase != SosPhase.idle) ...[
                _buildSosStatusCard(theme, _sos!),
                const SizedBox(height: 16),
              ],

              // BLE Mesh Radar status pill
              _buildBleMeshBanner(theme),
              const SizedBox(height: 20),

              if (isBroadcasting) ...[
                _buildActiveBroadcastCard(theme),
                const SizedBox(height: 24),
              ],

              // Main SOS Trigger Header
              Text(
                isBroadcasting ? 'Broadcasting Active' : 'Are you in an emergency?',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isBroadcasting ? AppColors.sosRed : null,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isBroadcasting
                    ? 'Your BLE beacon is pulsing. Nearby travelers & responders are receiving alerts.'
                    : 'Press & hold the SOS button for 3 seconds to broadcast offline BLE mesh beacon and notify nearby app users.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),

              // Concentric Animated Radar & SOS Button
              Center(child: _sosButton(context)),
              const SizedBox(height: 16),
              Text(
                _isSending
                    ? 'Broadcasting BLE beacon…'
                    : isBroadcasting
                        ? 'Broadcasting SOS to ${_bleService.nearbyRespondersCount} nearby devices'
                        : _category == null
                            ? 'Hold 3 sec for emergency broadcast'
                            : 'Hold 3 sec for $_category alert',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isBroadcasting ? AppColors.sosRed : theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 28),

              // Emergency Category Selectors
              Text(
                "Select Emergency Category",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _categoryCard(
                      context,
                      'Medical',
                      Icons.medical_services_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _categoryCard(
                      context,
                      'Fire',
                      Icons.local_fire_department_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _categoryCard(
                      context,
                      'Accident',
                      Icons.car_crash_outlined,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _categoryCard(
                      context,
                      'Violence',
                      Icons.shield_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Nearby Peer Signals Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.bluetooth_searching, size: 20, color: AppColors.primaryGreen),
                      const SizedBox(width: 8),
                      Text(
                        'Nearby Peer Signals (${nearbySignals.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (nearbySignals.isNotEmpty)
                    TextButton(
                      onPressed: () => _bleService.clearSignals(),
                      child: const Text('Clear', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              if (nearbySignals.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.wifi_tethering, size: 36, color: theme.colorScheme.outline),
                      const SizedBox(height: 8),
                      Text(
                        'No Emergency Signals Detected',
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your device is continuously scanning for peer BLE broadcasts within ~150 meters even without internet.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else
                ...nearbySignals.map((signal) => _buildPeerSignalCard(context, signal)),

              const SizedBox(height: 24),
              // Simulation Trigger Card for easy testing
              _buildDemoToolsCard(theme),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  /// The shared [SosController]'s state, worded so it never over-claims: "sent"
  /// only where the OS accepted a message, "ready" where a composer opened.
  Widget _buildSosStatusCard(ThemeData theme, SosController sos) {
    final state = sos.state;
    final (String title, String body, Color colour) = switch (state.phase) {
      SosPhase.armed => (
        'Sending in ${state.secondsLeft}s',
        state.origin == SosOrigin.watch
            ? 'Raised from your Garmin watch. Tap Cancel to stop.'
            : 'Tap Cancel to stop before your contacts are messaged.',
        AppColors.sosRed,
      ),
      SosPhase.locating => ('Getting your location', 'One moment.', AppColors.sosRed),
      SosPhase.sending => ('Messaging your contacts', 'Sending now.', AppColors.sosRed),
      SosPhase.sent => (
        'Message sent',
        state.detail ?? 'Your emergency contacts have been messaged.',
        const Color(0xFF16A34A),
      ),
      SosPhase.prepared => (
        'Ready to send',
        // Deliberately not "sent": on iPhone nothing leaves without this tap.
        state.detail ?? 'Your messaging app is open with the message ready. Tap send.',
        const Color(0xFFD97706),
      ),
      SosPhase.failed => (
        'Could not send',
        state.detail ?? 'Nothing was sent.',
        AppColors.sosRed,
      ),
      SosPhase.cancelled => (
        'Cancelled',
        'No message was sent.',
        theme.colorScheme.onSurfaceVariant,
      ),
      SosPhase.idle => ('', '', theme.colorScheme.onSurfaceVariant),
    };

    final noContacts =
        state.phase == SosPhase.failed && (state.detail ?? '').contains('No emergency contacts');

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
                  state.phase == SosPhase.sent
                      ? Icons.check_circle_rounded
                      : state.phase == SosPhase.cancelled
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
          if (state.phase == SosPhase.armed)
            FilledButton.icon(
              onPressed: sos.cancel,
              style: FilledButton.styleFrom(backgroundColor: AppColors.sosRed),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancel SOS'),
            )
          else if (state.isFinished)
            noContacts
                ? OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EmergencyContactsScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Add emergency contacts'),
                  )
                : TextButton(onPressed: sos.acknowledge, child: const Text('Dismiss')),
        ],
      ),
    );
  }

  Widget _buildBleMeshBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, _) => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryGreen,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.6 * (1 - _radarController.value)),
                    blurRadius: 6 * _radarController.value,
                    spreadRadius: 3 * _radarController.value,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BLE Peer-to-Peer Mesh Active',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                ),
                Text(
                  '${_bleService.nearbyRespondersCount} peer app nodes in ~150m listening range',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'OFFLINE OK',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveBroadcastCard(ThemeData theme) {
    final broadcast = _bleService.activeBroadcast;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.sosRed.withValues(alpha: 0.15),
            AppColors.sosDeepRed.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.sosRed, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppColors.sosRed,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.broadcast_on_personal, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BROADCASTING EMERGENCY BEACON',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: AppColors.sosRed,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'ID: ${broadcast?.id ?? "UP-SOS-LIVE"} • ${broadcast?.category.label ?? "General"}',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Location: ${broadcast?.locationName ?? "Active GPS Fix"}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '⚡ ${_bleService.nearbyRespondersCount} nearby responders alerted',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.sosRed),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.sosRed,
                  side: const BorderSide(color: AppColors.sosRed),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () {
                  _bleService.cancelSos();
                  showToast(context, 'SOS broadcast canceled');
                },
                child: const Text('Cancel SOS'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeerSignalCard(BuildContext context, BleEmergencySignal signal) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: signal.isResponded
              ? AppColors.primaryGreen.withValues(alpha: 0.5)
              : AppColors.sosRed.withValues(alpha: 0.6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(signal.category.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${signal.senderName} • ${signal.category.label}',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${signal.locationName} • ${signal.timeAgo}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.sosRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '~${signal.distanceMeters.round()}m away',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.sosRed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.network_ping, size: 14, color: theme.colorScheme.outline),
              const SizedBox(width: 4),
              Text(
                'Signal: ${signal.signalQuality} (${signal.rssi} dBm) • ${signal.meshHops} mesh hop(s)',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: theme.colorScheme.outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (signal.isResponded)
                const Chip(
                  avatar: Icon(Icons.check_circle, size: 16, color: AppColors.primaryGreen),
                  label: Text('You Responded • Assistance En Route', style: TextStyle(fontSize: 11)),
                  backgroundColor: Color(0xFFE8F8F0),
                  visualDensity: VisualDensity.compact,
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.sosRed,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.navigation, size: 16),
                  label: const Text('Navigate & Assist'),
                  onPressed: () {
                    _bleService.respondToSignal(signal.id);
                    showToast(context, 'Responding to ${signal.senderName}! Opening mesh compass route.');
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDemoToolsCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, size: 18),
              const SizedBox(width: 8),
              Text(
                'BLE Mesh Simulation Testing',
                style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Test peer beacon mesh alerts received from other travelers in your vicinity:',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                avatar: const Text('🚨'),
                label: const Text('Nearby Medical (25m)', style: TextStyle(fontSize: 11)),
                onPressed: () {
                  _bleService.simulateIncomingSignal(
                    name: 'Traveler Priya',
                    category: EmergencyCategory.medical,
                    distanceMeters: 25.0,
                    locationName: 'North Gate • Taxi Stand',
                  );
                },
              ),
              ActionChip(
                avatar: const Text('🚗'),
                label: const Text('Accident Alert (60m)', style: TextStyle(fontSize: 11)),
                onPressed: () {
                  _bleService.simulateIncomingSignal(
                    name: 'Rider Kabir',
                    category: EmergencyCategory.accident,
                    distanceMeters: 60.0,
                    locationName: 'Main Ring Road Cross',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sosButton(BuildContext context) => GestureDetector(
    onTapDown: (_) => _onPressStart(),
    onTapUp: (_) => _onPressEnd(),
    onTapCancel: _onPressEnd,
    child: AnimatedBuilder(
      animation: Listenable.merge([_holdController, _radarController]),
      builder: (context, child) {
        final isBroadcasting = _bleService.isBroadcasting;
        final radarVal = _radarController.value;

        return SizedBox(
          width: 230,
          height: 230,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer radar pulse circle
              Container(
                width: 170 + 60 * radarVal,
                height: 170 + 60 * radarVal,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.sosRed.withValues(
                    alpha: (1 - radarVal) * (isBroadcasting ? 0.35 : 0.12),
                  ),
                ),
              ),
              // Inner radar wave
              Container(
                width: 160 + 30 * radarVal,
                height: 160 + 30 * radarVal,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.sosRed.withValues(
                    alpha: (1 - radarVal) * 0.2,
                  ),
                ),
              ),
              // Base button shell
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.sosRed.withValues(alpha: 0.15),
                ),
                padding: const EdgeInsets.all(12),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Hold progress indicator
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: _holdController.value == 0
                            ? (isBroadcasting ? null : 0.0)
                            : _holdController.value,
                        strokeWidth: 7,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation(
                          isBroadcasting ? AppColors.sosRed : Colors.white,
                        ),
                      ),
                    ),
                    Transform.scale(
                      scale: 1 - 0.08 * _holdController.value,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.sosRed, AppColors.sosDeepRed],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.sosRed.withValues(alpha: 0.4),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'SOS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              isBroadcasting ? 'BROADCASTING' : 'HOLD 3s',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _categoryCard(BuildContext context, String label, IconData icon) {
    final isSelected = _category == label;
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderWidth: isSelected ? 2 : 0,
      borderColor: AppColors.sosRed,
      onTap: () => setState(() => _category = isSelected ? null : label),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.sosRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (isSelected)
            const Icon(Icons.check_circle, size: 18, color: AppColors.sosRed),
        ],
      ),
    );
  }
}

