import 'package:flutter/material.dart';

import '../../agents/runtime/agent_kind.dart';
import '../../models/itinerary/itinerary_parts.dart';

/// A one-line summary of what Khoji checked about a hotel or place.
class KhojiBadge extends StatelessWidget {
  const KhojiBadge({required this.claims, super.key});

  final List<Claim> claims;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confirmed = claims.where((c) => c.verdict == Verdict.confirmed).length;
    final contradicted = claims.where((c) => c.verdict == Verdict.contradicted).length;
    final reviews = claims.where((c) => c.isReviews).firstOrNull?.reviewQuotes.length ?? 0;
    final parts = [
      if (confirmed > 0) '$confirmed confirmed',
      if (contradicted > 0) '$contradicted contradicted',
      if (reviews > 0) '$reviews review${reviews == 1 ? '' : 's'}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    final color = contradicted > 0 ? theme.colorScheme.error : AgentKind.khoji.color;
    return Row(
      children: [
        Icon(AgentKind.khoji.icon, size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            'Khoji: ${parts.join(' · ')}',
            style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
