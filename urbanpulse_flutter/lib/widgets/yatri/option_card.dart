import 'package:flutter/material.dart';

import '../../models/yatri_question.dart';

/// The custom selection mark used by every Yatri answer: a rounded square for
/// multi-select (a checkbox) or a circle for single choice (a radio). Built
/// from the colour scheme so it follows the user's accent and light/dark mode.
class SelectionMark extends StatelessWidget {
  const SelectionMark({required this.selected, required this.multi, super.key});

  final bool selected;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(multi ? 7 : 12);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? scheme.primary : Colors.transparent,
        borderRadius: radius,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outline,
          width: 1.6,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 140),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: selected
            ? Icon(
                multi ? Icons.check_rounded : Icons.circle,
                key: const ValueKey('on'),
                size: multi ? 16 : 8,
                color: scheme.onPrimary,
              )
            : const SizedBox.shrink(key: ValueKey('off')),
      ),
    );
  }
}

/// A selectable card: emoji, title, optional subtitle / CO2 badge, and a
/// selection mark. Used for the richer choices (transport, accessibility…).
class OptionCard extends StatelessWidget {
  const OptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
    this.multi = false,
    super.key,
  });

  final QuestionOption option;
  final bool selected;
  final bool multi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                if (option.emoji != null) ...[
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(option.emoji!, style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text(
                            option.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (option.recommended)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '🌱 Greener',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (option.subtitle != null || option.badge != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            option.subtitle ?? option.badge!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                SelectionMark(selected: selected, multi: multi),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact pill for short one-word choices (cities, group sizes).
class OptionPill extends StatelessWidget {
  const OptionPill({
    required this.option,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final QuestionOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? scheme.primary
              : option.recommended
              ? scheme.primary.withValues(alpha: 0.6)
              : scheme.outlineVariant,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (option.emoji != null) ...[
                  Text(option.emoji!),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    option.label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? scheme.onPrimary : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays option cards out in one column on phones and two on wider layouts,
/// keeping every card the same width whatever its height.
class OptionGrid extends StatelessWidget {
  const OptionGrid({required this.children, this.spacing = 8, super.key});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cols = constraints.maxWidth >= 520 ? 2 : 1;
      final width = (constraints.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final c in children) SizedBox(width: width, child: c)],
      );
    },
  );
}

/// A full-width pill button for a primary call to action inside a card.
class CtaButton extends StatelessWidget {
  const CtaButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.tonal = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );
    return tonal
        ? FilledButton.tonal(onPressed: onPressed, style: style, child: child)
        : FilledButton(onPressed: onPressed, style: style, child: child);
  }
}
