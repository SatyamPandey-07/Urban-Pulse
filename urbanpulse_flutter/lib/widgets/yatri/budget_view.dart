import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../models/yatri_question.dart';
import 'choice_answers.dart';
import 'option_card.dart';

/// Budget tiers scaled to the group size and trip length, plus a custom range.
class BudgetAnswerView extends StatefulWidget {
  const BudgetAnswerView({
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
  State<BudgetAnswerView> createState() => _BudgetAnswerViewState();
}

class _Tier {
  const _Tier(this.id, this.label, this.emoji, this.lowPerDay, this.highPerDay);

  final String id;
  final String label;
  final String emoji;
  final int lowPerDay;
  final int highPerDay;
}

class _BudgetAnswerViewState extends State<BudgetAnswerView> {
  static const _tiers = [
    _Tier('budget', 'Budget-friendly', '🎒', 1500, 3000),
    _Tier('comfort', 'Comfortable', '🛏️', 3000, 6000),
    _Tier('premium', 'Premium', '✨', 6000, 12000),
    _Tier('luxury', 'Luxury', '👑', 12000, 25000),
  ];
  static const _custom = 'custom';
  static const _step = 500.0;

  late final int _people = math.max(1, (widget.question.prefill['people'] as int?) ?? 1);
  late final int _days = math.max(1, (widget.question.prefill['days'] as int?) ?? 1);
  late final double _sliderMax = math.max(
    100000,
    _round(_people * _days * 25000 * 1.2),
  ).toDouble();

  String? _selected;
  late RangeValues _range;

  double _round(num v) => (v / _step).round() * _step;

  (int, int) _tierRange(_Tier t) => (
    _round(t.lowPerDay * _people * _days).toInt(),
    _round(t.highPerDay * _people * _days).toInt(),
  );

  @override
  void initState() {
    super.initState();
    final min = widget.question.prefill['min'] as int?;
    final max = widget.question.prefill['max'] as int?;
    final mid = _tierRange(_tiers[1]);
    _range = RangeValues(
      (min ?? mid.$1).toDouble().clamp(0, _sliderMax),
      (max ?? mid.$2).toDouble().clamp(0, _sliderMax),
    );
    if (max != null) {
      _selected = _custom;
      for (final t in _tiers) {
        final r = _tierRange(t);
        if (r.$1 == min && r.$2 == max) _selected = t.id;
      }
    }
  }

  BudgetAnswer? get _answer => _selected == null
      ? null
      : BudgetAnswer(_range.start.round(), _range.end.round());

  bool get _valid => _answer != null && _range.end >= 500;

  void _select(String id, {RangeValues? range}) {
    setState(() {
      _selected = id;
      if (range != null) _range = range;
    });
    if (widget.embedded) widget.onChanged?.call(_valid ? _answer : null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final perPerson = _range.end / _people / _days;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Whole trip · $_people traveller${_people == 1 ? '' : 's'} · $_days day${_days == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        OptionGrid(
          children: [
            for (final t in _tiers)
              OptionCard(
                option: QuestionOption(
                  id: t.id,
                  label: t.label,
                  emoji: t.emoji,
                  subtitle:
                      '${rupees(_tierRange(t).$1)} – ${rupees(_tierRange(t).$2)}',
                ),
                selected: _selected == t.id,
                onTap: () {
                  final r = _tierRange(t);
                  _select(t.id, range: RangeValues(r.$1.toDouble(), r.$2.toDouble()));
                },
              ),
            OptionCard(
              option: const QuestionOption(
                id: _custom,
                label: 'Custom range',
                emoji: '🎚️',
                subtitle: 'Set your own minimum and maximum',
              ),
              selected: _selected == _custom,
              onTap: () => _select(_custom),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _selected == _custom
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    children: [
                      RangeSlider(
                        values: _range,
                        min: 0,
                        max: _sliderMax,
                        divisions: (_sliderMax / _step).round(),
                        labels: RangeLabels(
                          rupees(_range.start),
                          rupees(_range.end),
                        ),
                        onChanged: (v) => _select(_custom, range: v),
                      ),
                      Text(
                        '${rupees(_range.start)} – ${rupees(_range.end)}  ·  about ${rupees(perPerson)} per person per day',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (!widget.embedded) ...[
          const SizedBox(height: 12),
          CtaButton(
            icon: Icons.check_rounded,
            label: _valid
                ? 'Confirm ${rupees(_range.start)} – ${rupees(_range.end)}'
                : 'Choose a budget',
            onPressed: _valid ? () => widget.onSubmit(_answer!) : null,
          ),
        ],
      ],
    );
  }
}
