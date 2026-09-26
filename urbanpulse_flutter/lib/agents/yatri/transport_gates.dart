import '../../core/formatting.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../safar/transport_planner.dart';
import '../runtime/agent_kind.dart';
import '../runtime/report.dart';

/// Yatri's checks on Safar's answer: with a real choice of modes, the traveller
/// decides, seeing time, cost and CO₂ side by side.
abstract final class TransportGates {
  static List<Issue> check(TransportPlan plan) {
    if (plan.options.length < 2) return const [];
    final q = plan.query;
    final rec = plan.recommendedIndex;
    return [
      Issue(
        id: 'transport.choice',
        agent: AgentKind.safar,
        severity: IssueSeverity.info,
        message: 'How would you like to get from ${q.originName} to ${q.destinationName}? '
            'About ${plan.distanceKm.round()} km each way.',
        why: 'Safar compared each option on time, cost and CO₂, and against your access needs. '
            'The recommended one balances them for what you told me matters. You know your comfort, so the choice is yours.',
        options: [
          for (var i = 0; i < plan.options.length; i++) _option(plan, i, i == rec),
        ],
      ),
    ];
  }

  static IssueOption _option(TransportPlan plan, int i, bool recommended) {
    final l = plan.options[i];
    final access = _accessNote(plan, l);
    return IssueOption(
      id: l.mode.name,
      label: l.mode.label,
      subtitle: '${durationLabel(l.durationMin)} · ${rupees(l.costInr)} total${access == null ? '' : ' · $access'}',
      badge: '${fixed(l.co2Grams / 1000, 0)} kg CO₂',
      effect: {'mode': l.mode.name, 'index': i},
      recommended: recommended,
    );
  }

  static String? _accessNote(TransportPlan plan, TransportLeg l) {
    final needs = plan.query.needs.where((n) => n.name != 'none').toList();
    if (needs.isEmpty) return null;
    final levels = [for (final n in needs) ModeAccess.of(l.mode, n).$1];
    if (levels.contains(SupportLevel.no)) return 'access: not suited';
    if (levels.every((v) => v == SupportLevel.yes)) return 'access: suited';
    return 'access: needs assistance';
  }

  /// Index of the option the traveller picked, or the recommended one.
  static int indexOf(TransportPlan plan, IssueOption option) {
    final i = option.effect['index'];
    if (i is int && i >= 0 && i < plan.options.length) return i;
    return plan.recommendedIndex;
  }
}
