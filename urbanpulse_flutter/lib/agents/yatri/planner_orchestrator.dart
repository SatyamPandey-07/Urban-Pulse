import 'dart:async';

import 'package:latlong2/latlong.dart';

import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../models/yatri_question.dart';
import '../../services/data/forecast_client.dart';
import '../../services/data/location_key_resolver.dart';
import '../atithi/atithi_agent.dart';
import '../atithi/hotel_finder.dart';
import '../bhatkanti/bhatkanti_agent.dart';
import '../bhatkanti/hotspot_finder.dart';
import '../hariyali/carbon_engine.dart';
import '../hariyali/hariyali_agent.dart';
import '../hisab/budget_engine.dart';
import '../khoji/khoji.dart';
import '../khoji/khoji_agent.dart';
import '../hisab/hotel_budget.dart';
import '../raah/day_planner.dart';
import '../runtime/agent_kind.dart';
import '../runtime/agent_toolkit.dart';
import '../runtime/plan_clock.dart';
import '../runtime/report.dart';
import '../runtime/task_board.dart';
import '../runtime/task_graph.dart';
import '../safar/safar_agent.dart';
import '../safar/transport_planner.dart';
import '../saksham/audit_engine.dart';
import '../saksham/saksham_agent.dart';
import 'access_gates.dart';
import 'budget_gates.dart';
import 'hotel_gates.dart';
import 'hotspot_gates.dart';
import 'itinerary_assembler.dart';
import 'transport_gates.dart';

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
    this.itinerary,
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

  /// The finished plan, when every stage produced one.
  final Itinerary? itinerary;
}

/// What the agents have produced so far. Written by the phases, read by the
/// stages that come after them.
class _State {
  _State(this.brief, this.center);

  final TripBrief brief;
  final LatLng center;
  LatLng? origin;

  HotelSearchResult? hotels;
  HotelOption? hotel;
  bool stayOwn = false;
  String? hotelTask;

  HotspotSearchResult? spots;
  String? spotsTask;

  TransportPlan? transport;
  TransportLeg? chosen;
  String? transportTask;

  Map<String, DayForecast> weather = {};
  String? weatherTask;

  final Set<String> droppedIds = {};
  final Set<String> bannedOutdoor = {};
  final List<String> notes = [];
}

