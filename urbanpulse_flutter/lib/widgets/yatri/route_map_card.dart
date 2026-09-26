import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../domain/route_path.dart';
import '../../models/trip_brief.dart';
import '../../models/yatri_question.dart';
import 'option_card.dart';

IconData transportModeIcon(TripTransportMode mode) => switch (mode) {
  TripTransportMode.flight => Icons.flight,
  TripTransportMode.train => Icons.train,
  TripTransportMode.metroLocal => Icons.subway,
  TripTransportMode.eBus || TripTransportMode.bus => Icons.directions_bus,
  TripTransportMode.sharedEv || TripTransportMode.carTaxi => Icons.local_taxi,
  TripTransportMode.selfDriveEv => Icons.electric_car,
};

/// The route preview shown once the origin and destination are fixed: both
/// places on an OpenStreetMap map, joined by a line that draws itself. Picking
/// a transport mode restyles it — a curved flight arc with a plane, a dashed
/// rail line with a train, a road line with a cab or bus.
class RouteMapCard extends StatefulWidget {
  const RouteMapCard({
    required this.origin,
    required this.destination,
    required this.originName,
    required this.destinationName,
    required this.modes,
    required this.shown,
    required this.onShow,
    this.tileLayer,
    super.key,
  });

  final LatLng origin;
  final LatLng destination;
  final String originName;
  final String destinationName;

  /// The transport modes the traveller has selected, to preview one by one.
  final List<TripTransportMode> modes;

  /// The mode currently drawn, or null before any is chosen.
  final TripTransportMode? shown;
  final ValueChanged<TripTransportMode> onShow;

  /// Overrides the OpenStreetMap tiles (tests pass an empty layer so no
  /// network is touched).
  final Widget? tileLayer;

  @override
  State<RouteMapCard> createState() => _RouteMapCardState();
}

class _RouteMapCardState extends State<RouteMapCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..forward();

  @override
  void didUpdateWidget(RouteMapCard old) {
    super.didUpdateWidget(old);
    if (old.shown != widget.shown ||
        old.origin != widget.origin ||
        old.destination != widget.destination) {
      _draw.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  /// The part of [path] drawn so far, ending exactly at the moving head.
  List<LatLng> _partial(List<LatLng> path, double t) {
    final at = t * (path.length - 1);
    final whole = at.floor().clamp(0, path.length - 1);
    final out = path.sublist(0, whole + 1);
    if (whole < path.length - 1) {
      final frac = at - whole;
      final a = path[whole];
      final b = path[whole + 1];
      out.add(
        LatLng(
          a.latitude + (b.latitude - a.latitude) * frac,
          a.longitude + (b.longitude - a.longitude) * frac,
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = RouteStyles.styleFor(widget.shown);
    final path = routePath(widget.origin, widget.destination, style);
    final pattern = style == RouteStyle.dashed
        ? StrokePattern.dashed(segments: const [10, 8])
        : const StrokePattern.solid();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
            child: Row(
              children: [
                Icon(Icons.route_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.originName} to ${widget.destinationName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Replay route',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _draw.forward(from: 0),
                  icon: Icon(Icons.replay_rounded, size: 20, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final height = c.maxWidth >= 560 ? 300.0 : 220.0;
              return ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: height,
                  child: FlutterMap(
                    // A new camera fit is needed when the route changes shape.
                    key: ValueKey(
                      '${widget.origin}-${widget.destination}-${style.name}',
                    ),
                    options: MapOptions(
                      initialCameraFit: CameraFit.coordinates(
                        coordinates: path,
                        padding: const EdgeInsets.fromLTRB(56, 64, 56, 40),
                        maxZoom: 12,
                      ),
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      widget.tileLayer ??
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.urbanpulse.app',
                          ),
                      AnimatedBuilder(
                        animation: _draw,
                        builder: (context, _) {
                          final t = Curves.easeInOutCubic.transform(_draw.value);
                          final drawn = _partial(path, t);
                          final head = drawn.last;
                          final prev = drawn.length > 1
                              ? drawn[drawn.length - 2]
                              : widget.origin;
                          final mode = widget.shown;
                          return Stack(
                            children: [
                              PolylineLayer(
                                polylines: [
                                  // The full route, faint, so the target is visible.
                                  Polyline(
                                    points: path,
                                    strokeWidth: 3,
                                    color: scheme.primary.withValues(alpha: 0.22),
                                    pattern: pattern,
                                  ),
                                  Polyline(
                                    points: drawn,
                                    strokeWidth: 4.5,
                                    color: scheme.primary,
                                    pattern: pattern,
                                  ),
                                ],
                              ),
                              MarkerLayer(
                                markers: [
                                  _placeMarker(
                                    context,
                                    widget.origin,
                                    widget.originName,
                                    Icons.trip_origin,
                                  ),
                                  _placeMarker(
                                    context,
                                    widget.destination,
                                    widget.destinationName,
                                    Icons.location_on,
                                  ),
                                  if (mode != null)
                                    Marker(
                                      point: head,
                                      width: 38,
                                      height: 38,
                                      child: _VehicleMarker(
                                        icon: transportModeIcon(mode),
                                        // Planes point along their heading.
                                        angleRadians: mode == TripTransportMode.flight
                                            ? bearingDegrees(prev, head) * math.pi / 180
                                            : 0,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      // Required credit for OpenStreetMap tiles. (flutter_map's own
                      // attribution row overflows on narrow cards.)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          margin: const EdgeInsets.all(6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '© OpenStreetMap contributors',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          if (widget.modes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in widget.modes)
                  OptionPill(
                    option: QuestionOption(id: m.name, label: m.label),
                    selected: widget.shown == m,
                    onTap: () => widget.onShow(m),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Marker _placeMarker(
    BuildContext context,
    LatLng point,
    String name,
    IconData icon,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Marker(
      point: point,
      width: 132,
      height: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1)),
              ],
            ),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ),
          Icon(icon, size: 24, color: scheme.primary),
        ],
      ),
    );
  }
}

class _VehicleMarker extends StatelessWidget {
  const _VehicleMarker({required this.icon, required this.angleRadians});

  final IconData icon;
  final double angleRadians;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primary,
        border: Border.all(color: scheme.onPrimary, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Transform.rotate(
        angle: angleRadians,
        child: Icon(icon, size: 20, color: scheme.onPrimary),
      ),
    );
  }
}
