import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/formatting.dart';
import '../services/sos/sos_locator.dart';
import '../services/sos/sos_models.dart';
import '../state/app_scope.dart';
import '../state/sos_controller.dart';
import '../widgets/common.dart';

const _red = Color(0xFFDC2626);

/// Emergency SOS: your own (raise, see its state, end it), how the power-button
/// trigger is set up, and SOS alerts from people near you.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  /// How many SOS screens are open: the overlay does not stack another, and
  /// hides its "SOS active" pill while one is showing.
  static final open = ValueNotifier<int>(0);

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with WidgetsBindingObserver {
  SosController? _sos;
  SosCategory _category = SosCategory.general;
  final _responded = <String>{};

  @override
  void initState() {
    super.initState();
    SosScreen.open.value++;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sos != null) return;
    _sos = AppScope.of(context).sos;
    unawaited(_sos!.refreshNativeStatus().then((_) => mounted ? setState(() {}) : null));
    unawaited(_sos!.refreshNearby());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from a system settings screen: permissions may have changed.
    if (state == AppLifecycleState.resumed) {
      unawaited(_sos?.refreshNativeStatus().then((_) => mounted ? setState(() {}) : null));
    }
  }

  @override
  void dispose() {
    SosScreen.open.value--;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _call(String number) async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: number));
    } catch (_) {
      if (mounted) showToast(context, 'Could not open the dialer. Call $number.');
    }
  }

  Future<void> _navigate(SosEvent e) async {
    if (!e.hasLocation) return;
    final uri = Uri.https('www.google.com', '/maps/dir/', {'api': '1', 'destination': '${e.lat},${e.lng}', 'travelmode': 'walking'});
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) showToast(context, 'Could not open maps.');
    }
  }

  Future<void> _resolve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End your SOS?'),
        content: const Text('People nearby will see that you are safe.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep it active')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("I'm safe")),
        ],
      ),
    );
    if (ok == true) await _sos!.resolve();
  }

  Future<void> _respond(SosEvent e) async {
    final ok = await _sos!.respond(e);
    if (!mounted) return;
    if (ok) setState(() => _responded.add(e.id));
    showToast(context, ok ? '${e.name} can see that someone is on the way.' : 'Could not send that. Check your connection.');
  }

  @override
  Widget build(BuildContext context) {
    final sos = _sos!;
    return AnimatedBuilder(
      animation: sos,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Emergency SOS')),
        body: RefreshIndicator(
          onRefresh: sos.refreshNearby,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (!sos.hasAccounts || !sos.signedIn) _AccountNotice(signedIn: sos.signedIn, hasAccounts: sos.hasAccounts),
              _OwnSos(sos: sos, category: _category, onCategory: (c) => setState(() => _category = c), onResolve: _resolve),
              const SizedBox(height: 12),
              _EmergencyNumbers(onCall: _call),
              if (sos.triggerSupported) ...[const SizedBox(height: 12), _PowerButton(sos: sos)],
              const SizedBox(height: 16),
              _Nearby(sos: sos, responded: _responded, onNavigate: _navigate, onRespond: _respond),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountNotice extends StatelessWidget {
  const _AccountNotice({required this.signedIn, required this.hasAccounts});

  final bool signedIn;
  final bool hasAccounts;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SectionCard(
      padding: const EdgeInsets.all(14),
      borderColor: const Color(0xFFF59E0B),
      borderWidth: 1.2,
      child: Text(
        hasAccounts
            ? 'Sign in with an UrbanPulse account so your SOS reaches people nearby and you receive theirs. The emergency numbers below always work.'
            : 'This build has no accounts, so SOS alerts cannot reach anyone. Use the emergency numbers below.',
      ),
    ),
  );
}

// --- your SOS ----------------------------------------------------------------------

class _OwnSos extends StatelessWidget {
  const _OwnSos({required this.sos, required this.category, required this.onCategory, required this.onResolve});

  final SosController sos;
  final SosCategory category;
  final ValueChanged<SosCategory> onCategory;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (sos.phase == SosPhase.idle) {
      return SectionCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Text('In danger or need urgent help?', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              sos.triggerSupported
                  ? 'Press the power button 3 times quickly, from anywhere, even with the app closed. Or hold the button below.'
                  : 'Hold the button below to alert UrbanPulse users near you.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            _HoldButton(onFire: () => sos.trigger(category: category)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final c in SosCategory.values)
                  ChoiceChip(label: Text(c.label), selected: c == category, onSelected: (_) => onCategory(c)),
              ],
            ),
          ],
        ),
      );
    }

    final since = sos.startedAt ?? sos.mine?.createdAt;
    final fix = sos.lastFix;
    final (title, subtitle) = switch (sos.phase) {
      SosPhase.sending => ('Sending your SOS…', sos.syncProblem ?? 'Getting your location and alerting people near you.'),
      SosPhase.resolving => ('Ending your SOS…', sos.syncProblem ?? 'Telling people nearby that you are safe.'),
      _ => (
        'SOS active',
        sos.syncProblem ??
            (sos.responders > 0
                ? '${sos.responders} ${sos.responders == 1 ? 'person is' : 'people are'} on the way.'
                : 'UrbanPulse users within a few km can see where you are.'),
      ),
    };
    return SectionCard(
      padding: const EdgeInsets.all(18),
      borderColor: _red,
      borderWidth: 1.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _Pulse(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleLarge?.copyWith(color: _red, fontWeight: FontWeight.w900)),
                    if (since != null) Text('${sos.category.label} · since ${clock12(since)}', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(subtitle, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(fix == null ? Icons.location_off_rounded : Icons.my_location_rounded, size: 16, color: fix == null ? _red : theme.colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fix == null
                      ? switch (sos.locationIssue) {
                          LocationIssue.denied => 'Location is off for UrbanPulse, so helpers cannot see where you are. Allow it below.',
                          LocationIssue.serviceOff => 'Location is switched off on this phone. Turn it on so helpers can find you.',
                          _ => 'Still looking for your location…',
                        }
                      : 'Location ${fix.lat.toStringAsFixed(5)}, ${fix.lng.toStringAsFixed(5)}${fix.accuracyM == null ? '' : ' (±${fix.accuracyM!.round()} m)'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (sos.phase != SosPhase.resolving)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A), padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: onResolve,
                icon: const Icon(Icons.verified_user_rounded),
                label: const Text("I'm safe: end SOS"),
              ),
            ),
        ],
      ),
    );
  }
}

