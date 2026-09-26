import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../agents/runtime/agent_kind.dart';
import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../yatri/route_map_card.dart' show transportModeIcon;

Color slotColor(SlotKind k) => switch (k) {
  SlotKind.stay => AgentKind.atithi.color,
  SlotKind.visit => AgentKind.bhatkanti.color,
  SlotKind.meal => AppColors.solidWarning,
  SlotKind.transit => AgentKind.safar.color,
  SlotKind.rest => AppColors.textTertiary,
};

IconData slotIcon(ItinerarySlot s) => switch (s.kind) {
  SlotKind.stay => Icons.hotel_rounded,
  SlotKind.visit => Icons.place_rounded,
  SlotKind.meal => Icons.restaurant_rounded,
  SlotKind.rest => Icons.hourglass_bottom_rounded,
  SlotKind.transit => s.leg == null
      ? Icons.directions_rounded
      : (s.leg!.walking ? Icons.directions_walk_rounded : transportModeIcon(s.leg!.mode)),
};

Color levelColor(BuildContext context, SupportLevel l) => switch (l) {
  SupportLevel.yes => AppColors.primaryGreenDark,
  SupportLevel.partial => AppColors.solidWarning,
  SupportLevel.no => Theme.of(context).colorScheme.error,
  SupportLevel.unknown => Theme.of(context).colorScheme.outline,
};

/// One day of the itinerary: a map of where the day goes, then the timeline.
class DayView extends StatelessWidget {
  const DayView({required this.day, required this.hotel, required this.needs, this.tileLayer, super.key});

  final ItineraryDay day;
  final HotelOption? hotel;
  final Set<AccessibilityNeed> needs;
  final Widget? tileLayer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visits = [for (final s in day.slots) if (s.kind == SlotKind.visit && s.location != null) s];
    final hasMap = visits.isNotEmpty || hotel?.location != null;

    final header = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 4,
        children: [
          Text(day.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          if (day.weather != null)
            _Pill(icon: Icons.cloud_outlined, text: day.weather!, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
    final timeline = _Timeline(day: day, needs: needs);
    final map = hasMap ? DayMap(day: day, hotel: hotel, tileLayer: tileLayer) : null;

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= 900 && map != null) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: Padding(padding: const EdgeInsets.only(right: 16), child: SizedBox(height: 520, child: map))),
              Expanded(flex: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [header, timeline])),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            if (map != null) ...[SizedBox(height: 220, child: map), const SizedBox(height: 14)],
            timeline,
          ],
        );
      },
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}

// --- map ------------------------------------------------------------------------

class DayMap extends StatelessWidget {
  const DayMap({required this.day, required this.hotel, this.tileLayer, super.key});

  final ItineraryDay day;
  final HotelOption? hotel;
  final Widget? tileLayer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visits = [for (final s in day.slots) if (s.kind == SlotKind.visit && s.location != null) s];
    final base = hotel?.location;
    final route = [if (base != null) base, for (final v in visits) v.location!, if (base != null && visits.isNotEmpty) base];
    final points = [if (base != null) base, for (final v in visits) v.location!];
    if (points.isEmpty) return const SizedBox.shrink();

    final options = points.length == 1
        ? MapOptions(
            initialCenter: points.first,
            initialZoom: 14,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom),
          )
        : MapOptions(
            initialCameraFit: CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(36), maxZoom: 15),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(18)),
        child: FlutterMap(
          options: options,
          children: [
            tileLayer ??
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.urbanpulse.app',
                ),
            if (route.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(points: route, strokeWidth: 3.5, color: AgentKind.raah.color.withValues(alpha: 0.75), pattern: StrokePattern.dashed(segments: const [8, 6])),
                ],
              ),
            MarkerLayer(
              markers: [
                if (base != null)
                  Marker(
                    point: base,
                    width: 34,
                    height: 34,
                    child: _Dot(color: AgentKind.atithi.color, child: const Icon(Icons.hotel_rounded, color: Colors.white, size: 17)),
                  ),
                for (var i = 0; i < visits.length; i++)
                  Marker(
                    point: visits[i].location!,
                    width: 34,
                    height: 34,
                    child: _Dot(
                      color: AgentKind.bhatkanti.color,
                      child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                  ),
              ],
            ),
            const Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Text('© OpenStreetMap', style: TextStyle(fontSize: 9, color: Color(0xFF444444))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4)],
    ),
    child: child,
  );
}

