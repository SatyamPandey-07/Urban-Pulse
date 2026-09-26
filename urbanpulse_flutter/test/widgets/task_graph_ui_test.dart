import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/runtime/agent_kind.dart';
import 'package:urbanpulse/agents/runtime/demo_plan.dart';
import 'package:urbanpulse/agents/runtime/plan_clock.dart';
import 'package:urbanpulse/agents/runtime/report.dart';
import 'package:urbanpulse/agents/runtime/task_board.dart';
import 'package:urbanpulse/agents/runtime/task_graph.dart';
import 'package:urbanpulse/core/app_colors.dart';
import 'package:urbanpulse/core/app_theme.dart';
import 'package:urbanpulse/widgets/taskgraph/agent_feed.dart';
import 'package:urbanpulse/widgets/taskgraph/task_graph_card.dart';
import 'package:urbanpulse/widgets/taskgraph/task_graph_view.dart';

const _phone = Size(360, 740);
const _tablet = Size(820, 1180);
const _wide = Size(1280, 800);

Future<void> pumpAt(WidgetTester tester, Size size, Widget child, {bool dark = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark(AccentColor.green) : AppTheme.light(AccentColor.green),
      home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
    ),
  );
  await tester.pump();
}

void main() {
  group('demo run drives the board', () {
    test('finishes every task with the whole story, the user question and delegation', () async {
      final graph = TaskGraph();
      final board = TaskBoard(graph: graph);
      final asked = <String>[];
      final result = await runDemoPlan(
        board,
        speed: 0.01,
        ask: (q, options) async {
          asked.add(q);
          // While the question is open the clock is paused and Yatri is waiting.
          expect(board.clock.isPaused, isTrue);
          expect(graph.node('yatri.ask')!.status, TaskStatus.waitingUser);
          return options.last;
        },
      );

      expect(result.status, ReportStatus.done);
      expect(result.summary, contains('no, keep searching'));
      expect(asked.single, contains('wheelchair'));
      expect(graph.isFinished, isTrue);
      expect(graph.nodes.every((n) => n.status.isFinished), isTrue);

      // Every agent took part, and Khoji was delegated to by Atithi.
      expect({for (final n in graph.nodes) n.agent}, AgentKind.values.toSet());
      expect(graph.node('khoji.hotels')!.delegatedBy, 'atithi.hotels');
      expect(graph.node('atithi.retry')!.parentIds, ['yatri.ask']);

      // Workers ran in parallel: Atithi, Bhatkanti and Safar overlapped.
      final a = graph.node('atithi.hotels')!, b = graph.node('bhatkanti.spots')!, s = graph.node('safar.transport')!;
      expect(b.startedAt!.isBefore(a.endedAt!), isTrue);
      expect(s.startedAt!.isBefore(b.endedAt!), isTrue);

      // The feed narrates it, with reasons.
      expect(graph.events.length, greaterThan(10));
      expect(graph.events.where((e) => e.why != null).length, greaterThan(8));
      expect(graph.events.any((e) => e.kind == FeedKind.negotiate && e.agent == AgentKind.hisab), isTrue);
      expect(graph.events.any((e) => e.kind == FeedKind.delegate), isTrue);
    });

    test('the user’s time is not counted against the plan', () async {
      var now = DateTime(2026, 1, 1);
      final clock = PlanClock(now: () => now);
      final board = TaskBoard(graph: TaskGraph(), clock: clock);
      await runDemoPlan(
        board,
        speed: 0.01,
        ask: (q, o) async {
          // The traveller takes ten minutes to answer.
          now = now.add(const Duration(minutes: 10));
          return o.first;
        },
      );
      expect(clock.elapsed.inMinutes, lessThan(1));
    });
  });

  group('graph view', () {
    testWidgets('shows a pill per task in its agent’s colour, with “?” where there is a reason', (tester) async {
      final graph = TaskGraph();
      final board = TaskBoard(graph: graph);
      // ignore: unawaited_futures
      runDemoPlan(board, speed: 0.01, ask: (q, o) async => o.first);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
      await pumpAt(tester, _tablet, TaskGraphView(graph: graph), dark: true);
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Atithi'), findsWidgets);
      expect(find.text('Find hotels'), findsOneWidget);
      expect(find.text('Yatri'), findsWidgets);
      // Agent names are coloured with the agent's own colour.
      final atithiText = tester.widgetList<Text>(find.text('Atithi')).first;
      expect(atithiText.style!.color!.toARGB32() & 0x00FFFFFF, AgentKind.atithi.color.toARGB32() & 0x00FFFFFF);
      // Task titles are neutral, not coloured.
      final title = tester.widget<Text>(find.text('Find hotels'));
      expect(title.style!.color, isNot(AgentKind.atithi.color));
      // Reasons hang off a “?”.
      expect(find.byIcon(Icons.help_outline_rounded), findsWidgets);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('tapping “?” opens the reason', (tester) async {
      final graph = TaskGraph()
        ..addNode(TaskNode(const TaskSpec(id: 'a', agent: AgentKind.atithi, title: 'Find hotels', why: 'You need somewhere to sleep.')));
      await pumpAt(tester, _phone, TaskGraphView(graph: graph));
      await tester.tap(find.byIcon(Icons.help_outline_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Why is this happening?'), findsOneWidget);
      expect(find.text('You need somewhere to sleep.'), findsOneWidget);
    });

    testWidgets('status glyphs follow the task state as the graph changes', (tester) async {
      final graph = TaskGraph();
      final node = TaskNode(const TaskSpec(id: 'a', agent: AgentKind.atithi, title: 'Find hotels'));
      graph.addNode(node);
      await pumpAt(tester, _phone, TaskGraphView(graph: graph));
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);

      graph.update('a', (n) => n.status = TaskStatus.running);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      graph.update('a', (n) => n.status = TaskStatus.waitingUser);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);

      graph.update('a', (n) => n.status = TaskStatus.done);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      graph.update('a', (n) => n.status = TaskStatus.failed);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      graph.update('a', (n) => n.status = TaskStatus.degraded);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('a full graph lays out without overflow in ${dark ? 'dark' : 'light'} mode', (tester) async {
        final graph = TaskGraph();
        final board = TaskBoard(graph: graph);
        // ignore: unawaited_futures
        runDemoPlan(board, speed: 0.005, ask: (q, o) async => o.first);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
        await pumpAt(tester, _phone, SingleChildScrollView(scrollDirection: Axis.horizontal, child: TaskGraphView(graph: graph)), dark: dark);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('feed', () {
    testWidgets('agent names are coloured, the rest is neutral, and “?” shows the reason', (tester) async {
      final graph = TaskGraph()
        ..addEvent(FeedEvent(agent: AgentKind.atithi, text: 'found 4 relevant hotels', why: 'Shortlisted near your places.', kind: FeedKind.found))
        ..addEvent(FeedEvent(agent: AgentKind.hisab, text: 'negotiating with Atithi', kind: FeedKind.negotiate));
      await pumpAt(tester, _phone, AgentFeed(graph: graph, maxEvents: 5), dark: true);
      await tester.pump(const Duration(milliseconds: 400));
      final rich = tester.widgetList<RichText>(find.byType(RichText)).where((r) => r.text.toPlainText().contains('found 4 relevant hotels')).first;
      final root = (rich.text as TextSpan).children!.first as TextSpan;
      final spans = root.children!.cast<TextSpan>();
      expect(spans.first.text, 'Atithi');
      expect(spans.first.style!.color!.toARGB32() & 0x00FFFFFF, AgentKind.atithi.color.toARGB32() & 0x00FFFFFF);
      expect(spans.last.text, ' found 4 relevant hotels');
      // Only the line with a reason has a “?”.
      expect(find.byIcon(Icons.help_outline_rounded), findsOneWidget);
    });

    testWidgets('the compact feed keeps only the latest lines', (tester) async {
      final graph = TaskGraph();
      for (var i = 0; i < 10; i++) {
        graph.addEvent(FeedEvent(agent: AgentKind.yatri, text: 'step $i'));
      }
      await pumpAt(tester, _phone, AgentFeed(graph: graph, maxEvents: 3));
      await tester.pump(const Duration(milliseconds: 400));
      String plain(RichText r) => r.text.toPlainText();
      final lines = tester.widgetList<RichText>(find.byType(RichText)).map(plain).where((t) => t.contains('step')).toList();
      expect(lines, ['Yatri step 7', 'Yatri step 8', 'Yatri step 9']);
    });
  });

  group('inline card and full page', () {
    test('status line tells the truth about progress', () {
      final g = TaskGraph();
      expect(planStatusLine(g), 'Getting started');
      g
        ..addNode(TaskNode(const TaskSpec(id: 'a', agent: AgentKind.atithi, title: 'a')))
        ..addNode(TaskNode(const TaskSpec(id: 'b', agent: AgentKind.raah, title: 'b')));
      g.update('a', (n) => n.status = TaskStatus.done);
      g.update('b', (n) => n.status = TaskStatus.running);
      expect(planStatusLine(g), '1 of 2 tasks done · 1 working');
      g.update('b', (n) => n.status = TaskStatus.waitingUser);
      expect(planStatusLine(g), 'Waiting for your answer');
      g.update('b', (n) => n.status = TaskStatus.failed);
      expect(planStatusLine(g), '1 of 2 tasks finished, 1 could not complete');
      g.update('b', (n) => n.status = TaskStatus.done);
      expect(planStatusLine(g), 'All 2 tasks finished');
    });

    for (final (name, size) in [('phone', _phone), ('tablet', _tablet)]) {
      testWidgets('the chat card renders on a $name and expands to the full page', (tester) async {
        final graph = TaskGraph();
        final clock = PlanClock()..start();
        final board = TaskBoard(graph: graph, clock: clock);
        // ignore: unawaited_futures
        runDemoPlan(board, speed: 0.005, ask: (q, o) async => o.first);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 500)));

        await pumpAt(tester, size, TaskGraphCard(graph: graph, clock: clock));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Planning your trip'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byTooltip('Open full view'));
        await tester.pumpAndSettle();
        expect(find.text('What the agents are doing'), findsOneWidget);
        // The legend lists every agent.
        for (final a in AgentKind.values) {
          expect(find.text(a.displayName), findsWidgets);
        }
        expect(tester.takeException(), isNull);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
      });
    }

    testWidgets('the full page lays out side by side on a wide screen', (tester) async {
      final graph = TaskGraph()
        ..addNode(TaskNode(const TaskSpec(id: 'a', agent: AgentKind.yatri, title: 'Plan the trip')))
        ..addEvent(FeedEvent(agent: AgentKind.yatri, text: 'allocated tasks'));
      tester.view.physicalSize = _wide;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(AccentColor.green), home: TaskGraphPage(graph: graph)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('What the agents are doing'), findsOneWidget);
      expect(find.byType(VerticalDivider), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
