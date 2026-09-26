import '../../core/formatting.dart';
import '../../services/data/ai_estimator.dart';
import '../runtime/agent_kind.dart';
import '../runtime/report.dart';
import '../runtime/task_board.dart';
import '../yatri/transport_gates.dart';
import 'transport_planner.dart';

/// Safar, the transport planner. Numbers come from the deterministic planner;
/// the model, when available, only adds a labelled remark about whether a
/// direct service is likely.
class SafarAgent {
  SafarAgent({this.estimator});

  final AiEstimator? estimator;

  Future<AgentReport> run(TaskContext ctx, TransportQuery query) async {
    ctx.say(
      'is comparing ways to get from ${query.originName} to ${query.destinationName}',
      why: 'Safar compares travel time, cost and CO₂ for the modes you picked, and checks each against your access needs.',
    );
    TransportPlan plan;
    try {
      plan = TransportPlanner.plan(query);
    } catch (_) {
      return AgentReport.failed(ctx.agent, 'Safar could not work out the journey');
    }

    if (plan.isEmpty) {
      return AgentReport(
        agent: ctx.agent,
        status: ReportStatus.done,
        summary: plan.distanceKm < TransportPlanner.localOnlyKm
            ? 'no long-distance travel is needed'
            : 'found no practical way to travel',
        payload: plan,
        why: plan.assumptions.join(' '),
      );
    }

    final est = estimator;
    if (est != null && !ctx.cancelled) {
      final remarks = await _remarks(est, plan);
      if (remarks.isNotEmpty) {
        plan = TransportPlan(
          query: plan.query,
          options: plan.options,
          recommendedIndex: plan.recommendedIndex,
          distanceKm: plan.distanceKm,
          assumptions: plan.assumptions,
          notes: remarks,
        );
      }
    }

    final best = plan.recommended!;
    return AgentReport(
      agent: ctx.agent,
      status: ReportStatus.degraded, // fares and times are estimates
      summary: 'found ${plan.options.length} way${plan.options.length == 1 ? '' : 's'} to travel; '
          '${best.mode.label.toLowerCase()} looks best (${durationLabel(best.durationMin)}, ${rupees(best.costInr)})',
      payload: plan,
      issues: TransportGates.check(plan),
      why: 'Times, fares and CO₂ are estimated from typical speeds and rates for about ${plan.distanceKm.round()} km. Check live fares before booking.',
    );
  }

  /// One cautious model call: is a direct service likely for each mode?
  Future<Map<String, String>> _remarks(AiEstimator est, TransportPlan plan) async {
    final q = plan.query;
    final items = {
      for (final l in plan.options)
        l.mode.name: {
          'mode': l.mode.label,
          'from': q.originName,
          'to': q.destinationName,
          'approxKm': plan.distanceKm.round(),
        },
    };
    try {
      final filled = await est.fillMany(
        agent: AgentKind.safar,
        subject: 'travel from ${q.originName} to ${q.destinationName}',
        items: items,
        fields: const {
          'remark': 'one short sentence: is a direct service of this mode likely, or does it usually need a change or a transfer to a nearby station or airport? null if unsure',
        },
      );
      if (filled == null) return const {};
      final out = <String, String>{};
      for (final e in filled.entries) {
        final v = e.value['remark']?.value;
        if (v is String && v.trim().isNotEmpty && v.length < 220) out[e.key] = '${v.trim()} (AI-estimated)';
      }
      return out;
    } catch (_) {
      return const {};
    }
  }
}
