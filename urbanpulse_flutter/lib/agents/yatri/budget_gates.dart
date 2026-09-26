import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../hisab/budget_engine.dart';
import '../runtime/agent_kind.dart';
import '../runtime/report.dart';
import '../safar/transport_planner.dart';
import 'hotel_gates.dart';

/// Hisab's gate: when the plan costs more than the traveller said they can
/// spend, it finds real ways to bring it down (a cheaper stay, a cheaper way to
/// travel, dropping the priciest paid places) and Yatri asks which to take.
abstract final class BudgetGates {
  static List<Issue> check({
    required Budget budget,
    required HotelOption? hotel,
    required List<HotelOption> hotelAlternatives,
    required TransportPlan? transport,
    required TransportLeg? chosenTransport,
    required List<ItineraryDay> days,
    required Map<String, Hotspot> hotspots,
    required TripBrief brief,
    Set<String> alreadyDropped = const {},
  }) {
    final cap = brief.budgetMaxInr;
    final total = budget.totalInr;
    if (cap == null || total <= cap) return const [];
    final over = total - cap;
    final nights = BudgetEngine.nights(brief);
    final rooms = BudgetEngine.rooms(brief);
    final options = <IssueOption>[];
    var largest = 0;
    String? largestId;

    void add(IssueOption o, int saving) {
      options.add(o);
      if (saving > largest) {
        largest = saving;
        largestId = o.id;
      }
    }

    // A cheaper stay that suits the group at least as well: saving money never
    // swaps a confirmed-accessible stay for a less suitable one.
    final needs = {for (final n in brief.accessibilityNeeds) if (n != AccessibilityNeed.none) n};
    final cur = hotel?.nightlyInr;
    if (hotel != null && cur != null) {
      final cheaper = [
        for (final h in hotelAlternatives)
          if (h.id != hotel.id && h.nightlyInr != null && h.nightlyInr! < cur && h.meets(needs) && HotelGates.fitsAsWell(h, hotel, needs)) h,
      ]..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
      final alt = cheaper.firstOrNull;
      if (alt != null) {
        final saving = (cur - alt.nightlyInr!) * nights * rooms;
        add(
          IssueOption(
            id: 'hotel',
            label: 'Stay at ${alt.name} instead',
            subtitle: 'saves about ${rupees(saving)}${alt.rating == null ? '' : ' · rated ${alt.rating!.toStringAsFixed(1)}'}',
            effect: {'action': 'swapHotel', 'hotelId': alt.id, 'saving': saving},
          ),
          saving,
        );
      }
    }

    // A cheaper way to travel that is not worse for the group's access needs.
    if (transport != null && chosenTransport != null) {
      final curPenalty = TransportPlanner.accessPenalty(needs, chosenTransport.mode);
      final cheaper = [
        for (var i = 0; i < transport.options.length; i++)
          if (transport.options[i].costInr < chosenTransport.costInr &&
              TransportPlanner.accessPenalty(needs, transport.options[i].mode) <= curPenalty + 0.05)
            i,
      ]..sort((a, b) => transport.options[a].costInr.compareTo(transport.options[b].costInr));
      if (cheaper.isNotEmpty) {
        final leg = transport.options[cheaper.first];
        final saving = (chosenTransport.costInr - leg.costInr) * 2;
        add(
          IssueOption(
            id: 'transport',
            label: 'Travel by ${leg.mode.label.toLowerCase()} instead',
            subtitle: 'saves about ${rupees(saving)} · ${leg.durationMin ~/ 60}h ${leg.durationMin % 60}m each way',
            effect: {'action': 'swapTransport', 'index': cheaper.first, 'saving': saving},
          ),
          saving,
        );
      }
    }

    // Drop the paid places that matter least.
    final paid = [for (final p in BudgetEngine.paidVisits(days, hotspots)) if (!alreadyDropped.contains(p.id)) p];
    if (paid.isNotEmpty) {
      final drop = <({String id, String name, int fee, double score})>[];
      var saved = 0;
      final maxDrop = (paid.length / 2).ceil().clamp(1, 6);
      for (final p in paid) {
        if (drop.length >= maxDrop) break;
        drop.add(p);
        saved += p.fee;
        if (saved >= over) break;
      }
      add(
        IssueOption(
          id: 'fees',
          label: 'Skip ${drop.length} paid place${drop.length == 1 ? '' : 's'}: ${drop.take(3).map((d) => d.name).join(', ')}${drop.length > 3 ? '…' : ''}',
          subtitle: 'saves about ${rupees(saved)}',
          effect: {'action': 'dropPlaces', 'ids': [for (final d in drop) d.id], 'saving': saved},
        ),
        saved,
      );
    }

    final tolerable = over <= cap * 0.05;
    options.add(
      IssueOption(
        id: 'accept',
        label: 'Keep the plan as it is',
        subtitle: 'about ${rupees(over)} over your budget',
        effect: const {'action': 'accept'},
      ),
    );

    // The recommendation: keep it when the overrun is tiny, else the biggest saver.
    final recId = tolerable ? 'accept' : (largestId ?? 'accept');
    final withRec = [
      for (final o in options)
        IssueOption(
          id: o.id,
          label: o.label,
          subtitle: o.subtitle,
          badge: o.badge,
          effect: o.effect,
          recommended: o.id == recId,
        ),
    ];

    return [
      Issue(
        id: 'budget.over@${(over / 500).round() * 500}',
        agent: AgentKind.hisab,
        severity: IssueSeverity.blocking,
        message: 'The plan comes to about ${rupees(total)}, ${rupees(over)} over your budget of ${rupees(cap)}. '
            '${withRec.length > 1 ? 'Here is what could bring it down.' : ''}',
        why: 'Hisab added up the stay, travel, local transport, entry fees, meals and a small buffer. '
            'Prices marked as estimates may change, so treat the total as a guide.',
        options: withRec,
      ),
    ];
  }
}
