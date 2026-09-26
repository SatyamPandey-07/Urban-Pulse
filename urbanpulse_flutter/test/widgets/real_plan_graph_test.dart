import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/yatri/planner_orchestrator.dart';
import 'package:urbanpulse/core/app_colors.dart';
import 'package:urbanpulse/core/app_theme.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/models/yatri_question.dart';
import 'package:urbanpulse/widgets/taskgraph/task_graph_card.dart';

import '../agents/hotel_world.dart';
import '../agents/planner_orchestrator_test.dart' show toolkitFor;
import '../yatri/test_support.dart';

/// The graph a real plan produces (nine agents, delegated Khoji checks, re-plan
/// passes) must lay out on any screen.
void main() {
  late PlannerOrchestrator plan;

  // The plan runs in the real async zone (setUpAll), not inside a widget test.
  setUpAll(() async {
    final places = [
      for (var i = 0; i < 9; i++)
        osmNode(200 + i, 'Viewpoint ${String.fromCharCode(65 + i)}${'x' * i}', 0.012 * i - 0.04, 0.01 * (i % 3) - 0.01, tags: {'tourism': 'viewpoint', if (i % 3 == 0) 'wheelchair': 'no'}),
    ];
    plan = PlannerOrchestrator(
      toolkit: toolkitFor(HotelWorld(overpassPlaces: places)),
      ask: (q) async {
        final opt = q.options.firstWhere((x) => x.recommended, orElse: () => q.options.first);
        return ChoiceAnswer(opt.id, opt.label);
      },
    );
    await plan.run(completeBrief().copyWith(accessibilityNeeds: {AccessibilityNeed.wheelchair}));
  });

  for (final (name, size) in [('phone', const Size(360, 740)), ('tablet', const Size(820, 1180)), ('wide', const Size(1280, 800))]) {
    testWidgets('a real plan graph renders in the chat card and the full page on a $name', (tester) async {
      expect(plan.graph.nodes.length, greaterThan(12), reason: 'a rich graph, not a toy one');

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AccentColor.green),
          home: Scaffold(body: SingleChildScrollView(child: TaskGraphCard(graph: plan.graph, clock: plan.clock))),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(MaterialApp(theme: AppTheme.light(AccentColor.green), home: TaskGraphPage(graph: plan.graph)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  }
}
