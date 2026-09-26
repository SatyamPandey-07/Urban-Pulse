import 'package:flutter/material.dart';

import '../../models/yatri_question.dart';
import 'choice_answers.dart';
import 'option_card.dart';

/// Adults / seniors / children (with an age each) / women. In chat mode the
/// parts must add up to the total the traveler already gave; in the review
/// form there is no fixed total, so the total is simply their sum.
class GroupStepperView extends StatefulWidget {
  const GroupStepperView({
    required this.question,
    required this.onSubmit,
    this.embedded = false,
    this.onChanged,
    super.key,
  });

  final YatriQuestion question;
  final AnswerSubmit onSubmit;
  final bool embedded;
  final AnswerChanged? onChanged;

  @override
  State<GroupStepperView> createState() => _GroupStepperViewState();
}

class _GroupStepperViewState extends State<GroupStepperView> {
  static const _defaultChildAge = 8;

  late int _adults = _pre('adults');
  late int _seniors = _pre('seniors');
  late int _children = _pre('children');
  late int _women = _pre('women');
  late List<int> _ages = _initialAges();

  int _pre(String key) => (widget.question.prefill[key] as int?) ?? 0;

  int? get _total => widget.question.prefill['total'] as int?;

  List<int> _initialAges() {
    final given = (widget.question.prefill['childAges'] as List?)?.cast<int>() ?? const [];
    return [
      for (var i = 0; i < _children; i++) i < given.length ? given[i] : _defaultChildAge,
    ];
  }

  int get _sum => _adults + _seniors + _children;

  String? get _problem {
    if (_sum < 1) return 'Add at least one traveller.';
    if (_adults + _seniors < 1) return 'At least one adult or senior is needed.';
    if (_women > _sum) return 'Women can’t be more than the group.';
    final total = _total;
    if (total != null && _sum != total) {
      return 'That adds up to $_sum, but you said $total travellers.';
    }
    return null;
  }

  GroupAnswer _answer() => GroupAnswer(
    adults: _adults,
    seniors: _seniors,
    children: _children,
    women: _women,
    childAges: List.of(_ages),
  );

  void _changed() {
    setState(() {});
    if (widget.embedded) {
      widget.onChanged?.call(_problem == null ? _answer() : null);
    }
  }

  void _setChildren(int v) {
    _children = v;
    while (_ages.length < v) {
      _ages.add(_defaultChildAge);
    }
    if (_ages.length > v) _ages = _ages.sublist(0, v);
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final problem = _problem;
    final total = _total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OptionGrid(
          children: [
            _CounterRow(
              emoji: '🧑',
              label: 'Adults',
              subtitle: '18 – 59 years',
              value: _adults,
              onChanged: (v) {
                _adults = v;
                _changed();
              },
            ),
            _CounterRow(
              emoji: '🧓',
              label: 'Seniors',
              subtitle: '60 and above',
              value: _seniors,
              onChanged: (v) {
                _seniors = v;
                _changed();
              },
            ),
            _CounterRow(
              emoji: '🧒',
              label: 'Children',
              subtitle: '0 – 17 years',
              value: _children,
              onChanged: _setChildren,
            ),
            _CounterRow(
              emoji: '👩',
              label: 'Women',
              subtitle: 'Any age, within the group',
              value: _women,
              onChanged: (v) {
                _women = v;
                _changed();
              },
            ),
          ],
        ),
        if (_children > 0) ...[
          const SizedBox(height: 12),
          Text(
            'Children’s ages',
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _children; i++)
                _AgeChip(
                  index: i,
                  age: _ages[i],
                  onChanged: (a) {
                    _ages[i] = a;
                    _changed();
                  },
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: (problem == null ? scheme.primary : scheme.error)
                .withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                problem == null ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                size: 18,
                color: problem == null ? scheme.primary : scheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  problem ??
                      (total == null
                          ? 'Group of $_sum'
                          : 'Group of $_sum matches your $total travellers'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: problem == null ? scheme.primary : scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!widget.embedded) ...[
          const SizedBox(height: 12),
          CtaButton(
            icon: Icons.check_rounded,
            label: 'Confirm group',
            onPressed: problem == null ? () => widget.onSubmit(_answer()) : null,
          ),
        ],
      ],
    );
  }
}

class _CounterRow extends StatelessWidget {
  const _CounterRow({
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String emoji;
  final String label;
  final String subtitle;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _StepButton(
            icon: Icons.remove_rounded,
            tooltip: 'Fewer $label',
            onTap: value > 0 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add_rounded,
            tooltip: 'More $label',
            onTap: value < 50 ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: scheme.primary.withValues(alpha: 0.12),
        foregroundColor: scheme.primary,
        disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.05),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 20),
    );
  }
}

class _AgeChip extends StatelessWidget {
  const _AgeChip({required this.index, required this.age, required this.onChanged});

  final int index;
  final int age;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Child ${index + 1}', style: theme.textTheme.bodySmall),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: age,
              isDense: true,
              borderRadius: BorderRadius.circular(16),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
              items: [
                for (var a = 0; a <= 17; a++)
                  DropdownMenuItem(value: a, child: Text(a == 0 ? '<1 yr' : '$a yrs')),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
