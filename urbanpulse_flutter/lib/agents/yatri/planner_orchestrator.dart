import 'dart:async';

import 'package:latlong2/latlong.dart';

import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../models/yatri_question.dart';
import '../../services/data/location_key_resolver.dart';
import '../atithi/atithi_agent.dart';
import '../atithi/hotel_finder.dart';
import '../hisab/hotel_budget.dart';
import '../runtime/agent_kind.dart';
import '../runtime/agent_toolkit.dart';
import '../runtime/plan_clock.dart';
import '../runtime/report.dart';
import '../runtime/task_board.dart';
import '../runtime/task_graph.dart';
import 'hotel_gates.dart';

/// Puts a question in front of the traveller and waits for the answer.
typedef AskUser = Future<YatriAnswer> Function(YatriQuestion question);

enum PlanStatus {
  /// The trip was planned as far as this stage goes.
  planned,

  /// The destination could not be found on a map; the traveller must give another.
  unlocatable,

  /// Something went wrong badly enough that nothing useful came out.
  failed,
}

/// What the planner hands back to the app.
class PlanOutcome {
  const PlanOutcome({
    required this.status,
    required this.summary,
    this.hotel,
    this.hotels,
    this.center,
    this.notes = const [],
  });

  factory PlanOutcome.failed(String summary) => PlanOutcome(status: PlanStatus.failed, summary: summary);

  final PlanStatus status;
  final String summary;

  /// The stay the traveller (or Yatri) chose, or null if there was none.
  final HotelOption? hotel;

  /// Everything Atithi found, for the record and the map.
  final HotelSearchResult? hotels;
  final LatLng? center;

  /// Caveats to show with the plan: estimates used, sources that failed.
  final List<String> notes;
}

/// Yatri: the only agent that decides. It reads the brief, allocates work to
/// the workers as nodes of the live task graph, checks what comes back against
/// the gates, and when two goals collide (access and budget, say) it asks the
/// traveller with concrete options instead of choosing for them. The loop runs
/// until the stay is settled or there is nothing more to try.
///
/// Everything here is deterministic policy over the workers' reports, so a
/// model outage can never stop a plan.
class PlannerOrchestrator {
  PlannerOrchestrator({
    required this.toolkit,
    required this.ask,
    TaskGraph? graph,
    PlanClock? clock,
    this.maxSearches = 3,
    this.maxChoices = 5,
  }) : graph = graph ?? TaskGraph(),
       clock = clock ?? PlanClock() {
    board = TaskBoard(graph: this.graph, clock: this.clock);
  }

  final AgentToolkit toolkit;
  final AskUser ask;
  final TaskGraph graph;
  final PlanClock clock;
  late final TaskBoard board;

  /// How many times the hotel search may be repeated with new constraints.
  final int maxSearches;

  /// Hotels offered to the traveller to choose from.
  final int maxChoices;

  Future<PlanOutcome> run(TripBrief brief) async {
    var outcome = PlanOutcome.failed('Planning did not finish');
    await board.submit(
      TaskSpec(
        id: 'yatri.plan',
        agent: AgentKind.yatri,
        title: 'Plan your trip',
        why: 'Yatri is the only agent that decides. It hands work to the specialists, checks what they bring back and asks you when a choice is yours.',
        timeout: const Duration(minutes: 4),
      ),
      (ctx) async {
        outcome = await _plan(ctx, brief);
        return AgentReport(
          agent: AgentKind.yatri,
          status: outcome.status == PlanStatus.planned ? ReportStatus.done : ReportStatus.degraded,
          summary: outcome.summary,
        );
      },
    );
    return outcome;
  }

  // --- Yatri's plan ---------------------------------------------------------

