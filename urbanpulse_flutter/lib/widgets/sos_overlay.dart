import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/routes.dart';
import '../models/app_notification.dart';
import '../screens/sos_screen.dart';
import '../services/sos/sos_models.dart';
import '../services/watch/watch_service.dart';
import '../state/app_scope.dart';
import '../state/notification_controller.dart';
import '../state/sos_controller.dart';

/// Above every screen: a red pill while your own SOS is active (tap to manage
/// it), and an alert when someone near you raises one.
class SosOverlay extends StatefulWidget {
  const SosOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<SosOverlay> createState() => _SosOverlayState();
}

class _SosOverlayState extends State<SosOverlay> {
  SosController? _sos;
  NotificationController? _notifications;
  GlobalKey<NavigatorState>? _nav;
  final _subs = <StreamSubscription<Object?>>[];
  final _queue = <SosEvent>[];
  bool _showing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sos != null) return;
    final services = AppScope.of(context);
    _sos = services.sos;
    _notifications = services.notifications;
    _nav = services.navigatorKey;
    _subs
      ..add(_sos!.newAlerts.listen(_alert))
      ..add(_sos!.openRequests.listen((_) => _openSos()))
      // The watch's SOS button, answered on the phone as well as the wrist.
      ..add(services.watch.watchSosRequests.listen(_watchSos));
    // Nothing arrives from the watch until the link is listening, and the
    // traveller should not have to open a settings screen for their SOS button
    // to work. Does nothing unless a watch has been paired before.
    unawaited(services.watch.reconnectIfPaired());
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  void _openSos() {
    if (SosScreen.open.value > 0) return;
    unawaited(_nav?.currentState?.pushNamed(Routes.sos));
  }

  void _alert(SosEvent e) {
    final away = _sos?.distanceKm(e);
    unawaited(
      _notifications?.add(
        kind: NotificationKind.sos,
        title: '${e.name} needs help nearby',
        body: '${e.category.label}${away == null ? '' : ' · ${SosController.distanceLabel(away)} away'}.',
        target: const NotificationTarget.route(Routes.sos),
      ),
    );
    // In the background Android's own notification is the alert.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    _queue.add(e);
    unawaited(_next());
  }

  /// The watch asked for an SOS. Say so here, whatever screen is open.
  ///
  /// This matters most when the phone could not act: the traveller held a button
  /// for three seconds, and a silent refusal on the wrist alone would leave them
  /// believing help was on its way.
  Future<void> _watchSos(WatchSosNotice notice) async {
    unawaited(HapticFeedback.heavyImpact());
    final ctx = _nav?.currentContext;
    if (ctx == null) return;

    if (notice.started) {
      // The countdown is running; the SOS screen is where it can be cancelled.
      _openSos();
      return;
    }

    await showDialog<void>(
      context: ctx,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.watch_off_rounded, color: Color(0xFFDC2626), size: 40),
        title: const Text('SOS pressed on your watch'),
        content: Text(
          '${notice.reason}\n\n'
          'Nothing has been sent. Use the SOS button in the app to message your '
          'emergency contacts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () {
              Navigator.of(context).pop();
              _openSos();
            },
            child: const Text('Open SOS'),
          ),
        ],
      ),
    );
  }

  Future<void> _next() async {
    if (_showing || _queue.isEmpty) return;
    final ctx = _nav?.currentContext;
    if (ctx == null) return;
    final e = _queue.removeAt(0);
    final sos = _sos!;
    // Skip one that ended while it waited.
    if (!sos.nearby.any((x) => x.id == e.id)) {
      unawaited(_next());
      return;
    }
    _showing = true;
    unawaited(HapticFeedback.heavyImpact());
    final away = sos.distanceKm(e);
    final view = await showDialog<bool>(
      context: ctx,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.sos_rounded, color: Color(0xFFDC2626), size: 40),
        title: Text('${e.name} needs help nearby'),
        content: Text(
          '${e.category.label}${away == null ? '' : ' · ${SosController.distanceLabel(away)} away'}.\n'
          'If you can help safely, see where they are. If it is serious, call 112.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Dismiss')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('See where'),
          ),
        ],
      ),
    );
    _showing = false;
    if (view == true) _openSos();
    unawaited(_next());
  }

  @override
  Widget build(BuildContext context) {
    final sos = _sos ?? AppScope.of(context).sos;
    return AnimatedBuilder(
      animation: Listenable.merge([sos, SosScreen.open]),
      builder: (context, child) => Stack(
        children: [
          child!,
          if ((sos.isRaised || sos.phase == SosPhase.resolving) && SosScreen.open.value == 0)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 6,
              left: 0,
              right: 0,
              child: Center(child: _ActivePill(sos: sos, onTap: _openSos)),
            ),
        ],
      ),
      child: widget.child,
    );
  }
}

class _ActivePill extends StatelessWidget {
  const _ActivePill({required this.sos, required this.onTap});

  final SosController sos;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = switch (sos.phase) {
      SosPhase.sending => sos.syncProblem == null ? 'Sending SOS…' : 'SOS saved, waiting for network',
      SosPhase.resolving => 'Ending SOS…',
      _ => sos.responders > 0 ? 'SOS active · ${sos.responders} on the way' : 'SOS active · tap to manage',
    };
    return Material(
      color: const Color(0xFFDC2626),
      elevation: 6,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sos_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}
