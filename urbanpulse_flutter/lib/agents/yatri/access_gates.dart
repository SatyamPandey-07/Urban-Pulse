import '../../core/formatting.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../raah/day_planner.dart';
import '../runtime/agent_kind.dart';
import '../runtime/report.dart';
import '../safar/transport_planner.dart';
import '../saksham/audit_engine.dart';

/// What Yatri does about the audit: quietly replace unsuitable minor places,
/// and ask the traveller when the fix touches something they chose or a top sight.
class AccessFixes {
  const AccessFixes({this.autoReplaceIds = const [], this.issues = const []});

  /// Minor places a real source says do not suit the group: swapped for better
  /// fits without troubling the traveller.
  final List<String> autoReplaceIds;
  final List<Issue> issues;
}

abstract final class AccessGates {
  /// A failing place at least this important is worth asking about.
  static const askImportance = 0.7;

  static AccessFixes check({
    required AuditResult result,
    required Set<AccessibilityNeed> needs,
    HotelOption? hotel,
    List<HotelOption> hotelAlternatives = const [],
    TransportPlan? transport,
    TransportLeg? chosenTransport,
  }) {
    final auto = <String>[];
    final issues = <Issue>[];

    // The stay the traveller chose does not suit a need.
    final badHotel = result.failedHotel;
    if (badHotel != null && hotel != null) {
      final alts = [
        for (final h in hotelAlternatives)
          if (h.id != hotel.id && h.meets(needs) && !_fails(h, needs)) h,
      ].take(2).toList();
      issues.add(
        Issue(
          id: 'access.hotel@${hotel.id}',
          agent: AgentKind.saksham,
          severity: IssueSeverity.blocking,
          message: '${hotel.name} is reported as not suiting ${_needsPhrase(badHotel.needs)}. '
              '${alts.isEmpty ? 'I found no better stay among the options.' : 'Would you like to switch?'}',
          why: 'Saksham audits every step of the trip for each need in your group. A real source says this stay does not work, so it is worth deciding now.',
          options: [
            for (var i = 0; i < alts.length; i++)
              IssueOption(
                id: 'hotel.${alts[i].id}',
                label: 'Stay at ${alts[i].name} instead',
                subtitle: alts[i].nightlyInr == null ? null : '${alts[i].priceIsEstimated ? '≈ ' : ''}${rupees(alts[i].nightlyInr!)} a night',
                effect: {'action': 'swapHotel', 'hotelId': alts[i].id},
                recommended: i == 0,
              ),
            IssueOption(id: 'keep', label: 'Keep ${hotel.name}; I will confirm with them', effect: const {'action': 'accept'}, recommended: alts.isEmpty),
          ],
        ),
      );
    }

    // The way of travelling does not suit a need.
    final badLeg = result.failedJourney;
    if (badLeg != null && chosenTransport != null && transport != null && badLeg.id.startsWith('intercity')) {
      final cur = TransportPlanner.accessPenalty(needs, chosenTransport.mode);
      final better = [
        for (var i = 0; i < transport.options.length; i++)
          if (transport.options[i].mode != chosenTransport.mode && TransportPlanner.accessPenalty(needs, transport.options[i].mode) < cur) i,
      ]..sort((a, b) => TransportPlanner.accessPenalty(needs, transport.options[a].mode).compareTo(TransportPlanner.accessPenalty(needs, transport.options[b].mode)));
      if (better.isNotEmpty) {
        issues.add(
          Issue(
            id: 'access.transport@${chosenTransport.mode.name}',
            agent: AgentKind.saksham,
            severity: IssueSeverity.blocking,
            message: '${chosenTransport.mode.label} is reported as not suiting ${_needsPhrase(badLeg.needs)}. Would you like to travel another way?',
            why: 'Saksham checks the journey there and back as well as the places, since a trip is only accessible if every step is.',
            options: [
              for (var j = 0; j < better.length.clamp(0, 2); j++)
                IssueOption(
                  id: 'mode.${transport.options[better[j]].mode.name}',
                  label: 'Travel by ${transport.options[better[j]].mode.label.toLowerCase()}',
                  subtitle: '${durationLabel(transport.options[better[j]].durationMin)} · ${rupees(transport.options[better[j]].costInr)}',
                  effect: {'action': 'swapTransport', 'index': better[j]},
                  recommended: j == 0,
                ),
              const IssueOption(id: 'keep', label: 'Keep it; I will arrange assistance', effect: {'action': 'accept'}),
            ],
          ),
        );
      }
    }

    // Places: the minor ones are swapped quietly, the top sights are asked about.
    final major = <AccessFailure>[];
    for (final f in result.failedPlaces) {
      if (f.importance >= askImportance) {
        major.add(f);
      } else {
        auto.add(f.id);
      }
    }
    if (major.isNotEmpty) {
      final names = major.take(3).map((f) => f.name).join(', ');
      issues.add(
        Issue(
          id: 'access.places@${major.map((f) => f.id).join(',')}',
          agent: AgentKind.saksham,
          severity: IssueSeverity.warning,
          message: '${major.length == 1 ? 'A top sight, $names, is' : 'Some top sights ($names) are'} reported as not suiting ${_needsPhrase({for (final f in major) ...f.needs}.toList())}. What should I do?',
          why: 'These are among the best places for your trip, so Yatri asks rather than dropping them quietly.',
          options: [
            IssueOption(
              id: 'replace',
              label: 'Replace ${major.length == 1 ? 'it' : 'them'} with places that work for the group',
              effect: {'action': 'replacePlaces', 'ids': [for (final f in major) f.id]},
              recommended: true,
            ),
            const IssueOption(id: 'keep', label: 'Keep them; I will manage', effect: {'action': 'accept'}),
          ],
        ),
      );
    }
    return AccessFixes(autoReplaceIds: auto, issues: issues);
  }

