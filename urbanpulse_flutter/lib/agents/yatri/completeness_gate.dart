import 'dart:math' as math;

import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../raah/day_planner.dart';
import '../runtime/agent_kind.dart';
import '../runtime/report.dart';
import '../safar/transport_planner.dart';

/// What still keeps the plan from being a whole trip.
enum GapKind {
  /// No places to visit at all.
  places,

  /// A day with time to spare but too few places on it.
  day,

  /// The journey there and back leaves no real time at the destination.
  time,

  /// Nowhere to stay, and the traveller has not said they will arrange it.
  stay,

  /// The journey could not be planned.
  journey,
}

class PlanGap {
  const PlanGap({required this.id, required this.kind, this.day, this.date, this.visits = 0, this.needed = 0, this.freeMinutes = 0});

  /// Stable across passes, so an answer is remembered for the same gap.
  final String id;
  final GapKind kind;

  /// 1-based day number and ISO date, for a [GapKind.day] gap.
  final int? day;
  final String? date;
  final int visits;
  final int needed;
  final int freeMinutes;
}

/// Yatri's goal: the plan is finished only when every day the traveller is at
/// the destination has enough to do, there is somewhere to stay, and the
/// journey is planned, or the traveller has knowingly accepted a gap. The
/// planner loops until this passes; it never ends because time ran out.
abstract final class PlanCompleteness {
  /// Places a full free day should hold, by pace (one fewer for a slow pace).
  static int paceMinimum(TripPace? pace, {bool slow = false}) {
    final base = switch (pace) {
      TripPace.relaxed => 2,
      TripPace.packed => 4,
      _ => 3,
    };
    return slow ? math.max(1, base - 1) : base;
  }

  /// Places a day with [freeMinutes] at the destination needs: the pace
  /// minimum for five free hours or more, one for three hours, none for less.
  static int needed(int freeMinutes, int paceMin) => freeMinutes >= 300 ? paceMin : (freeMinutes >= 180 ? 1 : 0);

  static int visitsOn(ItineraryDay d) => d.slots.where((s) => s.kind == SlotKind.visit).length;

  static List<PlanGap> check({
    required DayPlanResult? days,
    required TripBrief brief,
    required bool hasPlaces,
    required bool hasStay,
    required bool journeyNeeded,
    required bool hasJourney,
    Set<String> accepted = const {},
    bool slowPace = false,
  }) {
    final gaps = <PlanGap>[];
    void add(PlanGap g) {
      if (!accepted.contains(g.id)) gaps.add(g);
    }

    if (!hasPlaces) add(const PlanGap(id: 'gap.places', kind: GapKind.places));
    if (journeyNeeded && !hasJourney) add(const PlanGap(id: 'gap.journey', kind: GapKind.journey));
    if (!hasStay) add(const PlanGap(id: 'gap.stay', kind: GapKind.stay));

    final d = days;
    if (d != null && hasPlaces) {
      final free = d.freeMinutes;
      if (free.isNotEmpty && free.every((m) => m < 180) && hasJourney) {
        add(const PlanGap(id: 'gap.time', kind: GapKind.time));
      } else {
        final paceMin = paceMinimum(brief.pace, slow: slowPace);
        for (var i = 0; i < d.days.length && i < free.length; i++) {
          final want = needed(free[i], paceMin);
          final have = visitsOn(d.days[i]);
          if (have < want) {
            final date = d.days[i].date;
            add(PlanGap(
              id: 'gap.day.${i + 1}',
              kind: GapKind.day,
              day: i + 1,
              date: '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
              visits: have,
              needed: want,
              freeMinutes: free[i],
            ));
          }
        }
      }
    }
    return gaps;
  }

  // --- the questions, when Yatri has nothing left to try on its own -----------

