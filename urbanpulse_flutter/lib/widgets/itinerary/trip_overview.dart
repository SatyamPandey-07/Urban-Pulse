import 'package:flutter/material.dart';

import '../../core/safe_launch.dart';
import '../../agents/runtime/agent_kind.dart';
import '../../agents/safar/transport_planner.dart';
import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../yatri/claims_view.dart';
import '../yatri/hotel_choice_view.dart' show NeedChip;
import '../yatri/route_map_card.dart' show transportModeIcon;

/// The trip at a glance: the stay, the journey, how much of it rests on real
/// data, what was assumed, and where every fact came from.
class TripOverview extends StatelessWidget {
  const TripOverview({required this.itinerary, super.key});

  final Itinerary itinerary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final needs = {for (final n in itinerary.brief?.accessibilityNeeds ?? const <AccessibilityNeed>{}) if (n != AccessibilityNeed.none) n};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Confidence(value: itinerary.confidence),
        const SizedBox(height: 16),
        _Heading(icon: Icons.hotel_rounded, color: AgentKind.atithi.color, text: 'Where you stay'),
        if (itinerary.hotel == null)
          Text('No stay is included in this plan.', style: theme.textTheme.bodyMedium)
        else
          _HotelCard(hotel: itinerary.hotel!, needs: needs),
        if (itinerary.hotelAlternatives.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Other stays considered', style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
          for (final h in itinerary.hotelAlternatives.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${h.name}${h.nightlyInr == null ? '' : ' · ${h.priceIsEstimated ? '≈ ' : ''}${rupees(h.nightlyInr!)} a night'}${h.rating == null ? '' : ' · ★ ${h.rating!.toStringAsFixed(1)}'}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
        const SizedBox(height: 20),
        _Heading(icon: Icons.directions_transit_rounded, color: AgentKind.safar.color, text: 'Getting there'),
        if (itinerary.transportOptions.isEmpty)
          Text('No long-distance travel is planned.', style: theme.textTheme.bodyMedium)
        else
          for (final l in itinerary.transportOptions)
            _LegTile(leg: l, chosen: itinerary.chosenTransport?.id == l.id, needs: needs),
        if (itinerary.timings.isNotEmpty) ...[
          const SizedBox(height: 20),
          _Heading(icon: Icons.timer_outlined, color: AgentKind.yatri.color, text: 'How this plan was made'),
          Text(
            'The agents worked side by side for about ${itinerary.timings['total'] ?? 0} seconds (time spent waiting for your answers is not counted).',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final e in itinerary.timings.entries)
                if (e.key != 'total')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: _agentColor(e.key).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${e.key} ${e.value}s',
                      style: theme.textTheme.labelSmall?.copyWith(color: _agentColor(e.key), fontWeight: FontWeight.w700),
                    ),
                  ),
            ],
          ),
        ],
        if (itinerary.assumptions.isNotEmpty) ...[
          const SizedBox(height: 20),
          _Heading(icon: Icons.rule_rounded, color: AppColors.solidWarning, text: 'What this plan assumes'),
          for (final a in itinerary.assumptions)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 6, right: 8), child: Icon(Icons.circle, size: 5)),
                  Expanded(child: Text(a, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
        ],
        if (itinerary.sources.isNotEmpty) ...[
          const SizedBox(height: 20),
          _Heading(icon: Icons.link_rounded, color: AgentKind.khoji.color, text: 'Sources'),
          for (final s in itinerary.sources.take(30))
            InkWell(
              onTap: () => openWebLink(s.url),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.open_in_new_rounded, size: 14, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${s.title}${s.source.isEmpty ? '' : ' · ${s.source}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

Color _agentColor(String displayName) {
  for (final a in AgentKind.values) {
    if (a.displayName == displayName) return a.color;
  }
  return AppColors.textTertiary;
}

class _Heading extends StatelessWidget {
  const _Heading({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color))),
      ],
    ),
  );
}

class _Confidence extends StatelessWidget {
  const _Confidence({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = value >= 0.75 ? 'Mostly real data' : (value >= 0.5 ? 'A mix of real data and estimates' : 'Mostly estimates');
    final color = value >= 0.75 ? AppColors.primaryGreenDark : (value >= 0.5 ? AppColors.solidWarning : scheme.error);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(value: value, strokeWidth: 5, color: color, backgroundColor: color.withValues(alpha: 0.2)),
                Text('${(value * 100).round()}', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(
                  'How much of this plan rests on real prices, places and forecasts rather than estimates.',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HotelCard extends StatelessWidget {
  const _HotelCard({required this.hotel, required this.needs});

  final HotelOption hotel;
  final Set<AccessibilityNeed> needs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hotel.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            [
              hotel.type,
              if (hotel.rating != null) '★ ${hotel.rating!.toStringAsFixed(1)}${hotel.reviewCount == null ? '' : ' (${grouped(hotel.reviewCount!)})'}',
              if (hotel.distanceToCenterKm != null) '${hotel.distanceToCenterKm} km from centre',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (hotel.nightlyInr != null) ...[
            const SizedBox(height: 8),
            Text(
              '${hotel.priceIsEstimated ? '≈ ' : ''}${rupees(hotel.nightlyInr!)} a night'
              '${hotel.cheapestOta != null && !hotel.priceIsEstimated ? ' via ${hotel.cheapestOta}' : ''}'
              '${hotel.priceIsEstimated ? ' (estimate)' : ''}',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
          if (needs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final n in needs) NeedChip(need: n, support: hotel.access[n])]),
          ],
          if (hotel.amenities.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(hotel.amenities.join(' · '), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          if (hotel.claims.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClaimsView(claims: hotel.claims),
          ],
        ],
      ),
    );
  }
}

class _LegTile extends StatelessWidget {
  const _LegTile({required this.leg, required this.chosen, required this.needs});

  final TransportLeg leg;
  final bool chosen;
  final Set<AccessibilityNeed> needs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: chosen ? scheme.primary.withValues(alpha: 0.08) : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: chosen ? scheme.primary : scheme.outlineVariant, width: chosen ? 1.6 : 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(transportModeIcon(leg.mode), color: AgentKind.safar.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(leg.mode.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (chosen) ...[
                      const SizedBox(width: 8),
                      Text('planned', style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary, fontWeight: FontWeight.w800)),
                    ],
                  ],
                ),
                Text(
                  '${durationLabel(leg.durationMin)} · ${rupees(leg.costInr)} · ${fixed(leg.co2Grams / 1000, 0)} kg CO₂ (each way, estimated)',
                  style: theme.textTheme.bodySmall,
                ),
                if (leg.note != null && leg.note!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(leg.note!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
