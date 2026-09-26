import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/runtime/agent_toolkit.dart';
import 'package:urbanpulse/agents/yatri/planner_orchestrator.dart';
import 'package:urbanpulse/core/app_colors.dart';
import 'package:urbanpulse/core/app_theme.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/screens/plan_itinerary_screen.dart';

import '../agents/itinerary_editor_test.dart' show autoAnswer, world;
import '../agents/planner_orchestrator_test.dart' show toolkitFor;
import '../agents/hotel_world.dart';
import '../yatri/test_support.dart';

void main() {
  late Itinerary plan;
  late AgentToolkit toolkit;

  setUpAll(() async {
    final places = {'munnar': munnarCenter, 'pune': bengaluruCenter};
    toolkit = toolkitFor(world(), places: places);
    plan = (await PlannerOrchestrator(toolkit: toolkitFor(world(), places: places), ask: autoAnswer).run(completeBrief())).itinerary!;
  });

  Future<void> pump(WidgetTester tester, Size size, {ThemeMode mode = ThemeMode.light, bool editable = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(AccentColor.green),
        darkTheme: AppTheme.dark(AccentColor.green),
        themeMode: mode,
        home: PlanItineraryScreen(itinerary: plan, tileLayer: const SizedBox.shrink(), toolkit: editable ? toolkit : null),
      ),
    );
    await tester.pump();
  }

  for (final (name, size) in [('phone', const Size(360, 740)), ('tablet', const Size(820, 1180)), ('desktop', const Size(1280, 800))]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('the edit panel opens and renders on a $name (${mode.name})', (tester) async {
        await pump(tester, size, mode: mode);
        expect(find.text('Edit with Yatri'), findsOneWidget);
        await tester.tap(find.text('Edit with Yatri'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Tell me what to change'), findsOneWidget);
        expect(find.textContaining('Your plan, as first made'), findsOneWidget);
        expect(find.byType(TextField), findsWidgets);
        expect(find.byType(ActionChip), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a plan opened without the tools is read-only', (tester) async {
    await pump(tester, const Size(360, 740), editable: false);
    expect(find.text('Edit with Yatri'), findsNothing);
  });

  testWidgets('tapping a stop offers what can be done with it', (tester) async {
    await pump(tester, const Size(360, 740));
    final stop = plan.days.first.slots.firstWhere((s) => s.kind == SlotKind.visit && s.refId != null);
    await tester.ensureVisible(find.text(stop.title).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(stop.title).first);
    await tester.pumpAndSettle();
    expect(find.text('Why is this here?'), findsOneWidget);
    expect(find.text('Replace with something else'), findsOneWidget);
    expect(find.text('Remove from the plan'), findsOneWidget);

    await tester.tap(find.text('Why is this here?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Importance for this trip'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to another day'));
    await tester.pumpAndSettle();
    expect(find.text('Move to which day?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