  static bool _fails(HotelOption h, Set<AccessibilityNeed> needs) => needs.any((n) => h.access[n]?.level == SupportLevel.no);

  static String _needsPhrase(List<AccessibilityNeed> needs) {
    final labels = {
      for (final n in needs)
        switch (n) {
          AccessibilityNeed.wheelchair => 'wheelchair access',
          AccessibilityNeed.limitedMobility => 'step-free access',
          AccessibilityNeed.visual => 'visual impairment',
          AccessibilityNeed.hearing => 'hearing impairment',
          AccessibilityNeed.elderlyCare => 'elderly guests',
          AccessibilityNeed.serviceAnimal => 'a service animal',
          AccessibilityNeed.cognitiveSensory => 'sensory or cognitive needs',
          AccessibilityNeed.otherSpecial => 'your special needs',
          AccessibilityNeed.none => 'your needs',
        },
    }.toList();
    if (labels.isEmpty) return 'your needs';
    if (labels.length == 1) return labels.single;
    return '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
  }
}

/// Raah's gate on the weather: outdoor places on a day of heavy rain.
abstract final class RainGates {
  static List<Issue> check(DayPlanResult r, {Set<String> banned = const {}}) {
    final open = [for (final c in r.rainConflicts) if (!banned.contains(c.date)) c];
    if (open.isEmpty) return const [];
    final lines = [
      for (final c in open.take(3))
        'Day ${c.day}${c.summary.isEmpty ? '' : ' (${c.summary})'}: ${c.places.take(3).map((p) => p.name).join(', ')}',
    ];
    return [
      Issue(
        id: 'weather.rain@${open.map((c) => c.date).join(',')}',
        agent: AgentKind.raah,
        severity: IssueSeverity.warning,
        message: 'Heavy rain is expected on ${open.length == 1 ? 'one day' : '${open.length} days'} with outdoor plans:\n${lines.join('\n')}\nWhat should I do?',
        why: 'Raah read the weather for your dates. Outdoor sights in heavy rain are often closed, slippery or simply miserable, and worse for some access needs.',
        options: [
          IssueOption(
            id: 'swap',
            label: 'Move outdoor plans to drier days, and use indoor places on the wet ones',
            effect: {'action': 'banOutdoor', 'dates': [for (final c in open) c.date]},
            recommended: true,
          ),
          const IssueOption(id: 'keep', label: 'Keep the plan; I will carry rain gear', effect: {'action': 'accept'}),
        ],
      ),
    ];
  }
}
