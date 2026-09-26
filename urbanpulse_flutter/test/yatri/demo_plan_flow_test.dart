import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/runtime/agent_kind.dart';
import 'package:urbanpulse/core/app_colors.dart';
import 'package:urbanpulse/core/app_theme.dart';
import 'package:urbanpulse/models/yatri_question.dart';
import 'package:urbanpulse/state/yatri_controller.dart';
import 'package:urbanpulse/widgets/taskgraph/task_graph_card.dart';
import 'package:urbanpulse/widgets/yatri/chat_entry_view.dart';

import 'receptionist_flow_test.dart' show build;

Future<void> until(bool Function() cond, {int ms = 4000}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: ms));
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) fail('condition not reached in ${ms}ms');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('the demo plan puts a graph in the chat and asks a real question mid-plan', () async {
    final (c, _, _) = await build();
    c.start();
    final run = c.startDemoPlan(speed: 0.005);

    expect(c.busy, isTrue);
    expect(c.phase, YatriPhase.planning);
    expect(c.canType, isFalse, reason: 'the composer is off while agents work');
    expect(c.entries.whereType<TaskGraphEntry>(), hasLength(1));

    await until(() => c.activeQuestion != null);
    final q = c.activeQuestion!.question;
    expect(q.id, startsWith('plan.demo'));
    expect(q.agent, 'yatri');
    expect(q.why, contains('only agent that decides'));
    expect(q.options.first.label, contains('Yes'));
    expect(c.busy, isTrue, reason: 'the plan is still running');

    // The graph shows Yatri waiting on the user, and the clock is paused.
    final graphEntry = c.entries.whereType<TaskGraphEntry>().single;
    expect(graphEntry.graph.hasWaitingUser, isTrue);
    expect(graphEntry.clock.isPaused, isTrue);

    await c.answer(q, ChoiceAnswer(q.options.first.id, q.options.first.label));
    await run;

    expect(c.phase, YatriPhase.done);
    expect(c.busy, isFalse);
    expect(graphEntry.graph.isFinished, isTrue);
    expect(graphEntry.clock.isPaused, isFalse);
    expect(c.entries.whereType<UserText>().last.text, contains('Yes'));
    expect((c.entries.last as AgentText).text, contains('preview run'));
  });

  test('a second demo cannot start while one is running, and start over resets', () async {
    final (c, _, _) = await build();
    c.start();
    final run = c.startDemoPlan(speed: 0.005);
    await c.startDemoPlan(speed: 0.005); // ignored
    expect(c.entries.whereType<TaskGraphEntry>(), hasLength(1));

    await until(() => c.activeQuestion != null);
    await c.answer(c.activeQuestion!.question, const ChoiceAnswer('o1', 'No'));
    await run;
    expect(c.entries.whereType<UserText>().last.text, 'No');

    c.start();
    expect(c.entries.whereType<TaskGraphEntry>(), isEmpty);
    expect(c.phase, YatriPhase.intake);
  });

  testWidgets('the planner’s question is answerable in the chat card while the plan is busy', (tester) async {
    tester.view.physicalSize = const Size(820, 1180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late YatriController c;
    late Future<void> run;
    // The demo's timers must run in real time, so create it inside runAsync.
    await tester.runAsync(() async {
      final (ctl, _, _) = await build();
      c = ctl..start();
      run = c.startDemoPlan(speed: 0.005);
      await until(() => c.activeQuestion != null);
    });

    final entry = c.activeQuestion!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(AccentColor.green),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ChatEntryView(
              entry: entry,
              controller: c,
              onOpenForm: () {},
              onReview: (_) {},
              onExample: (_) {},
              onViewTrip: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // Planner name in its colour, the question, its “?”, and the options.
    expect(find.text('Yatri · Planner'), findsOneWidget);
    expect(find.textContaining('wheelchair accessible'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
    expect(c.busy, isTrue);

    await tester.tap(find.text('Yes, up to ₹1,800 a night'));
    await tester.pump();
    await tester.runAsync(() => run);

    expect(c.phase, YatriPhase.done);
    expect(c.entries.whereType<UserText>().last.text, 'Yes, up to ₹1,800 a night');
  });

  testWidgets('the task graph card is what the chat shows for the plan', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late YatriController c;
    late Future<void> run;
    await tester.runAsync(() async {
      final (ctl, _, _) = await build();
      c = ctl..start();
      run = c.startDemoPlan(speed: 0.005);
      await until(() => c.activeQuestion != null);
    });

    final entry = c.entries.whereType<TaskGraphEntry>().single;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AccentColor.green),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ChatEntryView(
              entry: entry,
              controller: c,
              onOpenForm: () {},
              onReview: (_) {},
              onExample: (_) {},
              onViewTrip: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TaskGraphCard), findsOneWidget);
    expect(find.text('Waiting for your answer'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      await c.answer(c.activeQuestion!.question, const ChoiceAnswer('o0', 'Yes'));
      await run;
    });
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });

  test('every agent has a distinct colour, an icon and a key slot', () {
    final colors = {for (final a in AgentKind.values) a.color.toARGB32()};
    expect(colors, hasLength(AgentKind.values.length));
    for (final a in AgentKind.values) {
      expect(a.displayName, isNotEmpty);
      expect(a.description, isNotEmpty);
      expect(a.keySlot, inInclusiveRange(0, 3));
    }
    // Yatri and Hisab share a key; so do Atithi, Raah and Safar.
    expect(AgentKind.yatri.keySlot, AgentKind.hisab.keySlot);
    expect({AgentKind.atithi.keySlot, AgentKind.raah.keySlot, AgentKind.safar.keySlot}, hasLength(1));
    // No key carries more than three agents.
    final perSlot = <int, int>{};
    for (final a in AgentKind.values) {
      perSlot[a.keySlot] = (perSlot[a.keySlot] ?? 0) + 1;
    }
    expect(perSlot.values.every((n) => n <= 3), isTrue);
  });
}
