import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/formatting.dart';
import '../../models/map_route.dart';
import '../../state/live_map_controller.dart';

/// A rounded card that sits under the map.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 12,
      color: scheme.surface,
      shadowColor: Colors.black54,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 14), child: child),
    );
  }
}

/// Picks the panel for what the traveller is doing.
class MapBottomPanel extends StatelessWidget {
  const MapBottomPanel({required this.controller, super.key});

  final LiveMapController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        Widget? panel;
        if (c.navigating) {
          panel = NavigationPanel(controller: c);
        } else if (c.selected != null && (c.routing != RoutingStatus.idle)) {
          panel = DirectionsPanel(controller: c);
        } else if (c.selected != null) {
          panel = PlacePanel(controller: c);
        } else if (c.tripActive && c.category == null) {
          panel = TripPanel(controller: c);
        } else if (c.category != null && (c.results.isNotEmpty || c.searchMessage != null)) {
          panel = ResultsCarousel(controller: c);
        }
        return AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.bottomCenter,
          child: panel == null ? const SizedBox(width: double.infinity) : _Sheet(child: panel),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------------

/// The chosen place: what it is, how far, and what to do about it.
class PlacePanel extends StatelessWidget {
  const PlacePanel({required this.controller, super.key});

  final LiveMapController controller;

  @override
  Widget build(BuildContext context) {
    final p = controller.selected!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isPin = p.category == 'pin';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  if (p.address.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(p.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
                ],
              ),
            ),
            IconButton(tooltip: 'Close', onPressed: controller.clearSelection, icon: const Icon(Icons.close_rounded)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (!isPin && p.distanceMeters > 0) _Tag(icon: Icons.near_me_rounded, text: '${distanceLabel(p.distanceMeters)} away'),
            if (!isPin && (p.category ?? '').isNotEmpty) _Tag(icon: Icons.category_rounded, text: _pretty(p.category!)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: FilledButton.icon(onPressed: controller.directions, icon: const Icon(Icons.directions_rounded), label: const Text('Directions'))),
            if ((p.phone ?? '').trim().isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton.outlined(tooltip: 'Call', onPressed: () => _call(p.phone!), icon: const Icon(Icons.call_rounded)),
            ],
          ],
        ),
      ],
    );
  }

  static String _pretty(String s) => s.replaceAll('_', ' ').split(RegExp(r'[,;]')).first.trim();

  static Future<void> _call(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: digits));
    } catch (_) {}
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: scheme.onSurfaceVariant), const SizedBox(width: 5), Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)))]),
    );
  }
}

// ---------------------------------------------------------------------------------

/// Category results as a strip of cards under the map.
class ResultsCarousel extends StatelessWidget {
  const ResultsCarousel({required this.controller, super.key});

