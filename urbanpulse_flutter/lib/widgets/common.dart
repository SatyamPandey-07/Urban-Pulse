import 'package:flutter/material.dart';

/// Small building blocks shared by the migrated screens, standing in for the
/// repeated `MaterialCardView` / header / chip-group blocks in the XML layouts.

/// The filled, 24dp-rounded surface card every screen is built out of.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderColor,
    this.borderWidth = 0,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: borderWidth > 0
          ? BorderSide(color: borderColor ?? scheme.primary, width: borderWidth)
          : BorderSide.none,
    );
    return Card(
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Title + subtitle heading with a back button, used by every pushed screen
/// (`btnBack` + the two `TextView`s at the top of each `activity_*.xml`).
class ScreenHeader extends StatelessWidget implements PreferredSizeWidget {
  const ScreenHeader({
    required this.title,
    required this.subtitle,
    this.actions,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      toolbarHeight: 72,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      titleSpacing: 0,
      actions: actions,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled headline figure — the "TOTAL CO2 AVOIDED / 37.4 kg" style tiles.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    this.caption,
    this.valueColor,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(
            caption!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// A single-select chip row, the Flutter form of `ChipGroup` with
/// `singleSelection`.
class SingleChoiceChips<T> extends StatelessWidget {
  const SingleChoiceChips({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.wrap = true,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final chips = values
        .map(
          (value) => ChoiceChip(
            label: Text(labelOf(value)),
            selected: value == selected,
            onSelected: (_) => onSelected(value),
          ),
        )
        .toList();

    if (wrap) return Wrap(spacing: 8, runSpacing: 8, children: chips);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips)
            Padding(padding: const EdgeInsets.only(right: 8), child: chip),
        ],
      ),
    );
  }
}

/// The "Describe what you're looking for" free-text natural-language box that
/// sits above Hospitality, Green Routes and Itinerary, with its parsed-intent
/// summary line.
class IntentPromptCard extends StatelessWidget {
  const IntentPromptCard({
    required this.title,
    required this.hint,
    required this.buttonLabel,
    required this.controller,
    required this.onApply,
    required this.summary,
    this.isParsing = false,
    super.key,
  });

  final String title;
  final String hint;
  final String buttonLabel;
  final TextEditingController controller;
  final VoidCallback onApply;
  final String? summary;
  final bool isParsing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(hintText: hint, isDense: true),
            onSubmitted: (_) => onApply(),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: isParsing ? null : onApply,
              icon: isParsing
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(buttonLabel),
            ),
          ),
          if (summary != null) ...[
            const SizedBox(height: 8),
            Text(
              summary!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Consistent "nothing here yet" copy for the migrated empty states.
class EmptyState extends StatelessWidget {
  const EmptyState({required this.message, this.icon, super.key});

  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
      child: Column(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 36, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders the lightweight `**bold**` markup the assistant emits in its replies.
/// Full Markdown would need a package; the source only ever uses bold runs.
class InlineBoldText extends StatelessWidget {
  const InlineBoldText(this.text, {this.style, super.key});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? Theme.of(context).textTheme.bodyMedium;
    final spans = <TextSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*', dotAll: true);
    var index = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      index = match.end;
    }
    if (index < text.length) spans.add(TextSpan(text: text.substring(index)));

    return Text.rich(TextSpan(style: baseStyle, children: spans));
  }
}

/// Shorthand for the Toast-equivalent used throughout the original Activities.
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