/// Yatri: the only agent that decides. It reads the brief, allocates work to
/// the workers as nodes of the live task graph, checks what comes back against
/// the gates, and when two goals collide (access and budget, say) it asks the
/// traveller with concrete options instead of choosing for them. The loop runs
/// until the plan is settled or there is nothing more to try.
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
    this.hotelsOnly = false,
    DateTime Function()? now,
  }) : graph = graph ?? TaskGraph(),
       clock = clock ?? PlanClock(),
       _now = now ?? DateTime.now {
    board = TaskBoard(graph: this.graph, clock: this.clock);
  }

  final AgentToolkit toolkit;
  final AskUser ask;
  final TaskGraph graph;
  final PlanClock clock;
  late final TaskBoard board;
  final DateTime Function() _now;

  /// How many times a search may be repeated with new constraints.
  final int maxSearches;

  /// Hotels offered to the traveller to choose from.
  final int maxChoices;

  /// Only the hotel stage (used by focused tests).
  final bool hotelsOnly;

  final Set<String> _asked = {};
  Future<void> _askTail = Future.value();

  Future<PlanOutcome> run(TripBrief brief) async {
    var outcome = PlanOutcome.failed('Planning did not finish');
    await board.submit(
      TaskSpec(
        id: 'yatri.plan',
        agent: AgentKind.yatri,
        title: 'Plan your trip',
        why: 'Yatri is the only agent that decides. It hands work to the specialists, checks what they bring back and asks you when a choice is yours.',
        timeout: const Duration(minutes: 6),
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

    final origin = brief.originCity?.trim() ?? '';
    final located = await Future.wait([_geocode(destination), if (!hotelsOnly && origin.isNotEmpty) _locateOrigin(origin)]);
    final center = located.first;
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
    final st = _State(brief, center);
    if (located.length > 1) st.origin = located[1];

    final toolset = toolkit.newPlan();
    final finder = HotelFinder(
      resolver: LocationKeyResolver(
        xotelo: toolkit.xotelo,
        geocode: _geocode,
        llm: toolkit.llm,
        search: toolset.search,
        cache: toolkit.cache,
      ),
      xotelo: toolkit.xotelo,
      overpass: toolkit.overpass,
      geoapify: toolkit.geoapify,
      tools: toolset.registry,
      llm: toolkit.llm,
      estimator: toolkit.estimator,
      fetchPage: toolset.fetch,
    );
    final khoji = KhojiAgent(
      Khoji(
        llm: toolkit.llm,
        budget: toolset.budget,
        search: toolset.search,
        fetchPage: toolset.fetch,
        wikipedia: toolkit.wikipedia,
      ),
    );
    final atithi = AtithiAgent(finder, khoji: hotelsOnly ? null : khoji);

    final hotelQuery = HotelQuery(
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

    if (hotelsOnly) {
      await _hotelPhase(ctx, st, atithi, hotelQuery);
      return _hotelsOnlyOutcome(st);
    }

    // The specialists work at the same time; the traveller is asked one
    // question at a time as their answers come in.
    final bhatkanti = BhatkantiAgent(
      HotspotFinder(
        overpass: toolkit.overpass,
        wikipedia: toolkit.wikipedia,
        geoapify: toolkit.geoapify,
        tools: toolset.registry,
        llm: toolkit.llm,
        estimator: toolkit.estimator,
      ),
      khoji: khoji,
    );
    final safar = SafarAgent(estimator: toolkit.estimator);
    final spotQuery = HotspotQuery(
      destination: destination,
      center: center,
      days: brief.days,
      pace: brief.pace,
      style: brief.style,
      needs: brief.accessibilityNeeds,
      notes: _notes(brief),
      year: brief.start!.year,
    );

    await Future.wait([
      _guardPhase(ctx, 'hotels', () => _hotelPhase(ctx, st, atithi, hotelQuery)),
      _guardPhase(ctx, 'places', () => _hotspotPhase(ctx, st, bhatkanti, spotQuery)),
      _guardPhase(ctx, 'journey', () => _transportPhase(ctx, st, safar)),
      _guardPhase(ctx, 'weather', () => _weatherPhase(ctx, st)),
    ]);

    // Lay out the days, price them, and settle any budget problem.
    final itinerary = await _settle(ctx, st);
    return PlanOutcome(
      status: PlanStatus.planned,
      summary: itinerary == null ? 'Planned without a full itinerary' : 'Planned ${itinerary.dayCount} days in $destination',
      hotel: st.hotel,
      hotels: st.hotels,
      center: center,
      notes: st.notes,
      itinerary: itinerary,
    );
  }

  PlanOutcome _hotelsOnlyOutcome(_State st) => PlanOutcome(
    status: PlanStatus.planned,
    summary: st.hotel == null ? 'Planned without a hotel' : 'Chose ${st.hotel!.name}',
    hotel: st.hotel,
    hotels: st.hotels,
    center: st.center,
    notes: st.notes,
  );

  /// One phase failing must never take the others (or the plan) down.
  Future<void> _guardPhase(TaskContext ctx, String name, Future<void> Function() run) async {
    try {
      await run();
    } catch (_) {
      ctx.say(
        'ran into a problem with the $name, and is carrying on without it',
        why: 'A failed specialist never stops the plan: Yatri routes around it and says so.',
        kind: FeedKind.warn,
      );
    }
  }

  // --- hotels ---------------------------------------------------------------

  Future<void> _hotelPhase(TaskContext ctx, _State st, AtithiAgent atithi, HotelQuery first) async {
    var query = first;
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
          timeout: const Duration(seconds: 55),
        ),
        (c) => atithi.run(c, query),
        say: round == 0 ? 'allocated the hotel search to Atithi' : 're-tasked Atithi with the new limits',
      );
      st.hotelTask = atithiId;

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

      final issues = [...report.issues, ...hisab.issues].where((i) => !_asked.contains(i.id)).toList();
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
      _asked.add(issue.id);
      ctx.say('needs your decision on the hotels', why: issue.why, kind: FeedKind.ask);
      final option = await _askIssue(ctx, issue);
      ctx.say('you chose: ${option.label}', why: 'Yatri acts on your choice and re-plans if needed.', kind: FeedKind.decide);
      if (option.effect['action'] == 'skip') {
        skipped = true;
        break;
      }
      final next = HotelGates.apply(query, option);
      if (next == null) break;
      query = next;
    }

    st.hotels = found;
    if (found != null) st.notes.addAll(found.warnings);
    if (skipped || found == null || found.options.isEmpty) {
      st.stayOwn = skipped;
      return;
    }
    st.hotel = await _chooseHotel(ctx, found);
  }

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
    final answer = await _askQuestion(ctx, question);
    HotelOption chosen = options.first;
    if (answer is ChoiceAnswer) {
      for (final h in options) {
        if (h.id == answer.optionId) chosen = h;
      }
    }
    ctx.say('chose ${chosen.name} for your stay', why: 'Yatri builds the rest of the plan around this stay.', kind: FeedKind.decide);
    return chosen;
  }

  /// The option id meaning “you pick”.
  static const autoPick = 'auto';

  // --- places to visit --------------------------------------------------------

  Future<void> _hotspotPhase(TaskContext ctx, _State st, BhatkantiAgent agent, HotspotQuery first) async {
    var query = first;
    for (var round = 0; round <= 1; round++) {
      final id = 'bhatkanti.spots.$round';
      final report = await ctx.delegate(
        TaskSpec(
          id: id,
          agent: AgentKind.bhatkanti,
          title: round == 0 ? 'Find places to visit' : 'Look further out',
          why: 'A trip needs things to do. Bhatkanti finds about ${query.perDay} places a day, mixing well-known sights with new ones.',
          timeout: const Duration(seconds: 55),
        ),
        (c) => agent.run(c, query),
        say: round == 0 ? 'allocated the search for places to visit to Bhatkanti' : 'asked Bhatkanti to look further out',
      );
      st.spotsTask = id;
      final result = report.payload is HotspotSearchResult ? report.payload as HotspotSearchResult : null;
      if (result == null) {
        ctx.say(
          'Bhatkanti could not search for places; the days will be left open',
          why: 'A failed specialist never stops the plan: Yatri routes around it and says so.',
          kind: FeedKind.warn,
        );
        return;
      }
      st.spots = result;
      st.notes.addAll(result.warnings);

      final issues = report.issues.where((i) => !_asked.contains(i.id)).toList();
      if (issues.isEmpty || ctx.degraded) return;
      final issue = issues.first;
      _asked.add(issue.id);
      ctx.say('needs your taste on the places', why: issue.why, kind: FeedKind.ask);
      final option = await _askIssue(ctx, issue);
      ctx.say('you chose: ${option.label}', why: 'Yatri re-picks the places to match.', kind: FeedKind.decide);

      final mix = HotspotGates.mixOf(option);
      if (mix != null) {
        st.spots = HotspotFinder.reselect(result, mix);
        ctx.say(
          're-picked the places: ${mix.label.toLowerCase()}',
          why: 'No new search was needed: Yatri re-ranked what Bhatkanti had already found.',
          kind: FeedKind.decide,
        );
        return;
      }
      final wider = HotspotGates.widen(query, option);
      if (wider == null) return; // "leave the days open"
      query = wider;
    }
  }

  // --- the journey ----------------------------------------------------------

  Future<void> _transportPhase(TaskContext ctx, _State st, SafarAgent safar) async {
    final brief = st.brief;
    final origin = st.origin;
    if (origin == null) {
      st.notes.add('Your starting point could not be placed on the map, so the journey there is not planned or priced.');
      ctx.say(
        'could not place ${brief.originCity ?? 'your starting point'} on the map, so the journey is skipped',
        why: 'Travel time, cost and CO₂ need both ends of the journey.',
        kind: FeedKind.warn,
      );
      return;
    }
    final query = TransportQuery(
      originName: brief.originCity ?? 'Home',
      destinationName: brief.destination ?? 'Destination',
      origin: origin,
      destination: st.center,
      travellers: BudgetEngine.travellers(brief),
      adults: brief.adults ?? BudgetEngine.travellers(brief),
      children: BudgetEngine.childCount(brief),
      modes: brief.transportModes,
      needs: brief.accessibilityNeeds,
      priority: brief.sustainability,
      departure: brief.start,
    );
    final report = await ctx.delegate(
      TaskSpec(
        id: 'safar.transport',
        agent: AgentKind.safar,
        title: 'Plan the journey',
        why: 'Yatri needs to know how you get there, how long it takes, what it costs and how much CO₂ it emits.',
        timeout: const Duration(seconds: 25),
      ),
      (c) => safar.run(c, query),
      say: 'allocated the journey to Safar',
    );
    st.transportTask = 'safar.transport';
    final plan = report.payload is TransportPlan ? report.payload as TransportPlan : null;
    if (plan == null) {
      ctx.say(
        'Safar could not plan the journey; it will not be priced',
        why: 'A failed specialist never stops the plan: Yatri routes around it and says so.',
        kind: FeedKind.warn,
      );
      st.notes.add('The journey to ${brief.destination} could not be planned, so it is not in the budget.');
      return;
    }
    st.transport = plan;
    st.chosen = plan.recommended;

    final issues = report.issues.where((i) => !_asked.contains(i.id)).toList();
    if (issues.isEmpty || ctx.degraded) return;
    final issue = issues.first;
    _asked.add(issue.id);
    ctx.say('needs your choice of transport', why: issue.why, kind: FeedKind.ask);
    final option = await _askIssue(ctx, issue);
    final i = TransportGates.indexOf(plan, option);
    st.transport = plan.withChoice(i);
    st.chosen = plan.options[i];
    ctx.say('you chose ${plan.options[i].mode.label.toLowerCase()}', why: 'Yatri plans the days around your arrival and departure times.', kind: FeedKind.decide);
  }

  // --- weather ----------------------------------------------------------------

  Future<void> _weatherPhase(TaskContext ctx, _State st) async {
    final brief = st.brief;
    final report = await ctx.delegate(
      TaskSpec(
        id: 'raah.weather',
        agent: AgentKind.raah,
        title: 'Check the weather',
        why: 'Rain changes which places suit which day, so Raah looks at the forecast before ordering the days.',
        optional: true,
        timeout: const Duration(seconds: 12),
      ),
      (c) async {
        final days = await toolkit.forecast.outlook(st.center.latitude, st.center.longitude, brief.start!, brief.end!, today: _now());
        final map = {for (final d in days) d.date: d};
        st.weather = map;
        final rainy = days.where((d) => d.isRainy).length;
        final real = days.where((d) => d.isForecast).length;
        final typical = days.length - real;
        if (typical > 0) {
          st.notes.add(
            'For $typical day${typical == 1 ? '' : 's'} beyond the 16-day forecast, the weather is what the season was like in past years, not a forecast.',
          );
        }
        return AgentReport(
          agent: c.agent,
          status: map.isEmpty || typical > 0 ? ReportStatus.degraded : ReportStatus.done,
          summary: map.isEmpty
              ? 'no weather data for these dates'
              : '${real > 0 ? 'forecast for $real day${real == 1 ? '' : 's'}' : ''}'
                    '${real > 0 && typical > 0 ? ' and ' : ''}'
                    '${typical > 0 ? 'seasonal norms for $typical' : ''}'
                    '${rainy > 0 ? ', $rainy rainy' : ''}',
          why: 'Open-Meteo gives a forecast up to 16 days ahead; for later dates Raah uses how the same dates went in past years and labels it that way.',
        );
      },
      say: 'asked Raah to check the weather',
    );
    st.weatherTask = 'raah.weather';
    if (!report.isUsable && st.weather.isEmpty) st.notes.add('The weather forecast was not available.');
  }

  // --- days, audit, budget, assembly ------------------------------------------

  /// Lays out the days, then audits and prices them, and keeps going until
  /// nothing needs the traveller's decision (or time and rounds run out). Each
  /// pass is Raah, then Saksham and Hisab side by side; the first open problem
  /// (access, then weather, then budget) is put to the traveller, or fixed
  /// quietly when it is a minor place, and the days are laid out again.
  Future<Itinerary?> _settle(TaskContext ctx, _State st) async {
    final brief = st.brief;
    if (st.spots == null && st.hotel == null) {
      ctx.say(
        'has too little to build days from',
        why: 'Neither places nor a stay could be found, so there is nothing to lay out.',
        kind: FeedKind.warn,
      );
      return null;
    }

    const maxPasses = 5;
    DayPlanResult? days;
    Budget? budget;
    AuditResult? audit;
    GreenReport? green;
    var rainIssues = const <Issue>[];
    var budgetIssues = const <Issue>[];
    var greenIssues = const <Issue>[];
    var pass = -1;
    var dirty = true;
    final needs = {for (final n in brief.accessibilityNeeds) if (n != AccessibilityNeed.none) n};

    for (var guard = 0; guard < 24; guard++) {
      if (dirty) {
        pass++;
        dirty = false;
        final planned = await _dayPlan(ctx, st, pass);
        if (planned == null) return null;
        days = planned.$1;
        rainIssues = planned.$2;

        // Saksham, Hisab and Hariyali work on the same days at the same time.
        final reports = await Future.wait([
          _auditNode(ctx, st, planned.$1, pass),
          _budgetNode(ctx, st, planned.$1, pass),
          _greenNode(ctx, st, planned.$1, pass),
        ]);
        if (reports[0].payload is AuditResult) audit = reports[0].payload as AuditResult;
        if (reports[1].payload is Budget) budget = reports[1].payload as Budget;
        budgetIssues = reports[1].issues;
        if (reports[2].payload is GreenResult) green = (reports[2].payload as GreenResult).report;
        greenIssues = reports[2].issues;
      }
      if (pass >= maxPasses || ctx.degraded) break;

      final fixes = audit == null
          ? const AccessFixes()
          : AccessGates.check(
              result: audit,
              needs: needs,
              hotel: st.hotel,
              hotelAlternatives: st.hotels?.options ?? const [],
              transport: st.transport,
              chosenTransport: st.chosen,
            );

      // Minor places that do not suit the group are swapped without a question.
      final auto = [for (final id in fixes.autoReplaceIds) if (!_autoDone.contains(id)) id];
      if (auto.isNotEmpty) {
        _autoDone.addAll(auto);
        _replacePlaces(ctx, st, auto, quiet: true);
        dirty = true;
        continue;
      }

      final issues = [...fixes.issues, ...rainIssues, ...budgetIssues, ...greenIssues].where((i) => !_asked.contains(i.id)).toList();
      if (issues.isEmpty) break;

      final issue = issues.first;
      _asked.add(issue.id);
      ctx.say(
        'needs your decision on ${switch (issue.agent) {
          AgentKind.saksham => 'access',
          AgentKind.raah => 'the weather',
          AgentKind.hisab => 'the budget',
          AgentKind.hariyali => 'a greener choice',
          _ => 'the plan',
        }}',
        why: issue.why,
        kind: FeedKind.ask,
      );
      final option = await _askIssue(ctx, issue);
      ctx.say('you chose: ${option.label}', why: 'Yatri applies it and re-plans the days if needed.', kind: FeedKind.decide);
      // An answer that changes nothing just moves on to the next open issue.
      dirty = _applyChoice(ctx, st, option);
    }

    if (days == null || budget == null) return null;
    final d = days;
    final b = budget;
    final itinerary = ItineraryAssembler.build(
      brief: brief,
      now: _now(),
      days: d,
      budget: b,
      hotels: st.hotels,
      hotel: st.hotel,
      spots: st.spots,
      transport: st.transport,
      chosenTransport: st.chosen,
      weather: st.weather,
      audit: audit?.audit,
      green: green,
      extraAssumptions: [...st.notes, if (st.stayOwn) 'You chose to arrange your own stay, so no hotel is included.'],
    );
    final timed = itinerary.copyWith(timings: _timings());
    ctx.say(
      'put the plan together: ${itinerary.dayCount} days, ${rupees(b.totalInr)}',
      why: 'Yatri combined the stay, places, journey, days, access audit and budget into one itinerary.',
      kind: FeedKind.decide,
    );
    return timed;
  }

  /// Seconds each agent spent working, by agent name, and the active total.
  Map<String, int> _timings() {
    final out = <String, int>{};
    for (final n in graph.nodes) {
      final e = n.elapsed;
      if (e == null || n.agent == AgentKind.yatri) continue;
      out[n.agent.displayName] = (out[n.agent.displayName] ?? 0) + e.inSeconds;
    }
    out['total'] = clock.elapsed.inSeconds;
    return out;
  }

  final Set<String> _autoDone = {};

  Future<AgentReport> _auditNode(TaskContext ctx, _State st, DayPlanResult days, int pass) {
    final brief = st.brief;
    return ctx.delegate(
      TaskSpec(
        id: 'saksham.audit.$pass',
        agent: AgentKind.saksham,
        title: pass == 0 ? 'Audit accessibility' : 'Re-audit accessibility',
        why: 'Saksham checks every step of the trip (the stay, the journey, each place, each transfer) against every access need in your group.',
        parents: ['raah.days.$pass'],
        timeout: const Duration(seconds: 25),
      ),
      (c) => SakshamAgent(estimator: toolkit.estimator).run(
        c,
        AuditInput(
          needs: brief.accessibilityNeeds,
          days: days.days,
          spots: {for (final h in [...?st.spots?.pool, ...?st.spots?.selected]) h.id: h},
          hotel: st.hotel,
          outbound: st.chosen,
          inbound: _mirror(st.chosen),
        ),
      ),
      say: pass == 0 ? 'asked Saksham to audit the plan for access' : 'asked Saksham to audit the changed plan',
    );
  }

  Future<AgentReport> _greenNode(TaskContext ctx, _State st, DayPlanResult days, int pass) {
    final brief = st.brief;
    return ctx.delegate(
      TaskSpec(
        id: 'hariyali.green.$pass',
        agent: AgentKind.hariyali,
        title: pass == 0 ? 'Score the footprint' : 'Re-score the footprint',
        why: 'Hariyali measures the carbon and eco impact of every choice and looks for greener ones.',
        parents: ['raah.days.$pass'],
        timeout: const Duration(seconds: 8),
      ),
      (c) => HariyaliAgent().run(
        c,
        GreenInput(
          days: days.days,
          nights: BudgetEngine.nights(brief),
          rooms: BudgetEngine.rooms(brief),
          travellers: BudgetEngine.travellers(brief),
          hotel: st.hotel,
          outbound: st.chosen,
          inbound: _mirror(st.chosen),
          transport: st.transport,
          hotelAlternatives: st.hotels?.options ?? const [],
          needs: {for (final n in brief.accessibilityNeeds) if (n != AccessibilityNeed.none) n},
          localModes: brief.transportModes,
        ),
        preferGreenest: brief.sustainability == SustainabilityPriority.greenest,
      ),
      say: pass == 0 ? 'asked Hariyali to score the footprint' : 'asked Hariyali to re-score the footprint',
    );
  }

  Future<AgentReport> _budgetNode(TaskContext ctx, _State st, DayPlanResult days, int pass) {
    final brief = st.brief;
    return ctx.delegate(
      TaskSpec(
        id: 'hisab.budget.$pass',
        agent: AgentKind.hisab,
        title: pass == 0 ? 'Price the plan' : 'Re-price the plan',
        why: 'Hisab adds up the stay, travel, entry fees, meals and a small buffer, and compares the total with your budget.',
        parents: ['raah.days.$pass'],
        timeout: const Duration(seconds: 10),
      ),
      (c) async {
        final b = BudgetEngine.build(
          BudgetInput(
            brief: brief,
            days: days.days,
            hotel: st.hotel,
            outbound: st.chosen,
            inbound: _mirror(st.chosen),
            stayOwnArrangement: st.stayOwn,
          ),
        );
        final issues = BudgetGates.check(
          budget: b,
          hotel: st.hotel,
          hotelAlternatives: st.hotels?.options ?? const [],
          transport: st.transport,
          chosenTransport: st.chosen,
          days: days.days,
          hotspots: {for (final h in st.spots?.pool ?? const <Hotspot>[]) h.id: h},
          brief: brief,
          alreadyDropped: st.droppedIds,
        );
        if (issues.isNotEmpty) {
          c.say(
            'is over budget and is asking Atithi, Safar and Bhatkanti for cheaper options',
            why: 'Hisab looks for real savings in the stay, the journey and the paid places before it bothers you.',
            kind: FeedKind.negotiate,
          );
        }
        return AgentReport(
          agent: c.agent,
          status: b.hasEstimates ? ReportStatus.degraded : ReportStatus.done,
          summary: 'the plan comes to ${rupees(b.totalInr)}'
              '${b.budgetMaxInr == null ? '' : (b.isWithinBudget ? ', within your budget' : ', ${rupees(-b.remainingInr!)} over budget')}',
          payload: b,
          issues: issues,
          why: 'Lines marked as estimates use typical prices.',
        );
      },
      say: pass == 0 ? 'asked Hisab to price the plan' : 'asked Hisab to price the changed plan',
    );
  }

  /// Raah's layout for one pass, with any weather question it raises.
  Future<(DayPlanResult, List<Issue>)?> _dayPlan(TaskContext ctx, _State st, int round) async {
    final brief = st.brief;
    final parents = round == 0 ? [st.hotelTask, st.spotsTask, st.transportTask, st.weatherTask].whereType<String>().toList() : <String>[];
    DayPlanResult? out;
    var rain = const <Issue>[];
    await ctx.delegate(
      TaskSpec(
        id: 'raah.days.$round',
        agent: AgentKind.raah,
        title: round == 0 ? 'Plan the days' : 'Re-plan the days',
        why: 'Raah groups places that are close together, checks opening hours and weather, and orders each day so the walking and waiting stay short.',
        parents: parents,
        timeout: const Duration(seconds: 20),
      ),
      (c) async {
        final chosen = st.spots?.selected ?? const <Hotspot>[];
        final chosenIds = chosen.map((h) => h.id).toSet();
        final alternates = [for (final h in st.spots?.pool ?? const <Hotspot>[]) if (!chosenIds.contains(h.id)) h];
        final input = DayPlanInput(
          start: brief.start!,
          end: brief.end!,
          base: st.hotel?.location ?? st.center,
          baseName: st.hotel?.name ?? '${brief.destination} centre',
          places: chosen,
          alternates: alternates,
          travellers: BudgetEngine.travellers(brief),
          children: BudgetEngine.childCount(brief),
          weather: st.weather,
          localModes: brief.transportModes,
          needs: brief.accessibilityNeeds,
          arrival: st.chosen,
          departure: _mirror(st.chosen),
          pace: brief.pace,
          bannedOutdoorDates: st.bannedOutdoor,
          excludedIds: st.droppedIds,
        );
        final r = DayPlanner.plan(input);
        out = r;
        rain = RainGates.check(r, banned: st.bannedOutdoor);
        final visits = r.visited.length;
        return AgentReport(
          agent: c.agent,
          status: r.unscheduled.isEmpty ? ReportStatus.done : ReportStatus.degraded,
          summary: 'planned ${r.days.length} day${r.days.length == 1 ? '' : 's'} with $visits place${visits == 1 ? '' : 's'}'
              '${r.unscheduled.isEmpty ? '' : ', ${r.unscheduled.length} did not fit'}'
              '${rain.isEmpty ? '' : ', rain on ${r.rainConflicts.length} outdoor day${r.rainConflicts.length == 1 ? '' : 's'}'}',
          issues: rain,
          why: 'Places close together share a day; wet days go to indoor places where possible.',
        );
      },
      say: round == 0 ? 'asked Raah to lay out the days' : 'asked Raah to re-plan the days',
    );
    final r = out;
    if (r == null) {
      ctx.say('Raah could not lay out the days', why: 'Without days there is no itinerary to show.', kind: FeedKind.warn);
      return null;
    }
    return (r, rain);
  }

  /// Swaps unsuitable places for the next-best ones from the pool.
  void _replacePlaces(TaskContext ctx, _State st, List<String> ids, {bool quiet = false}) {
    final spots = st.spots;
    if (spots == null || ids.isEmpty) return;
    final names = [for (final h in spots.selected) if (ids.contains(h.id)) h.name];
    st.spots = HotspotFinder.amended(spots, dropIds: ids.toSet());
    st.droppedIds.addAll(ids);
    ctx.say(
      quiet
          ? 'swapped ${names.take(2).join(' and ')}${names.length > 2 ? ' and ${names.length - 2} more' : ''} for places that suit the group'
          : 'is replacing ${names.take(2).join(' and ')} with places that suit the group',
      why: 'A real source says ${names.length == 1 ? 'it does' : 'they do'} not work for someone in your group, so Yatri chose better fits from what Bhatkanti had found.',
      kind: FeedKind.decide,
    );
  }

  /// Applies the traveller's answer. False means the plan is unchanged.
  bool _applyChoice(TaskContext ctx, _State st, IssueOption option) {
    final e = option.effect;
    switch (e['action']) {
      case 'swapHotel':
        final id = e['hotelId'];
        final h = st.hotels?.options.where((o) => o.id == id).firstOrNull;
        if (h == null) return false;
        st.hotel = h;
        ctx.say('is switching the stay to ${h.name}', why: 'It suits the group better or costs less.', kind: FeedKind.negotiate);
        return true;
      case 'swapTransport':
        final plan = st.transport;
        final i = e['index'];
        if (plan == null || i is! int || i < 0 || i >= plan.options.length) return false;
        st.transport = plan.withChoice(i);
        st.chosen = plan.options[i];
        ctx.say('is switching the journey to ${plan.options[i].mode.label.toLowerCase()}', why: 'It suits the group better or costs less.', kind: FeedKind.negotiate);
        return true;
      case 'dropPlaces':
        final ids = e['ids'];
        if (ids is! List || ids.isEmpty) return false;
        st.droppedIds.addAll(ids.whereType<String>());
        ctx.say('is dropping ${ids.length} paid place${ids.length == 1 ? '' : 's'}', why: 'They cost the most for how much they add.', kind: FeedKind.negotiate);
        return true;
      case 'replacePlaces':
        final ids = e['ids'];
        if (ids is! List || ids.isEmpty) return false;
        _replacePlaces(ctx, st, ids.whereType<String>().toList());
        return true;
      case 'banOutdoor':
        final dates = e['dates'];
        if (dates is! List || dates.isEmpty) return false;
        st.bannedOutdoor.addAll(dates.whereType<String>());
        ctx.say(
          'is moving outdoor plans off the rainy day${dates.length == 1 ? '' : 's'}',
          why: 'Raah keeps outdoor places for drier days and fills the wet ones with indoor places.',
          kind: FeedKind.decide,
        );
        return true;
      default:
        return false;
    }
  }

  /// The way home: the chosen leg reversed.
  static TransportLeg? _mirror(TransportLeg? leg) {
    if (leg == null) return null;
    return TransportLeg(
      id: 'intercity.return.${leg.mode.name}',
      from: leg.to,
      to: leg.from,
      mode: leg.mode,
      distanceKm: leg.distanceKm,
      durationMin: leg.durationMin,
      costInr: leg.costInr,
      co2Grams: leg.co2Grams,
      stepFree: leg.stepFree,
      note: leg.note,
      isEstimated: leg.isEstimated,
      fromPoint: leg.toPoint,
      toPoint: leg.fromPoint,
    );
  }

  // --- questions ------------------------------------------------------------

  /// Asks one question at a time, however many specialists want to ask. The
  /// plan clock is paused for as long as anyone is waiting on the traveller.
  Future<T> _serial<T>(Future<T> Function() body) {
    final prev = _askTail;
    final done = Completer<void>();
    _askTail = done.future;
    return prev.then((_) => body()).whenComplete(done.complete);
  }

  Future<YatriAnswer?> _askQuestion(TaskContext ctx, YatriQuestion question) async {
    try {
      return await _serial(() => ctx.waitForUser(() => ask(question)));
    } catch (_) {
      return null;
    }
  }

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
          QuestionOption(id: o.id, label: o.label, subtitle: o.subtitle, badge: o.badge, recommended: o.recommended),
      ],
    );
    final answer = await _askQuestion(ctx, question);
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

  /// A starting point: geocoders first, then the model's knowledge of where
  /// well-known cities are (labelled through the plan's notes).
  Future<LatLng?> _locateOrigin(String place) async {
    final p = await _geocode(place);
    if (p != null) return p;
    try {
      final r = await toolkit.estimator.fill(
        agent: AgentKind.safar,
        subject: 'the location of "$place"',
        fields: const {'lat': 'latitude in decimal degrees', 'lon': 'longitude in decimal degrees'},
      );
      final lat = r?['lat']?.value;
      final lon = r?['lon']?.value;
      if (lat is num && lon is num && lat.abs() <= 90 && lon.abs() <= 180 && !(lat == 0 && lon == 0)) {
        return LatLng(lat.toDouble(), lon.toDouble());
      }
    } catch (_) {
      // unknown
    }
    return null;
  }

  static String? _notes(TripBrief brief) {
    final parts = [
      if (brief.stayTypes.isNotEmpty) brief.stayTypes.map((s) => s.label.toLowerCase()).join(' or '),
      if (brief.notes != null && brief.notes!.trim().isNotEmpty) brief.notes!.trim().substring(0, brief.notes!.trim().length.clamp(0, 120)),
    ];
    return parts.isEmpty ? null : parts.join('; ');
  }
}