/// Hold for 1.5 s to raise an SOS, so a stray tap never does.
class _HoldButton extends StatefulWidget {
  const _HoldButton({required this.onFire});

  final Future<void> Function() onFire;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        unawaited(HapticFeedback.heavyImpact());
        _hold.reset();
        unawaited(widget.onFire());
      }
    });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Hold to send SOS',
    child: GestureDetector(
      onTapDown: (_) => _hold.forward(),
      onTapUp: (_) => _hold.reverse(),
      onTapCancel: () => _hold.reverse(),
      child: AnimatedBuilder(
        animation: _hold,
        builder: (context, _) => SizedBox(
          width: 170,
          height: 170,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(value: _hold.value, strokeWidth: 8, color: Colors.white, backgroundColor: _red.withValues(alpha: 0.25)),
              ),
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _red,
                  boxShadow: [BoxShadow(color: _red.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: 2)],
                ),
                alignment: Alignment.center,
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('SOS', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900)),
                    Text('HOLD', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
    child: const CircleAvatar(radius: 22, backgroundColor: _red, child: Icon(Icons.sos_rounded, color: Colors.white)),
  );
}

// --- emergency numbers -------------------------------------------------------------

class _EmergencyNumbers extends StatelessWidget {
  const _EmergencyNumbers({required this.onCall});

  final ValueChanged<String> onCall;

  @override
  Widget build(BuildContext context) => SectionCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Emergency numbers (India)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (n, label) in const [('112', 'All emergencies'), ('108', 'Ambulance'), ('1091', "Women's helpline")])
              OutlinedButton.icon(onPressed: () => onCall(n), icon: const Icon(Icons.call_rounded, size: 18), label: Text('$n · $label')),
          ],
        ),
      ],
    ),
  );
}

// --- power button ------------------------------------------------------------------

