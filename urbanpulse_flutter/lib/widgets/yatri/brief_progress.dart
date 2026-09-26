import 'package:flutter/material.dart';

import '../../state/yatri_controller.dart';
import 'option_card.dart';

/// "7/10" ring shown in the header.
class ProgressRing extends StatelessWidget {
  const ProgressRing({required this.done, required this.total, super.key});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = total == 0 ? 0.0 : done / total;
    return Semantics(
      label: '$done of $total details collected',
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: value),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOut,
                builder: (context, v, _) => CircularProgressIndicator(
                  value: v,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  backgroundColor: scheme.primary.withValues(alpha: 0.15),
                ),
              ),
            ),
            Text(
              '$done/$total',
              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal chip rail of the mandatory details. A filled chip can be tapped
/// to re-open that question, pre-filled.
class BriefProgressStrip extends StatelessWidget {
  const BriefProgressStrip({required this.items, required this.onEdit, super.key});

  final List<ProgressItem> items;
  final ValueChanged<String> onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final item = items[i];
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: item.done
                  ? scheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: item.done ? scheme.primary : scheme.outlineVariant,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: item.done ? () => onEdit(item.questionId) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(
                        item.done
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 16,
                        color: item.done ? scheme.primary : scheme.outline,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        item.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: item.done
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The live "Trip brief" side panel shown next to the chat on wide screens.
class BriefPanel extends StatelessWidget {
  const BriefPanel({
    required this.items,
    required this.done,
    required this.total,
    required this.onEdit,
    required this.onOpenForm,
    super.key,
  });

  final List<ProgressItem> items;
  final int done;
  final int total;
  final ValueChanged<String> onEdit;
  final VoidCallback onOpenForm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 12, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProgressRing(done: done, total: total),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip brief',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$done of $total details collected',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: scheme.outlineVariant),
              itemBuilder: (context, i) {
                final item = items[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: item.done ? () => onEdit(item.questionId) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          item.done
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          size: 18,
                          color: item.done ? scheme.primary : scheme.outline,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                item.value ?? 'Not yet answered',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: item.value == null ? scheme.outline : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (item.done)
                          Icon(Icons.edit_outlined, size: 16, color: scheme.outline),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          CtaButton(
            tonal: true,
            icon: Icons.edit_note_rounded,
            label: 'Open the form',
            onPressed: onOpenForm,
          ),
        ],
      ),
    );
  }
}