  final LiveMapController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cat = c.category!;
    if (c.results.isEmpty) {
      return Row(children: [Icon(cat.icon, color: cat.color), const SizedBox(width: 10), Expanded(child: Text(c.searchMessage ?? '', style: theme.textTheme.bodyMedium)), IconButton(tooltip: 'Close', onPressed: c.clearResults, icon: const Icon(Icons.close_rounded))]);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(cat.icon, color: cat.color, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('${cat.label} nearby · ${c.results.length}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(visualDensity: VisualDensity.compact, tooltip: 'Close', onPressed: c.clearResults, icon: const Icon(Icons.close_rounded)),
          ],
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: c.results.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final p = c.results[i];
              return SizedBox(
                width: 230,
                child: Material(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => c.select(p),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          if (p.address.isNotEmpty) Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                          const Spacer(),
                          Text(distanceLabel(p.distanceMeters), style: TextStyle(color: cat.color, fontWeight: FontWeight.w800, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------

/// The ways to get to the chosen place, side by side.
class DirectionsPanel extends StatefulWidget {
  const DirectionsPanel({required this.controller, super.key});

  final LiveMapController controller;

  @override
  State<DirectionsPanel> createState() => _DirectionsPanelState();
}

class _DirectionsPanelState extends State<DirectionsPanel> {
  bool _steps = false;

  LiveMapController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dest = c.selected!;
    final chosen = c.selectedRoute;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('To ${dest.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(tooltip: 'Close directions', onPressed: c.closeDirections, icon: const Icon(Icons.close_rounded)),
          ],
        ),
        SegmentedButton<NavMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: NavMode.drive, icon: Icon(Icons.directions_car_rounded), label: Text('Drive')),
            ButtonSegment(value: NavMode.walk, icon: Icon(Icons.directions_walk_rounded), label: Text('Walk')),
          ],
          selected: {c.mode},
          onSelectionChanged: (s) => c.setMode(s.first),
        ),
        const SizedBox(height: 12),
        if (c.routing == RoutingStatus.loading)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const LinearProgressIndicator(), const SizedBox(height: 8), Text('Measuring routes…', style: theme.textTheme.bodySmall)])
        else if (c.routing == RoutingStatus.failed)
          Row(
            children: [
              Icon(Icons.info_outline_rounded, color: scheme.error),
              const SizedBox(width: 10),
              Expanded(child: Text(c.routingMessage ?? 'No route could be measured.', style: theme.textTheme.bodyMedium)),
              TextButton(onPressed: c.directions, child: const Text('Retry')),
            ],
          )
        else if (chosen != null) ...[
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: c.routes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _RouteCard(route: c.routes[i], selected: c.routes[i].id == chosen.id, fastest: i == 0 && c.routes.length > 1, onTap: () => c.selectRoute(c.routes[i].id)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              if (chosen.mode == NavMode.drive) 'CO₂ is an estimate for a petrol car.',
              'Measured by ${chosen.source}${chosen.trafficAware ? ', with live traffic' : ''}.',
            ].join(' '),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (_steps && chosen.instructions.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 170),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: chosen.instructions.length,
                itemBuilder: (context, i) {
                  final s = chosen.instructions[i];
                  return ListTile(dense: true, visualDensity: VisualDensity.compact, contentPadding: EdgeInsets.zero, leading: Icon(maneuverIcon(s.kind), size: 20), title: Text(s.text), trailing: Text(distanceLabel(s.atMeters), style: theme.textTheme.bodySmall));
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              if (chosen.instructions.isNotEmpty) Expanded(child: OutlinedButton.icon(onPressed: () => setState(() => _steps = !_steps), icon: Icon(_steps ? Icons.expand_more_rounded : Icons.list_rounded), label: Text(_steps ? 'Hide steps' : 'Steps'))),
              if (chosen.instructions.isNotEmpty) const SizedBox(width: 10),
              Expanded(flex: 2, child: FilledButton.icon(onPressed: c.startNavigation, icon: const Icon(Icons.navigation_rounded), label: const Text('Start'))),
            ],
          ),
        ],
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route, required this.selected, required this.fastest, required this.onTap});

  final MapRoute route;
  final bool selected;
  final bool fastest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${route.label}, ${minutesLabel(route.minutes)}, ${distanceLabel(route.distanceM)}',
      child: Material(
        color: selected ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            width: 150,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 2)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [if (route.label == 'Eco') Icon(Icons.eco_rounded, size: 14, color: scheme.primary), if (route.label == 'Eco') const SizedBox(width: 4), Flexible(child: Text(route.label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)))]),
                const SizedBox(height: 2),
                Text(minutesLabel(route.minutes), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                const Spacer(),
                Text(
                  '${distanceLabel(route.distanceM)}${route.mode == NavMode.drive ? ' · ≈${_co2(route.estimatedCo2Grams)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _co2(int g) => g >= 1000 ? '${(g / 1000).toStringAsFixed(1)} kg CO₂' : '$g g CO₂';
}

// ---------------------------------------------------------------------------------

IconData maneuverIcon(ManeuverKind k) => switch (k) {
  ManeuverKind.depart => Icons.trip_origin_rounded,
  ManeuverKind.straight => Icons.arrow_upward_rounded,
  ManeuverKind.slightLeft => Icons.turn_slight_left_rounded,
  ManeuverKind.left => Icons.turn_left_rounded,
  ManeuverKind.sharpLeft => Icons.turn_sharp_left_rounded,
  ManeuverKind.slightRight => Icons.turn_slight_right_rounded,
  ManeuverKind.right => Icons.turn_right_rounded,
  ManeuverKind.sharpRight => Icons.turn_sharp_right_rounded,
  ManeuverKind.uTurn => Icons.u_turn_left_rounded,
  ManeuverKind.roundabout => Icons.roundabout_left_rounded,
  ManeuverKind.merge => Icons.merge_rounded,
  ManeuverKind.fork => Icons.fork_right_rounded,
  ManeuverKind.arrive => Icons.flag_rounded,
};

/// The next turn, across the top of the map while navigating.
class NavigationBanner extends StatelessWidget {
  const NavigationBanner({required this.controller, super.key});

  final LiveMapController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final p = c.progress;
        final scheme = Theme.of(context).colorScheme;
        final String text;
        final IconData icon;
        String? distance;
        if (p == null) {
          text = 'Finding your position…';
          icon = Icons.gps_not_fixed_rounded;
        } else if (p.arrived) {
          text = 'You have arrived';
          icon = Icons.flag_rounded;
        } else if (p.next != null) {
          text = p.next!.text;
          icon = maneuverIcon(p.next!.kind);
          distance = p.nextInM == null ? null : 'in ${distanceLabel(p.nextInM!)}';
        } else {
          text = 'Continue to ${c.selected?.name ?? 'your destination'}';
          icon = Icons.arrow_upward_rounded;
        }
        return Material(
          elevation: 6,
          color: scheme.primary,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 34, color: scheme.onPrimary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (distance != null) Text(distance, style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85), fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 17)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Time and distance left, and the way to stop.
class NavigationPanel extends StatelessWidget {
  const NavigationPanel({required this.controller, this.now, super.key});

  final LiveMapController controller;

  /// The clock, for the arrival time (tests set it).
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = c.progress;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final route = c.selectedRoute;
    final dest = c.selected?.name ?? 'your destination';
    if (p != null && p.arrived) {
      return Row(
        children: [
          Icon(Icons.flag_rounded, color: scheme.primary, size: 30),
          const SizedBox(width: 12),
          Expanded(child: Text('You have arrived at $dest', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          FilledButton(onPressed: () => c.stopNavigation(keepRoutes: false), child: const Text('Done')),
        ],
      );
    }
    final minutes = p == null ? route?.minutes : (p.remainingS / 60).ceil().clamp(1, 100000);
    final meters = p?.remainingM ?? route?.distanceM;
    final eta = minutes == null ? null : (now?.call() ?? DateTime.now()).add(Duration(minutes: minutes));
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(minutes == null ? '—' : minutesLabel(minutes), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: scheme.primary)),
              Text([if (meters != null) distanceLabel(meters), if (eta != null) 'arrive ${clock12(eta)}'].join(' · '), style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        IconButton(tooltip: c.voiceGuidance ? 'Mute voice directions' : 'Speak directions', onPressed: () => c.setVoiceGuidance(!c.voiceGuidance), icon: Icon(c.voiceGuidance ? Icons.volume_up_rounded : Icons.volume_off_rounded)),
        if (!c.following) IconButton.filledTonal(tooltip: 'Follow me', onPressed: c.recenter, icon: const Icon(Icons.my_location_rounded)),
        const SizedBox(width: 8),
        FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError), onPressed: c.stopNavigation, icon: const Icon(Icons.close_rounded), label: const Text('End')),
      ],
    );
  }
}

