import 'package:flutter/material.dart';

import '../../core/safe_launch.dart';
import '../../agents/runtime/agent_kind.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import 'day_view.dart' show levelColor;

IconData _levelIcon(SupportLevel l) => switch (l) {
  SupportLevel.yes => Icons.check_circle_rounded,
  SupportLevel.partial => Icons.adjust_rounded,
  SupportLevel.no => Icons.cancel_rounded,
  SupportLevel.unknown => Icons.help_outline_rounded,
};

IconData _kindIcon(SlotKind k) => switch (k) {
  SlotKind.stay => Icons.hotel_rounded,
  SlotKind.visit => Icons.place_rounded,
  SlotKind.meal => Icons.restaurant_rounded,
  SlotKind.transit => Icons.directions_transit_rounded,
  SlotKind.rest => Icons.hourglass_bottom_rounded,
};

/// Saksham's audit: does every step of the trip work for every need in the group?
class AccessAuditView extends StatelessWidget {
  const AccessAuditView({required this.audit, required this.needs, super.key});

  final AccessibilityAudit audit;
  final Set<AccessibilityNeed> needs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overall = audit.overall;
    final color = levelColor(context, overall);
    final headline = switch (overall) {
      SupportLevel.yes => 'Every step suits your group',
      SupportLevel.partial => 'Mostly suitable, with things to confirm',
      SupportLevel.no => 'Some steps do not suit your group',
      SupportLevel.unknown => 'Not enough is known yet',
    };
    final counts = {
      for (final l in SupportLevel.values) l: audit.items.where((i) => i.overall == l).length,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withValues(alpha: 0.45))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_levelIcon(overall), color: color),
                  const SizedBox(width: 10),
                  Expanded(child: Text(headline, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Saksham checked ${audit.items.length} steps (the stay, the journey there and back, each place and each way of getting around) '
                'for ${needs.map((n) => n.label.toLowerCase()).join(', ')}.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  for (final l in [SupportLevel.yes, SupportLevel.partial, SupportLevel.unknown, SupportLevel.no])
                    if (counts[l]! > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_levelIcon(l), size: 14, color: levelColor(context, l)),
                          const SizedBox(width: 4),
                          Text('${counts[l]} ${l.label.toLowerCase()}', style: theme.textTheme.labelMedium),
                        ],
                      ),
                ],
              ),
            ],
          ),
        ),
        if (audit.actionsRequired.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.checklist_rounded, size: 18, color: AgentKind.saksham.color),
              const SizedBox(width: 8),
              Text('Confirm before you go', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: AgentKind.saksham.color)),
            ],
          ),
          const SizedBox(height: 6),
          for (final a in audit.actionsRequired)
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
        const SizedBox(height: 16),
        for (final item in audit.items) _ItemCard(item: item),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final AuditItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final overall = item.overall;
    final color = levelColor(context, overall);
    // The card's colour is painted by a Material, so the tile's ink shows on it.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          leading: Icon(_kindIcon(item.kind), color: color),
          title: Text(item.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${overall.label}${item.action == null ? '' : ' · ${item.action}'}',
            style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
          children: [
            for (final c in item.checks)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(c.need.emoji, style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(c.need.label, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700))),
                        Icon(_levelIcon(c.level), size: 15, color: levelColor(context, c.level)),
                        const SizedBox(width: 4),
                        Text(c.level.label, style: theme.textTheme.labelSmall?.copyWith(color: levelColor(context, c.level), fontWeight: FontWeight.w700)),
                      ],
                    ),
                    if (c.detail.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(c.detail, style: theme.textTheme.bodySmall)),
                    _Provenance(support: c),
                  ],
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}

class _Provenance extends StatelessWidget {
  const _Provenance({required this.support});

  final NeedSupport support;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = support.provenance;
    if (support.level == SupportLevel.unknown && p.source == 'none') return const SizedBox.shrink();
    final text = p.isEstimated ? 'AI-estimated, not verified' : 'Source: ${p.source}';
    final style = theme.textTheme.labelSmall?.copyWith(
      color: p.url == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary,
      fontStyle: p.isEstimated ? FontStyle.italic : null,
    );
    if (p.url == null) return Text(text, style: style);
    return InkWell(
      onTap: () => openWebLink(p.url),
      child: Text(text, style: style),
    );
  }
}
