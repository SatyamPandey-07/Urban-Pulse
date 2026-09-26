import '../../core/formatting.dart';
import '../../models/trip_brief.dart';
import '../../models/trip_models.dart';
import '../../services/groq_agentic_engine.dart';
import '../core/yatri_agent.dart';

typedef PlanGenerator =
    Future<TripPlan> Function({
      required String destination,
      required String originCity,
      required int days,
      required bool isAccessible,
      required String travelStyle,
    });

/// Phase-1 hand-off: turns the confirmed [TripBrief] into a [TripPlan] with the
/// existing autonomous planner, until phase 2's hotel / hotspot / itinerary
/// agents replace it. The engine has its own computed fallback, so this always
/// yields a plan.
class TripPlanHandoffAgent implements YatriAgent<TripBrief, TripPlan> {
  TripPlanHandoffAgent({PlanGenerator? generator})
    : _generate = generator ?? GroqAgenticEngine.generateAutonomousTripPlan;

  final PlanGenerator _generate;

  @override
  String get name => 'Planner';

  /// Needs that call for step-free routing in the planner.
  static bool needsStepFree(TripBrief b) => b.accessibilityNeeds.any(
    (n) =>
        n == AccessibilityNeed.wheelchair ||
        n == AccessibilityNeed.limitedMobility ||
        n == AccessibilityNeed.elderlyCare,
  );

  @override
  Future<AgentResult<TripPlan>> run(TripBrief brief) async {
    final plan = await _generate(
      destination: brief.destination!,
      originCity: brief.originCity!,
      days: brief.days,
      isAccessible: needsStepFree(brief),
      travelStyle:
          '${brief.style?.label ?? 'sustainable'} trip. '
          'Traveller brief: ${brief.toPromptSummary()}',
    );
    return AgentOk(
      plan.copyWith(
        travelDates: dateRangeLabel(brief.start!, brief.end!),
        title: '${brief.destination} — ${brief.days}-day trip',
      ),
    );
  }
}