  Future<PlanOutcome> _plan(TaskContext ctx, TripBrief brief) async {
    final destination = brief.destination?.trim() ?? '';
    if (destination.isEmpty || brief.start == null || brief.end == null) {
      return PlanOutcome.failed('The brief is missing a destination or dates');
    }

    ctx.say(
      'read your brief: ${brief.days} day${brief.days == 1 ? '' : 's'} in $destination',
      why: 'Yatri starts by working out what each specialist needs to know.',
      kind: FeedKind.decide,
    );

    final center = await _locate(destination);
    if (center == null) {
      ctx.say(
        'could not find “$destination” on the map',
        why: 'Every search is centred on the destination, so an unknown place cannot be planned.',
        kind: FeedKind.warn,
      );
      return PlanOutcome(
        status: PlanStatus.unlocatable,
        summary: 'I could not find “$destination” on the map',
      );
    }

    final toolset = toolkit.newPlan();
    final resolver = LocationKeyResolver(
      xotelo: toolkit.xotelo,
      geocode: _geocode,
      llm: toolkit.llm,
      search: toolset.search,
      cache: toolkit.cache,
    );
    final finder = HotelFinder(
      resolver: resolver,
      xotelo: toolkit.xotelo,
      overpass: toolkit.overpass,
      geoapify: toolkit.geoapify,
      tools: toolset.registry,
      llm: toolkit.llm,
      estimator: toolkit.estimator,
      fetchPage: toolset.fetch,
    );
    final atithi = AtithiAgent(finder);

    var query = HotelQuery(
      destination: destination,
      center: center,
      checkIn: brief.start!,
      checkOut: brief.end!,
      rooms: HotelBudget.roomsFor(brief),
      adults: HotelBudget.adultsFor(brief),
      needs: brief.accessibilityNeeds,
      nightlyCapInr: HotelBudget.nightlyCapInr(brief),
      preferEco: brief.sustainability == SustainabilityPriority.greenest || brief.stayTypes.contains(StayType.ecoStay),
      notes: _notes(brief),
    );

    final asked = <String>{};
    HotelSearchResult? found;
    var skipped = false;

    for (var round = 0; round <= maxSearches; round++) {
      final atithiId = 'atithi.hotels.$round';
      final report = await ctx.delegate(
        TaskSpec(
          id: atithiId,
          agent: AgentKind.atithi,
          title: round == 0 ? 'Find hotels' : 'Search again',
          goal: 'Find stays for ${query.nights} nights',
          why: round == 0
              ? 'Yatri needs somewhere to base the plan. Atithi searches hotels, prices and access details.'
              : 'You changed what the search should look for, so Atithi is trying again.',
          timeout: const Duration(seconds: 40),
        ),
        (c) => atithi.run(c, query),
        say: round == 0 ? 'allocated the hotel search to Atithi' : 're-tasked Atithi with the new limits',
      );

      final result = report.payload is HotelSearchResult ? report.payload as HotelSearchResult : null;
      if (result == null) {
        ctx.say(
          'Atithi could not search for hotels; carrying on without a stay',
          why: 'A failed specialist never stops the plan: Yatri routes around it and says so.',
          kind: FeedKind.warn,
        );
        break;
      }
      found = result;

      final hisab = await ctx.delegate(
        TaskSpec(
          id: 'hisab.hotels.$round',
          agent: AgentKind.hisab,
          title: 'Check the hotel budget',
          why: 'Hisab checks that a suitable hotel fits your budget before anything is planned around it.',
          parents: [atithiId],
          timeout: const Duration(seconds: 8),
        ),
        (c) async {
          final issues = HotelGates.checkHisab(result);
          return AgentReport(
            agent: c.agent,
            status: ReportStatus.done,
            summary: issues.isEmpty ? 'a suitable stay fits the budget' : 'no suitable stay fits ₹${query.nightlyCapInr} a night',
            issues: issues,
            why: 'About 40% of the trip budget is reserved for the stay.',
          );
        },
        say: 'asked Hisab to check the hotels against your budget',
      );

      final issues = [...report.issues, ...hisab.issues].where((i) => !asked.contains(i.id)).toList();
      if (issues.isEmpty) break;

      // Running out of time or searches: settle for what there is.
      if (round == maxSearches || ctx.degraded) {
        ctx.say(
          'is going with the best hotels found, as time is short',
          why: 'Yatri stops asking once the plan is running long, so you always get a result.',
          kind: FeedKind.decide,
        );
        break;
      }

      final issue = issues.first;
      asked.add(issue.id);
      ctx.say(
        'needs your decision on the hotels',
        why: issue.why,
        kind: FeedKind.ask,
      );
      final option = await _askIssue(ctx, issue);
      ctx.say(
        'you chose: ${option.label}',
        why: 'Yatri acts on your choice and re-plans if needed.',
        kind: FeedKind.decide,
      );
      if (option.effect['action'] == 'skip') {
        skipped = true;
        break;
      }
      final next = HotelGates.apply(query, option);
      if (next == null) break;
      query = next;
    }

    final notes = <String>[
      if (found != null) ...found.warnings,
    ];
    if (skipped || found == null || found.options.isEmpty) {
      return PlanOutcome(
        status: PlanStatus.planned,
        summary: 'Planned without a hotel',
        hotels: found,
        center: center,
        notes: notes,
      );
    }

    final chosen = await _chooseHotel(ctx, found);
    return PlanOutcome(
      status: PlanStatus.planned,
      summary: 'Chose ${chosen.name}',
      hotel: chosen,
      hotels: found,
      center: center,
      notes: notes,
    );
  }

