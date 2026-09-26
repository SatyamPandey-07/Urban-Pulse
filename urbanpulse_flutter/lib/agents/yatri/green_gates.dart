import '../../core/formatting.dart';
import '../hariyali/carbon_engine.dart';
import '../runtime/agent_kind.dart';
import '../runtime/report.dart';
import '../safar/transport_planner.dart';

/// Yatri's check on Hariyali's answer. Tips are always shown; the traveller is
/// asked only when they said the greenest option matters most and a real swap
/// saves a meaningful share without costing much time or money.
abstract final class GreenGates {
  /// A swap must cut at least this share of the trip's footprint to be worth asking.
  static const minShare = 0.2;

  static List<Issue> check(GreenResult r, GreenInput input, {required bool preferGreenest}) {
    final g = r.greenerJourney;
    final out = input.outbound;
    if (!preferGreenest || g == null || out == null) return const [];
    final total = r.report.co2Kg;
    if (total <= 0 || g.savedKg / total < minShare) return const [];
    // Not a big detour in time or money.
    if (g.extraMinutes > out.durationMin * 0.6) return const [];
    if (g.extraCostInr > out.costInr * 2 * 0.25) return const [];

    final pct = (g.savedKg / total * 100).round();
    return [
      Issue(
        id: 'green.transport@${g.leg.mode.name}',
        agent: AgentKind.hariyali,
        severity: IssueSeverity.info,
        message: 'You said the greenest option matters most. Going by ${g.leg.mode.label.toLowerCase()} instead of ${out.mode.label.toLowerCase()} '
            'would cut about ${fixed(g.savedKg, 0)} kg CO₂ (${pct.clamp(1, 99)}% of this trip\'s footprint). Switch?',
        why: 'Hariyali measured every choice in the plan. This swap is the biggest single saving, and it does not make the journey much longer or dearer or harder for your access needs.',
        options: [
          IssueOption(
            id: 'switch',
            label: 'Go by ${g.leg.mode.label.toLowerCase()}',
            subtitle: '${durationLabel(g.leg.durationMin)} each way · ${rupees(g.leg.costInr)} one way',
            badge: '−${fixed(g.savedKg, 0)} kg CO₂',
            effect: {'action': 'swapTransport', 'index': g.index},
            recommended: true,
          ),
          IssueOption(id: 'keep', label: 'Keep ${out.mode.label.toLowerCase()}', effect: const {'action': 'accept'}),
        ],
      ),
    ];
  }
}