class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.sos});

  final SosController sos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final st = sos.nativeStatus;
    final on = sos.triggerEnabled;
    final running = sos.triggerRunning;
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: on,
            onChanged: sos.signedIn ? sos.setTriggerEnabled : null,
            title: const Text('Power-button SOS', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              !on
                  ? 'Off. Turn on to send an SOS by pressing the power button 3 times quickly.'
                  : running
                  ? 'On: 3 quick presses of the power button send an SOS, even when the app is closed.'
                  : 'Not running yet. Allow location and notifications below.',
            ),
          ),
          if (on) ...[
            _Check(
              ok: sos.locationIssue != LocationIssue.denied,
              label: 'Location allowed (so helpers can find you)',
              action: 'Allow',
              onTap: sos.askLocation,
            ),
            _Check(ok: st['notifications'] ?? false, label: 'Notifications allowed (SOS status and alerts)', action: 'Allow', onTap: sos.requestNotifications),
            _Check(
              ok: st['batteryUnrestricted'] ?? false,
              label: 'Battery unrestricted (so Android does not stop the watch)',
              action: 'Open',
              onTap: sos.openBatterySettings,
            ),
            const SizedBox(height: 6),
            Text(
              'Some phones (Vivo, Oppo, Xiaomi) also need "Autostart" or "Allow background activity" turned on for UrbanPulse in the phone settings.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.ok, required this.label, required this.action, required this.onTap});

  final bool ok;
  final String label;
  final String action;
  final Future<Object?> Function() onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded, size: 18, color: ok ? const Color(0xFF16A34A) : const Color(0xFFF59E0B)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        if (!ok) TextButton(onPressed: () => unawaited(onTap()), child: Text(action)),
      ],
    ),
  );
}

// --- nearby --------------------------------------------------------------------------

class _Nearby extends StatelessWidget {
  const _Nearby({required this.sos, required this.responded, required this.onNavigate, required this.onRespond});

  final SosController sos;
  final Set<String> responded;
  final ValueChanged<SosEvent> onNavigate;
  final ValueChanged<SosEvent> onRespond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = sos.nearby;
    final status = sos.nearbyProblem ??
        (!sos.signedIn
            ? 'Sign in to receive SOS alerts from people near you.'
            : sos.live
            ? 'Live: new alerts appear instantly.'
            : 'Checking every minute${sos.lastChecked == null ? '' : ' (last ${clock12(sos.lastChecked!)})'}.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('SOS near you', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            DropdownButton<double>(
              value: const [2.0, 5.0, 10.0, 25.0].contains(sos.radiusKm) ? sos.radiusKm : 5.0,
              underline: const SizedBox.shrink(),
              items: [for (final km in const [2.0, 5.0, 10.0, 25.0]) DropdownMenuItem(value: km, child: Text('within ${km.round()} km'))],
              onChanged: sos.signedIn ? (v) => v == null ? null : unawaited(sos.setRadius(v)) : null,
            ),
          ],
        ),
        Row(
          children: [
            Icon(sos.live ? Icons.wifi_tethering_rounded : Icons.sync_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(child: Text(status, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          ],
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          SectionCard(
            padding: const EdgeInsets.all(16),
            child: Text(sos.signedIn ? 'No one near you needs help right now.' : 'Alerts from people nearby appear here.', style: theme.textTheme.bodyMedium),
          ),
        for (final e in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _NearbyCard(
              e: e,
              distance: sos.distanceKm(e),
              responded: responded.contains(e.id),
              onNavigate: () => onNavigate(e),
              onRespond: () => onRespond(e),
            ),
          ),
      ],
    );
  }
}

class _NearbyCard extends StatelessWidget {
  const _NearbyCard({required this.e, required this.distance, required this.responded, required this.onNavigate, required this.onRespond});

  final SosEvent e;
  final double? distance;
  final bool responded;
  final VoidCallback onNavigate;
  final VoidCallback onRespond;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = DateTime.now().difference(e.updatedAt);
    return SectionCard(
      padding: const EdgeInsets.all(14),
      borderColor: _red,
      borderWidth: 1.2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(radius: 18, backgroundColor: _red, child: Icon(Icons.sos_rounded, color: Colors.white, size: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e.name} · ${e.category.label}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      [
                        'since ${clock12(e.createdAt)}',
                        if (quiet.inMinutes >= 5) 'last update ${quiet.inMinutes} min ago' else 'updating live',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (distance != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _red.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                  child: Text(SosController.distanceLabel(distance!), style: const TextStyle(color: _red, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: _red),
                onPressed: e.hasLocation ? onNavigate : null,
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: const Text('Navigate'),
              ),
              OutlinedButton.icon(
                onPressed: responded ? null : onRespond,
                icon: Icon(responded ? Icons.check_rounded : Icons.directions_run_rounded, size: 18),
                label: Text(responded ? 'On your way' : "I'm on my way"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