// --- timeline -------------------------------------------------------------------

class _Timeline extends StatelessWidget {
  const _Timeline({required this.day, required this.needs});

  final ItineraryDay day;
  final Set<AccessibilityNeed> needs;

  @override
  Widget build(BuildContext context) {
    if (day.slots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('A free day: nothing is planned, so explore at your own pace.', style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    var visitNo = 0;
    return Column(
      children: [
        for (var i = 0; i < day.slots.length; i++)
          _SlotRow(
            slot: day.slots[i],
            visitNumber: day.slots[i].kind == SlotKind.visit ? ++visitNo : null,
            isLast: i == day.slots.length - 1,
            needs: needs,
          ),
      ],
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.visitNumber, required this.isLast, required this.needs});

  final ItinerarySlot slot;
  final int? visitNumber;
  final bool isLast;
  final Set<AccessibilityNeed> needs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = slotColor(slot.kind);
    final compact = slot.kind == SlotKind.transit || slot.kind == SlotKind.rest;
    final minutes = slot.duration.inMinutes;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 62,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(clock12(slot.start), style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
            ),
          ),
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: compact ? 22 : 26,
                  height: compact ? 22 : 26,
                  margin: const EdgeInsets.only(top: 1),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: compact ? color.withValues(alpha: 0.16) : color, shape: BoxShape.circle),
                  child: visitNumber != null
                      ? Text('$visitNumber', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800))
                      : Icon(slotIcon(slot), size: compact ? 13 : 15, color: compact ? color : Colors.white),
                ),
                if (!isLast) Expanded(child: Container(width: 2, color: scheme.outlineVariant)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: compact ? 8 : 14),
              child: compact ? _compact(context, minutes) : _card(context, minutes),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compact(BuildContext context, int minutes) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final l = slot.leg;
    final bits = [
      '$minutes min',
      if (l != null && !l.walking && l.distanceKm >= 1) '${fixed(l.distanceKm, 0)} km',
      if (slot.costInr != null && slot.costInr! > 0) rupees(slot.costInr!),
      if (l != null && l.co2Grams > 0) '${fixed(l.co2Grams / 1000, 1)} kg CO₂',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(slot.title, style: theme.textTheme.bodySmall?.copyWith(color: muted, fontWeight: FontWeight.w600)),
          Text(bits.join(' · '), style: theme.textTheme.labelSmall?.copyWith(color: muted)),
          if (slot.note != null && slot.note!.isNotEmpty)
            Text(slot.note!, style: theme.textTheme.labelSmall?.copyWith(color: muted, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, int minutes) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(slot.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
              Text('${minutes >= 60 ? '${minutes ~/ 60}h ' : ''}${minutes % 60 == 0 && minutes >= 60 ? '' : '${minutes % 60}m'}'.trim(),
                  style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          if (slot.note != null && slot.note!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(slot.note!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          if (slot.costInr != null && slot.costInr! > 0 || slot.access != null || slot.flags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (slot.costInr != null && slot.costInr! > 0)
                  _Pill(icon: Icons.sell_outlined, text: rupees(slot.costInr!), color: scheme.onSurfaceVariant),
                if (slot.access != null)
                  _Pill(icon: Icons.accessible_forward_rounded, text: 'Access: ${slot.access!.label}', color: levelColor(context, slot.access!)),
                for (final f in slot.flags) _Pill(icon: Icons.info_outline_rounded, text: f, color: AppColors.solidWarning),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
