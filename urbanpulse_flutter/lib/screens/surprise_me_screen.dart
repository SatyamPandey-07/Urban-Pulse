import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../agents/runtime/agent_kind.dart';
import '../agents/yatri/surprise_me.dart';
import '../core/formatting.dart';
import '../services/location_service.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

/// Surprise Me: Yatri and the agents pick a short trip from what this
/// traveller's past trips say about them. "Plan this trip" hands the brief to
/// Yatri, who opens it for review and plans it with the whole team.
class SurpriseMeScreen extends StatefulWidget {
  const SurpriseMeScreen({required this.onPlan, super.key});

  /// Takes the chosen pick to Yatri (the caller switches to the Yatri tab).
  final void Function(SurprisePick pick) onPlan;

  @override
  State<SurpriseMeScreen> createState() => _SurpriseMeScreenState();
}

class _SurpriseMeScreenState extends State<SurpriseMeScreen> {
  final _done = <SurpriseStep, String>{};
  final _shown = <String>{};
  List<SurprisePick>? _picks;
  bool _running = false;

  static const _steps = [
    (SurpriseStep.profile, AgentKind.yatri, 'Reading your past trips'),
    (SurpriseStep.shortlist, AgentKind.bhatkanti, 'Shortlisting places within a weekend’s reach'),
    (SurpriseStep.weather, AgentKind.raah, 'Checking the weekend weather'),
    (SurpriseStep.budget, AgentKind.hisab, 'Estimating the cost'),
    (SurpriseStep.pick, AgentKind.yatri, 'Choosing three for you'),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_picks == null && !_running) unawaited(_run());
  }

  Future<void> _run() async {
    final services = AppScope.of(context);
    setState(() {
      _running = true;
      _done.clear();
      _picks = null;
    });
    final loc = services.location;
    final home = loc.hasFix ? LatLng(loc.latitude!, loc.longitude!) : const LatLng(LocationService.defaultLat, LocationService.defaultLon);
    final profile = TravelProfile.from(
      home: loc.originCity ?? 'Mumbai',
      briefs: services.tripBriefs.getBriefs(),
      itineraries: services.itineraries.all(),
    );
    final tk = services.agentToolkit;
    final picks = await SurpriseMe(llm: tk.llm, forecast: tk.forecast).pick(
      profile,
      home: home,
      exclude: _shown,
      onStep: (step, detail) {
        if (mounted) setState(() => _done[step] = detail);
      },
    );
    if (!mounted) return;
    _shown.addAll(picks.map((p) => p.place.name));
    setState(() {
      _picks = picks;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picks = _picks;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Surprise me'),
        actions: [
          if (picks != null)
            TextButton.icon(onPressed: _running ? null : _run, icon: const Icon(Icons.shuffle_rounded), label: const Text('Three more')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Yatri and the agents pick a short trip for the coming weekend from the trips you have planned before: '
            'your style, pace, group, access needs and budget.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          SectionCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                for (final (step, agent, label) in _steps)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(radius: 14, backgroundColor: agent.color.withValues(alpha: 0.18), child: Icon(agent.icon, size: 16, color: agent.color)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${agent.displayName} · $label', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                              if (_done[step] != null) Text(_done[step]!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _done[step] != null
                            ? const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF10B981))
                            : (_running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const SizedBox(width: 16)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (picks != null && picks.isEmpty)
            const EmptyState(icon: Icons.travel_explore_rounded, message: 'No short trips fit right now. Try again later.'),
          if (picks != null)
            LayoutBuilder(
              builder: (context, box) {
                final cards = [for (final p in picks) _PickCard(pick: p, onPlan: () => widget.onPlan(p))];
                if (box.maxWidth < 900) {
                  return Column(children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 14), child: c)]);
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, c) in cards.indexed) ...[if (i > 0) const SizedBox(width: 14), Expanded(child: c)],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({required this.pick, required this.onPlan});

  final SurprisePick pick;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final b = pick.brief;
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(pick.place.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              Text(pick.place.state, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Chip(Icons.route_rounded, '${pick.distanceKm} km'),
              _Chip(Icons.nights_stay_rounded, '${pick.nights + 1} days · ${shortDate(b.start!)}'),
              _Chip(Icons.payments_rounded, '≈ ${rupees(pick.estimateInr)}'),
              if (pick.weather != null) _Chip(pick.rainy ? Icons.umbrella_rounded : Icons.wb_sunny_rounded, pick.weather!),
            ],
          ),
          const SizedBox(height: 10),
          Text(pick.why, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          for (final h in pick.highlights)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $h', style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(onPressed: onPlan, icon: const Icon(Icons.auto_awesome_rounded), label: const Text('Plan this trip')),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 4),
          Flexible(child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
