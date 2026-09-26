import 'package:flutter/material.dart';

import '../../agents/runtime/agent_kind.dart';
import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';

/// Hariyali's report: the plan's carbon footprint, what it saves against the
/// most polluting comparable choices, where the emissions come from, and
/// concrete greener options.
class GreenView extends StatelessWidget {
  const GreenView({required this.green, super.key});

  final GreenReport green;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = AgentKind.hariyali.color;
    final total = green.breakdown.values.fold<double>(0, (a, b) => a + b);
    final colors = {'Journey': AgentKind.safar.color, 'Local travel': AgentKind.raah.color, 'Stay': AgentKind.atithi.color};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: accent.withValues(alpha: 0.45))),
          child: Row(
            children: [
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 76,
                      height: 76,
                      child: CircularProgressIndicator(value: green.score / 100, strokeWidth: 8, color: accent, backgroundColor: accent.withValues(alpha: 0.2)),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${green.score}', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                        Text('eco score', style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${fixed(green.co2Kg, 0)} kg CO₂', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text('for the whole trip, estimated', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    if (green.co2SavedKg > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${fixed(green.co2SavedKg, 0)} kg less than the most polluting comparable choices',
                        style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.primaryGreenDark, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (green.breakdown.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text('Where it comes from', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (total > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (final e in green.breakdown.entries)
                      Expanded(flex: (e.value * 1000 / total).round().clamp(1, 1000), child: ColoredBox(color: colors[e.key] ?? scheme.outline)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          for (final e in green.breakdown.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[e.key] ?? scheme.outline, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.key, style: theme.textTheme.bodyMedium)),
                  Text('${fixed(e.value, 0)} kg', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  SizedBox(width: 44, child: Text(total > 0 ? '${(e.value / total * 100).round()}%' : '', textAlign: TextAlign.right, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant))),
                ],
              ),
            ),
        ],
        if (green.tips.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.eco_rounded, size: 18, color: accent),
              const SizedBox(width: 8),
              Text('Greener choices', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: accent)),
            ],
          ),
          const SizedBox(height: 6),
          for (final t in green.tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 6, right: 8), child: Icon(Icons.circle, size: 5)),
                  Expanded(child: Text(t, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
        const SizedBox(height: 12),
        Text(
          'Emissions use typical factors per passenger-kilometre and per hotel night, so treat them as estimates.',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
