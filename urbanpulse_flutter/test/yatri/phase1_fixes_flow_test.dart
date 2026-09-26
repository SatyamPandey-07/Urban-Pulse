import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/domain/trip_brief/question_catalog.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/models/yatri_question.dart';
import 'package:urbanpulse/state/yatri_controller.dart';

import 'receptionist_flow_test.dart' show build;

/// Answers whatever mandatory question comes next until only optional ones (or
/// the review) are left, and returns the ids that were asked.
Future<List<String>> answerMandatory(YatriController c) async {
  final asked = <String>[];
  for (var i = 0; i < 20; i++) {
    final q = c.activeQuestion?.question;
    if (q == null || q.reason == IssueKind.optional) break;
    asked.add(q.id);
    final YatriAnswer a = switch (q.id) {
      'origin' => const ChoiceAnswer('Pune', 'Pune'),
      'dates' => DateRangeAnswer(DateTime(2026, 10, 10, 9), DateTime(2026, 10, 13, 18)),
      'women' => const ChoiceAnswer('0', 'No women in the group'),
      'childAges' => const AgesAnswer([5, 9]),
      'accessibility' => const MultiChoiceAnswer({'none'}, ['None']),
      'transport' => const MultiChoiceAnswer({'train'}, ['Train']),
      'budget' => const BudgetAnswer(10000, 20000),
      _ => throw StateError('unexpected mandatory question ${q.id}'),
    };
    await c.answer(q, a);
  }
  return asked;
}

void main() {
  group('group dynamics', () {
    test('“Trip of 4 men to Goa” never opens the group form', () async {
      final (c, llm, _) = await build();
      c.start();
      llm.extractions.add(
        '{"updates": {"destination": "Goa", "travellerCount": 4, "adults": 4,'
        ' "seniors": 0, "children": 0, "women": 0}}',
      );
      await c.sendText('Trip of 4 men to Goa');

      expect(c.brief.hasGroupBreakdown, isTrue);
      expect(c.progress.firstWhere((p) => p.label == 'Group').done, isTrue);
      final asked = await answerMandatory(c);
      for (final skipped in ['group', 'women', 'childAges', 'womenSafety']) {
        expect(asked, isNot(contains(skipped)), reason: '$skipped must not be asked');
      }
      expect(c.phase, YatriPhase.review);
    });

    test('“3 friends” asks only how many are women', () async {
      final (c, llm, _) = await build();
      c.start();
      llm.extractions.add(
        '{"updates": {"destination": "Goa", "travellerCount": 3, "adults": 3,'
        ' "seniors": 0, "children": 0}}',
      );
      await c.sendText('3 friends to Goa');
      await c.answer(c.activeQuestion!.question, const ChoiceAnswer('Pune', 'Pune'));
      await c.answer(
        c.activeQuestion!.question,
        DateRangeAnswer(DateTime(2026, 10, 10, 9), DateTime(2026, 10, 13, 18)),
      );

      final q = c.activeQuestion!.question;
      expect(q.id, 'women');
      expect(q.widget, AnswerWidget.mcq);
      await c.answer(q, const ChoiceAnswer('1', '1 woman'));
      // One woman in the group, so the safety follow-up is now asked.
      expect(c.activeQuestion!.question.id, 'womenSafety');
    });

    test('kids without ages ask only for the ages', () async {
      final (c, llm, _) = await build();
      c.start();
      llm.extractions.add(
        '{"updates": {"destination": "Goa", "travellerCount": 4, "adults": 2,'
        ' "children": 2, "women": 1}}',
      );
      await c.sendText('2 adults and 2 kids to Goa');
      await c.answer(c.activeQuestion!.question, const ChoiceAnswer('Pune', 'Pune'));
      await c.answer(
        c.activeQuestion!.question,
        DateRangeAnswer(DateTime(2026, 10, 10, 9), DateTime(2026, 10, 13, 18)),
      );
      expect(c.activeQuestion!.question.id, 'childAges');
    });
  });

  group('next best question', () {
    test('asks the model once, and asks at most two of what it picks', () async {
      final (c, llm, _) = await build();
      c.start();
      llm.nextBestReply = '{"ask": ["pace", "stay", "dietary"]}';
      llm.extractions.add(
        '{"updates": {"destination": "Goa", "travellerCount": 2, "adults": 2, "women": 0}}',
      );
      await c.sendText('2 adults to Goa');
      await answerMandatory(c);

      expect(llm.nextBestCalls, 1);
      final first = c.activeQuestion!.question;
      expect((first.id, first.skippable, first.reason), ('pace', true, IssueKind.optional));
      await c.answer(first, const ChoiceAnswer('relaxed', 'Relaxed'));
      expect(c.brief.pace, TripPace.relaxed);

      final second = c.activeQuestion!.question;
      expect(second.id, 'stay');
      await c.answer(second, const ChoiceAnswer(QuestionCatalog.skipId, 'Skip'));

      // Two asked, the third ignored: straight to review, never consulted again.
      expect(c.phase, YatriPhase.review);
      expect(llm.nextBestCalls, 1);
    });

    test('a rich brief is not worth a model call', () async {
      final (c, llm, _) = await build();
      c.start();
      llm.extractions.add(
        '{"updates": {"destination": "Goa", "travellerCount": 2, "adults": 2, "women": 0,'
        ' "style": "leisure", "pace": "relaxed", "stayTypes": ["homestay"]}}',
      );
      await c.sendText('relaxed leisure homestay trip for 2 adults to Goa');
      await answerMandatory(c);

      expect(llm.nextBestCalls, 0);
      expect(c.phase, YatriPhase.review);
    });

    test('an unusable model reply just means no extra questions', () async {
      final (c, llm, _) = await build();
      c.start();
      llm.nextBestReply = 'sorry, I cannot help with that';
      llm.extractions.add(
        '{"updates": {"destination": "Goa", "travellerCount": 2, "adults": 2, "women": 0}}',
      );
      await c.sendText('Goa for 2 adults');
      await answerMandatory(c);
      expect(c.phase, YatriPhase.review);
    });
  });

  group('agent-chosen widget', () {
    test('the model’s choice is used when it is on the allow-list', () async {
      final (c, llm, _) = await build();
      c.start();
      llm.phrasingReply = '{"message": "When are you leaving?", "widget": "presets"}';
      llm.extractions.add('{"updates": {"destination": "Goa", "originCity": "Pune"}}');
      await c.sendText('Pune to Goa');

      final q = c.activeQuestion!.question;
      expect(q.id, 'dates');
      expect(q.variant, 'presets');
      expect(q.displayText, 'When are you leaving?');
    });

    test('an invalid choice falls back to the default flavour', () async {
      final (c, llm, _) = await build();
      c.start();
      llm.phrasingReply = '{"message": "When are you leaving?", "widget": "hologram"}';
      llm.extractions.add('{"updates": {"destination": "Goa", "originCity": "Pune"}}');
      await c.sendText('Pune to Goa');

      expect(c.activeQuestion!.question.variant, 'calendar');
    });
  });
}
