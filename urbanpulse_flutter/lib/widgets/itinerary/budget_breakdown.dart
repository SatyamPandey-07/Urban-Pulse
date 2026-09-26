import 'package:flutter/material.dart';

import '../../agents/runtime/agent_kind.dart';
import '../../core/app_colors.dart';
import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';

Color categoryColor(BudgetCategory c) => switch (c) {
  BudgetCategory.stay => AgentKind.atithi.color,
  BudgetCategory.transport => AgentKind.safar.color,
  BudgetCategory.activities => AgentKind.bhatkanti.color,
  BudgetCategory.food => AppColors.primaryPink,
  BudgetCategory.buffer => AppColors.textTertiary,
};

String categoryLabel(BudgetCategory c) => switch (c) {
  BudgetCategory.stay => 'Stay',
  BudgetCategory.transport => 'Transport',
  BudgetCategory.activities => 'Activities',
  BudgetCategory.food => 'Food',
  BudgetCategory.buffer => 'Buffer',
};

/// Where the money goes: the total against the budget, a bar split by
/// category, and every line with an "estimate" tag where it is one.
class BudgetBreakdown extends StatelessWidget {
  const BudgetBreakdown({required this.budget, super.key});

  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = budget.totalInr;
    final cap = budget.budgetMaxInr;
    final remaining = budget.remainingInr;
    final cats = [for (final c in BudgetCategory.values) if (budget.totalOf(c) > 0) c];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Estimated total', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              Text(rupees(total), style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              if (cap != null) ...[
                const SizedBox(height: 4),
                Text(
                  remaining! >= 0
                      ? '${rupees(remaining)} left of your ${rupees(cap)} budget'
                      : '${rupees(-remaining)} over your ${rupees(cap)} budget',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: remaining >= 0 ? AppColors.primaryGreenDark : scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (total > 0)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 12,
                    child: Row(
                      children: [
                        for (final c in cats)
                          Expanded(flex: (budget.totalOf(c) * 1000 / total).round().clamp(1, 1000), child: ColoredBox(color: categoryColor(c))),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  for (final c in cats)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: categoryColor(c), shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('${categoryLabel(c)} ${rupees(budget.totalOf(c))}', style: theme.textTheme.bodySmall),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final line in budget.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 34,
                  margin: const EdgeInsets.only(right: 12, top: 2),
                  decoration: BoxDecoration(color: categoryColor(line.category), borderRadius: BorderRadius.circular(2)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        line.isEstimated ? '${categoryLabel(line.category)} · estimate' : '${categoryLabel(line.category)} · live price',
                        style: theme.textTheme.labelSmall?.copyWith(color: line.isEstimated ? AppColors.solidWarning : AppColors.primaryGreenDark),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(rupees(line.amountInr), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        if (budget.hasEstimates)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Lines marked “estimate” use typical prices, so check live fares and rates before you book.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