  /// Options already chosen for a gap are not offered again, so every gap ends
  /// in a finite number of questions: the last one only offers acceptance.
  static Issue issueFor(
    PlanGap gap, {
    required String destination,
    Set<String> used = const {},
    bool rainBanned = false,
    int nearMisses = 0,
    TransportPlan? transport,
    TransportLeg? chosen,
    String? origin,
    int attempt = 0,
  }) {
    final options = <IssueOption>[];
    void offer(IssueOption o) {
      if (!used.contains(o.id)) options.add(o);
    }

    final String message;
    final String why;
    switch (gap.kind) {
      case GapKind.places:
        message = 'I could not find places to visit near $destination that suit your group. How would you like to go on?';
        why = 'Bhatkanti searched maps, Wikipedia, the web and its own knowledge. A wider area often turns up sights in the next town.';
        if (nearMisses > 0) {
          offer(IssueOption(id: 'nearMiss', label: 'Show me places that do not fully match; I will pick', subtitle: '$nearMisses to choose from', effect: const {'action': 'pickNearMiss'}, recommended: true));
        }
        offer(IssueOption(id: 'wider', label: 'Look further out', effect: const {'action': 'widenPlaces'}, recommended: nearMisses == 0));
        offer(const IssueOption(id: 'accept', label: 'Leave the days free; I will explore on my own', effect: {'action': 'acceptGap'}));
      case GapKind.day:
        final hours = (gap.freeMinutes / 60).round();
        message = 'Day ${gap.day} has ${gap.visits == 0 ? 'nothing' : 'only ${gap.visits} place${gap.visits == 1 ? '' : 's'}'} planned, '
            'with about $hours free hour${hours == 1 ? '' : 's'} in $destination${rainBanned ? ' (outdoor places are off that day because of rain)' : ''}. '
            'How should I fill it?';
        why = 'Yatri keeps planning until every day you are there has enough to do, or you tell it a lighter day is fine.';
        if (rainBanned) {
          offer(IssueOption(
            id: 'rain',
            label: 'Keep outdoor places on day ${gap.day}; I will carry rain gear',
            effect: {'action': 'unbanOutdoor', 'dates': [?gap.date]},
            recommended: true,
          ));
        }
        if (nearMisses > 0) {
          offer(IssueOption(
            id: 'nearMiss',
            label: 'Show me places that do not fully match; I will pick',
            subtitle: '$nearMisses to choose from, each with what does not fit',
            effect: const {'action': 'pickNearMiss'},
            recommended: !rainBanned,
          ));
        }
        offer(IssueOption(id: 'wider', label: 'Look further out for more places', effect: const {'action': 'widenPlaces'}, recommended: !rainBanned && nearMisses == 0));
        offer(IssueOption(id: 'accept', label: 'Keep day ${gap.day} light; free time is fine', effect: const {'action': 'acceptGap'}));
      case GapKind.time:
        final mins = chosen?.durationMin ?? 0;
        message = 'The journey takes about ${durationLabel(mins)} each way, which leaves almost no time in $destination. What should I do?';
        why = 'Every day of the trip is spent travelling. A faster way there gives you time to see the place.';
        final faster = [
          for (var i = 0; i < (transport?.options.length ?? 0); i++)
            if (transport!.options[i].durationMin < mins * 0.7) (i, transport.options[i]),
        ]..sort((a, b) => a.$2.durationMin.compareTo(b.$2.durationMin));
        for (final (i, leg) in faster.take(2)) {
          offer(IssueOption(
            id: 'faster.${leg.mode.name}',
            label: 'Go by ${leg.mode.label.toLowerCase()} instead (${durationLabel(leg.durationMin)})',
            subtitle: '${leg.isEstimated ? '≈ ' : ''}${rupees(leg.costInr)} each way',
            effect: {'action': 'swapTransport', 'index': i},
            recommended: identical(leg, faster.first.$2),
          ));
        }
        offer(IssueOption(id: 'accept', label: 'Keep it; I know the trip is mostly travel', effect: const {'action': 'acceptGap'}, recommended: faster.isEmpty));
      case GapKind.stay:
        message = 'I have not found a place to stay in $destination yet. What would you like?';
        why = 'Atithi searched TripAdvisor, OpenStreetMap and the web. A wider area often finds stays in the next town.';
        offer(const IssueOption(id: 'wider', label: 'Search a wider area for stays', effect: {'action': 'widenStay'}, recommended: true));
        offer(const IssueOption(id: 'accept', label: 'I will arrange my own stay', effect: {'action': 'stayOwn'}));
      case GapKind.journey:
        message = 'I could not plan the journey from ${origin ?? 'your starting point'} to $destination. What should I do?';
        why = 'Travel time, cost and CO₂ need both ends of the journey; a second try often works when a service was busy.';
        offer(const IssueOption(id: 'retry', label: 'Try planning the journey again', effect: {'action': 'retryJourney'}, recommended: true));
        offer(const IssueOption(id: 'accept', label: 'Plan without it; I will book the journey myself', effect: {'action': 'acceptGap'}));
    }
    // Acceptance is always there, so the traveller can always end a gap.
    if (!options.any((o) => o.effect['action'] == 'acceptGap' || o.effect['action'] == 'stayOwn')) {
      options.add(const IssueOption(id: 'accept', label: 'That is fine as it is', effect: {'action': 'acceptGap'}));
    }
    if (!options.any((o) => o.recommended)) {
      options[0] = IssueOption(
        id: options[0].id,
        label: options[0].label,
        subtitle: options[0].subtitle,
        badge: options[0].badge,
        effect: options[0].effect,
        recommended: true,
      );
    }
    return Issue(
      id: '${gap.id}#$attempt',
      agent: AgentKind.yatri,
      severity: IssueSeverity.blocking,
      message: message,
      why: why,
      options: options,
    );
  }
}