  // --- questions ------------------------------------------------------------

  Future<IssueOption> _askIssue(TaskContext ctx, Issue issue) async {
    final question = YatriQuestion(
      id: 'plan.${issue.id}',
      fields: const [],
      widget: AnswerWidget.mcq,
      defaultText: issue.message,
      reason: IssueKind.conflict,
      agent: AgentKind.yatri.name,
      why: issue.why,
      options: [
        for (final o in issue.options)
          QuestionOption(id: o.id, label: o.label, recommended: o.recommended),
      ],
    );
    final YatriAnswer answer;
    try {
      answer = await ctx.waitForUser(() => ask(question));
    } catch (_) {
      return _recommended(issue);
    }
    if (answer is ChoiceAnswer) {
      for (final o in issue.options) {
        if (o.id == answer.optionId) return o;
      }
    }
    return _recommended(issue);
  }

  static IssueOption _recommended(Issue issue) => issue.options.firstWhere(
    (o) => o.recommended,
    orElse: () => issue.options.first,
  );

  /// The traveller picks the stay; “let Yatri choose” (or running out of time,
  /// or a single candidate) takes the best-ranked one.
  Future<HotelOption> _chooseHotel(TaskContext ctx, HotelSearchResult found) async {
    final options = found.options.take(maxChoices).toList();
    if (options.length == 1 || ctx.degraded) {
      ctx.say(
        'picked ${options.first.name}',
        why: options.length == 1 ? 'It was the only stay that fit.' : 'Time was short, so Yatri took the best-ranked stay.',
        kind: FeedKind.decide,
      );
      return options.first;
    }

    ctx.say(
      'found ${options.length} stays worth a look and is asking which you prefer',
      why: 'The stay is your decision. Yatri ranks them for you, but you know what matters most.',
      kind: FeedKind.ask,
    );
    final needs = {for (final n in found.query.needs) if (n != AccessibilityNeed.none) n};
    final question = YatriQuestion(
      id: 'plan.hotels.choice',
      fields: const [],
      widget: AnswerWidget.hotelChoice,
      defaultText: 'Here are the stays that fit best. Which would you like?',
      reason: IssueKind.optional,
      agent: AgentKind.yatri.name,
      why: 'Ranked by how well each fits your group, budget and location. Access details show where they came from, and anything unconfirmed says so.',
      hotels: options,
      hotelNeeds: needs,
      options: [
        for (final h in options) QuestionOption(id: h.id, label: h.name),
        const QuestionOption(id: autoPick, label: 'Let Yatri choose'),
      ],
    );
    YatriAnswer? answer;
    try {
      answer = await ctx.waitForUser(() => ask(question));
    } catch (_) {
      answer = null;
    }
    HotelOption chosen = options.first;
    if (answer is ChoiceAnswer) {
      for (final h in options) {
        if (h.id == answer.optionId) chosen = h;
      }
    }
    ctx.say(
      'chose ${chosen.name} for your stay',
      why: 'Yatri builds the rest of the plan around this stay.',
      kind: FeedKind.decide,
    );
    return chosen;
  }

  /// The option id meaning “you pick”.
  static const autoPick = 'auto';

  // --- helpers --------------------------------------------------------------

  Future<LatLng?> _geocode(String place) async {
    try {
      final p = await toolkit.geocoder.lookup(place);
      if (p != null) return p;
    } catch (_) {
      // fall through to the next geocoder
    }
    try {
      final g = toolkit.geoapify;
      if (g != null && g.isConfigured) {
        final c = (await g.geocode(place, limit: 1))?.firstOrNull;
        if (c != null) return LatLng(c.lat, c.lon);
      }
    } catch (_) {
      // not found
    }
    return null;
  }

  Future<LatLng?> _locate(String destination) => _geocode(destination);

  static String? _notes(TripBrief brief) {
    final parts = [
      if (brief.stayTypes.isNotEmpty) brief.stayTypes.map((s) => s.label.toLowerCase()).join(' or '),
      if (brief.notes != null && brief.notes!.trim().isNotEmpty) brief.notes!.trim().substring(0, brief.notes!.trim().length.clamp(0, 120)),
    ];
    return parts.isEmpty ? null : parts.join('; ');
  }
}
