import 'package:flutter/material.dart';

import '../../models/yatri_question.dart';
import 'budget_view.dart';
import 'choice_answers.dart';
import 'date_time_view.dart';
import 'group_stepper_view.dart';

/// Picks the answer widget the question asks for. The same views power the
/// chat cards and (with [embedded]) the review form.
Widget buildAnswerView(
  YatriQuestion q, {
  required AnswerSubmit onSubmit,
  bool embedded = false,
  AnswerChanged? onChanged,
  Key? key,
}) {
  switch (q.widget) {
    case AnswerWidget.mcq:
    case AnswerWidget.cta:
      return McqAnswerView(
        key: key,
        question: q,
        onSubmit: onSubmit,
        embedded: embedded,
        onChanged: onChanged,
      );
    case AnswerWidget.multiSelect:
      return MultiSelectAnswerView(
        key: key,
        question: q,
        onSubmit: onSubmit,
        embedded: embedded,
        onChanged: onChanged,
      );
    case AnswerWidget.yesNo:
      return YesNoAnswerView(key: key, onSubmit: onSubmit);
    case AnswerWidget.dateTimeRange:
      return DateTimeAnswerView(
        key: key,
        question: q,
        onSubmit: onSubmit,
        embedded: embedded,
        onChanged: onChanged,
      );
    case AnswerWidget.groupStepper:
      return GroupStepperView(
        key: key,
        question: q,
        onSubmit: onSubmit,
        embedded: embedded,
        onChanged: onChanged,
      );
    case AnswerWidget.budgetRange:
      return BudgetAnswerView(
        key: key,
        question: q,
        onSubmit: onSubmit,
        embedded: embedded,
        onChanged: onChanged,
      );
    case AnswerWidget.text:
      return const SizedBox.shrink();
  }
}
