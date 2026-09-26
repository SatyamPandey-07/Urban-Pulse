import 'package:flutter/material.dart';

import '../../domain/trip_brief/question_catalog.dart';
import '../../models/yatri_question.dart';
import 'option_card.dart';

/// Shared contract of every answer view. In chat mode a view calls [onSubmit]
/// once when the traveler commits. In [embedded] mode (the review form) there
/// is no commit button: it reports the current value — or null while invalid —
/// through [onChanged] on every change.
typedef AnswerSubmit = void Function(YatriAnswer answer);
typedef AnswerChanged = void Function(YatriAnswer? answer);

/// Single choice. A tap answers immediately in chat mode.
class McqAnswerView extends StatefulWidget {
  const McqAnswerView({
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
  State<McqAnswerView> createState() => _McqAnswerViewState();
}

class _McqAnswerViewState extends State<McqAnswerView> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.question.preselected.firstOrNull;
  }

  void _pick(QuestionOption o) {
    if (widget.embedded) {
      setState(() => _selected = _selected == o.id ? null : o.id);
      widget.onChanged?.call(
        _selected == null ? null : ChoiceAnswer(o.id, o.label),
      );
    } else {
      widget.onSubmit(ChoiceAnswer(o.id, o.label));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;

    // Every single-choice question is a vertical list of options.
    final Widget options = OptionGrid(
      children: [
        for (final o in q.options)
          OptionCard(
            option: o,
            selected: _selected == o.id,
            onTap: () => _pick(o),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        options,
        if (q.skippable && !widget.embedded) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => widget.onSubmit(
                const ChoiceAnswer(QuestionCatalog.skipId, 'Skip'),
              ),
              child: const Text('Skip'),
            ),
          ),
        ],
      ],
    );
  }
}

/// Multiple choice with checkbox cards. "Exclusive" options (e.g. "None")
/// clear the rest, and picking anything else clears them.
class MultiSelectAnswerView extends StatefulWidget {
  const MultiSelectAnswerView({
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
  State<MultiSelectAnswerView> createState() => _MultiSelectAnswerViewState();
}

class _MultiSelectAnswerViewState extends State<MultiSelectAnswerView> {
  late Set<String> _selected = {...widget.question.preselected};

  MultiChoiceAnswer _answer() {
    final chosen = [
      for (final o in widget.question.options)
        if (_selected.contains(o.id)) o,
    ];
    return MultiChoiceAnswer(
      {for (final o in chosen) o.id},
      [for (final o in chosen) o.label],
    );
  }

  void _toggle(QuestionOption o) {
    setState(() {
      if (_selected.contains(o.id)) {
        _selected.remove(o.id);
      } else if (o.exclusive) {
        _selected = {o.id};
      } else {
        _selected.removeWhere(
          (id) => widget.question.options.any((x) => x.id == id && x.exclusive),
        );
        _selected.add(o.id);
      }
    });
    if (widget.embedded) {
      widget.onChanged?.call(_selected.isEmpty ? null : _answer());
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final count = _selected.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OptionGrid(
          children: [
            for (final o in q.options)
              OptionCard(
                option: o,
                multi: true,
                selected: _selected.contains(o.id),
                onTap: () => _toggle(o),
              ),
          ],
        ),
        if (!widget.embedded) ...[
          const SizedBox(height: 12),
          CtaButton(
            icon: Icons.check_rounded,
            label: count == 0
                ? (q.skippable ? 'Skip' : 'Select at least one')
                : 'Confirm ($count)',
            onPressed: count == 0
                ? (q.skippable
                      ? () => widget.onSubmit(
                          const ChoiceAnswer(QuestionCatalog.skipId, 'Skip'),
                        )
                      : null)
                : () => widget.onSubmit(_answer()),
          ),
        ],
      ],
    );
  }
}

/// Two large, unmistakable buttons.
class YesNoAnswerView extends StatelessWidget {
  const YesNoAnswerView({required this.onSubmit, super.key});

  final AnswerSubmit onSubmit;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: CtaButton(
          icon: Icons.check_rounded,
          label: 'Yes',
          onPressed: () => onSubmit(const BoolAnswer(true)),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: CtaButton(
          icon: Icons.close_rounded,
          label: 'No',
          tonal: true,
          onPressed: () => onSubmit(const BoolAnswer(false)),
        ),
      ),
    ],
  );
}
