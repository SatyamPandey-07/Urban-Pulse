import 'package:flutter/material.dart';

import '../../models/yatri_question.dart';
import 'choice_answers.dart';
import 'option_card.dart';

/// One age row per child. Asked on its own when the traveller already told us
/// how many children there are, so the whole group form is not needed.
class ChildAgesView extends StatefulWidget {
  const ChildAgesView({required this.question, required this.onSubmit, super.key});

  final YatriQuestion question;
  final AnswerSubmit onSubmit;

  @override
  State<ChildAgesView> createState() => _ChildAgesViewState();
}

class _ChildAgesViewState extends State<ChildAgesView> {
  static const _defaultAge = 8;

  late final List<int> _ages = () {
    final kids = (widget.question.prefill['children'] as int?) ?? 1;
    final given = (widget.question.prefill['childAges'] as List?)?.cast<int>() ?? const [];
    return [for (var i = 0; i < kids; i++) i < given.length ? given[i] : _defaultAge];
  }();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _ages.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.child_care_outlined, size: 22, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _ages.length == 1 ? 'Child' : 'Child ${i + 1}',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _ages[i],
                      borderRadius: BorderRadius.circular(16),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                      items: [
                        for (var a = 0; a <= 17; a++)
                          DropdownMenuItem(
                            value: a,
                            child: Text(a == 0 ? 'Under 1' : '$a years'),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _ages[i] = v);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        CtaButton(
          icon: Icons.check_rounded,
          label: 'Confirm ages',
          onPressed: () => widget.onSubmit(AgesAnswer(List.of(_ages))),
        ),
      ],
    );
  }
}

/// The "stepper" flavour of the traveller-count question: a big counter for
/// groups the option list doesn't cover.
class TravellersStepperView extends StatefulWidget {
  const TravellersStepperView({required this.onSubmit, super.key});

  final AnswerSubmit onSubmit;

  @override
  State<TravellersStepperView> createState() => _TravellersStepperViewState();
}

class _TravellersStepperViewState extends State<TravellersStepperView> {
  int _count = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: 'Fewer travellers',
                onPressed: _count > 1 ? () => setState(() => _count--) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                width: 110,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_count',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                    Text(
                      _count == 1 ? 'traveller' : 'travellers',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'More travellers',
                onPressed: _count < 50 ? () => setState(() => _count++) : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CtaButton(
          icon: Icons.check_rounded,
          label: 'Confirm $_count ${_count == 1 ? 'traveller' : 'travellers'}',
          onPressed: () => widget.onSubmit(
            ChoiceAnswer('$_count', _count == 1 ? 'Just me' : '$_count people'),
          ),
        ),
      ],
    );
  }
}