/// A day of the trip on the map: its stops in order, and the way to the next.
class TripPanel extends StatelessWidget {
  const TripPanel({required this.controller, super.key});

  final LiveMapController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final next = c.nextStopIndex;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.route_rounded, color: scheme.tertiary),
            const SizedBox(width: 8),
            Expanded(child: Text(c.tripTitle ?? 'Your trip', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(visualDensity: VisualDensity.compact, tooltip: 'Hide the trip', onPressed: c.clearTrip, icon: const Icon(Icons.close_rounded)),
          ],
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: c.tripStops.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final done = c.visitedStops.contains(i);
              return ActionChip(
                avatar: CircleAvatar(radius: 11, backgroundColor: done ? scheme.outline : scheme.tertiary, child: done ? Icon(Icons.check_rounded, size: 13, color: scheme.onTertiary) : Text('${i + 1}', style: TextStyle(fontSize: 11, color: scheme.onTertiary, fontWeight: FontWeight.w800))),
                label: Text(c.tripStops[i].name, overflow: TextOverflow.ellipsis),
                onPressed: () => c.selectStop(i),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        if (next == null)
          Row(children: [Icon(Icons.flag_rounded, color: scheme.primary), const SizedBox(width: 8), const Expanded(child: Text('You have been to every stop of this day.'))])
        else
          FilledButton.icon(
            onPressed: c.navigateToNextStop,
            icon: const Icon(Icons.navigation_rounded),
            label: Text('Navigate to ${c.tripStops[next].name}', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}
