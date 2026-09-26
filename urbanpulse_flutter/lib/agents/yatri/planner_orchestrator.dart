import 'dart:async';

import 'package:latlong2/latlong.dart';

import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../models/yatri_question.dart';
import '../../services/data/forecast_client.dart';
import '../../services/data/location_key_resolver.dart';
import '../../services/place_geocoder.dart';
import '../atithi/atithi_agent.dart';
import '../atithi/hotel_finder.dart';
import '../bhatkanti/bhatkanti_agent.dart';
import '../bhatkanti/hotspot_candidate.dart';
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
import '../tools/web_search_tool.dart';
import 'access_gates.dart';
import 'budget_gates.dart';
import 'completeness_gate.dart';
import 'hotel_gates.dart';
import 'hotspot_gates.dart';
import 'itinerary_assembler.dart';
import 'transport_gates.dart';

/// Puts a question in front of the traveller and waits for the answer.
typedef AskUser = Future<YatriAnswer> Function(YatriQuestion question);

enum PlanStatus {
  /// The whole trip is planned: every day has enough to do, or the traveller
  /// accepted a lighter day.
  planned,

  /// The traveller stopped the plan before it was finished; what exists so far.
  partial,

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

/// What the agents have produced so far, and what Yatri has already tried.
/// Written by the phases and the goal loop, read by the stages after them.
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

  // --- how the plan can be repaired -------------------------------------------
  late AtithiAgent atithi;
  late HotelQuery hotelQuery;
  late BhatkantiAgent bhatkanti;
  late HotspotQuery spotQuery;
  late SafarAgent safar;
  WebSearchTool? search;

  /// Run counters, so every re-run is its own node in the graph.
  int hotelRuns = 0;
  int spotRuns = 0;
  int journeyRuns = 0;

  /// Repairs Yatri has made on its own ("more", "wider"): each at most once.
  final Set<String> repairs = {};

  /// Gaps the traveller accepted ("keep day 3 light").
  final Set<String> accepted = {};

  /// Per gap, the options already chosen, so they are not offered again.
  final Map<String, Set<String>> usedOptions = {};
  final Map<String, int> gapAsks = {};

  /// Places the traveller picked from the near misses, kept whatever the filters say.
  final Set<String> forcedIds = {};
}

/// Yatri: the only agent that decides. It reads the brief, allocates work to
/// the workers as nodes of the live task graph, checks what comes back against
/// the gates, and when two goals collide (access and budget, say) it asks the
/// traveller with concrete options instead of choosing for them.
///
/// The loop runs until the goal is met: every day the traveller is at the
/// destination has enough to do, there is a stay and a journey, or the
/// traveller knowingly accepted a gap. Nothing ends it because time passed, and
/// no worker is ever told to hurry; the traveller can stop it at any time.
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

  /// How many times a hotel search may be repeated with new constraints.
  final int maxSearches;

  /// Hotels offered to the traveller to choose from.
  final int maxChoices;

  /// Only the hotel stage (used by focused tests).
  final bool hotelsOnly;

  /// A defensive cap on goal-loop rounds against a logic bug. Every gap ends in
  /// a finite number of questions, so a real plan never gets near it; it is not
  /// a time limit.
  static const maxRounds = 80;

  final Set<String> _asked = {};
  Future<void> _askTail = Future.value();

  /// Stops the plan (the traveller pressed Stop): what exists is returned as
  /// [PlanStatus.partial].
  void stop() => board.cancel();

  Future<PlanOutcome> run(TripBrief brief) async {
    var outcome = PlanOutcome.failed('Planning did not finish');
    await board.submit(
      TaskSpec(
        id: 'yatri.plan',
        agent: AgentKind.yatri,
        title: 'Plan your trip',
        why: 'Yatri is the only agent that decides. It hands work to the specialists, checks what they bring back and asks you when a choice is yours.',
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
    final destination = cleanPlace(brief.destination);
    if (destination.isEmpty || brief.start == null || brief.end == null) {
      return PlanOutcome.failed('The brief is missing a destination or dates');
    }

    ctx.say(
      'read your brief: ${brief.days} day${brief.days == 1 ? '' : 's'} in $destination',
      why: 'Yatri starts by working out what each specialist needs to know.',
      kind: FeedKind.decide,
    );

    final origin = brief.originCity?.trim() ?? '';
    final areaF = _geocodeArea(destination);
    final originF = !hotelsOnly && origin.isNotEmpty ? _locateOrigin(origin) : Future<LatLng?>.value(null);
    final area = await areaF;
    final originPoint = await originF;
    final center = area?.center;
    if (center == null && !await _isOnline()) {
      ctx.say(
        'cannot reach the internet, so nothing can be looked up',
        why: 'Every search needs a connection. Yatri falls back to an offline estimate rather than blaming the destination.',
        kind: FeedKind.warn,
      );
      return PlanOutcome.failed('offline');
    }
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
    st.origin = originPoint;

    // A state or region (Goa, Kodagu) spreads well beyond a town's radius:
    // search the whole of it.
    final span = area?.isRegion == true ? area?.spanKm : null;
    if (span != null) {
      ctx.say(
        'is treating $destination as a region about ${(span * 2).round()} km across',
        why: 'It is a state or district rather than one town, so hotels and places are searched across all of it.',
        kind: FeedKind.decide,
      );
    }

    final toolset = toolkit.newPlan();
    st.search = toolset.search;
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
        travelRisk: toolkit.travelRisk,
      ),
    );
    st.atithi = AtithiAgent(finder, khoji: hotelsOnly ? null : khoji);

    st.hotelQuery = HotelQuery(
      destination: destination,
      center: center,
      checkIn: brief.start!,
      checkOut: brief.end!,
      rooms: HotelBudget.roomsFor(brief),
      adults: HotelBudget.adultsFor(brief),
      needs: brief.accessibilityNeeds,
      nightlyCapInr: HotelBudget.nightlyCapInr(brief),
      radiusKm: span == null ? 10 : (span * 0.8).clamp(10.0, HotelGates.maxRadiusKm),
      preferEco: brief.sustainability == SustainabilityPriority.greenest || brief.stayTypes.contains(StayType.ecoStay),
      notes: _notes(brief),
    );

    if (hotelsOnly) {
      await _hotelPhase(ctx, st, st.hotelQuery);
      return _hotelsOnlyOutcome(st);
    }

    // The specialists work at the same time; the traveller is asked one
    // question at a time as their answers come in.
    st.bhatkanti = BhatkantiAgent(
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
    st.safar = SafarAgent(estimator: toolkit.estimator);
    final baseQuery = HotspotQuery(
      destination: destination,
      center: center,
      days: brief.days,
      pace: brief.pace,
      style: brief.style,
      needs: brief.accessibilityNeeds,
      notes: _notes(brief),
      year: brief.start!.year,
      details: brief.accessibilityDetails,
    );
    st.spotQuery = span == null ? baseQuery : baseQuery.copyWith(radiusFactor: (span / baseQuery.radiusKm).clamp(1.0, 4.0));

    await Future.wait([
      _guardPhase(ctx, 'hotels', () => _hotelPhase(ctx, st, st.hotelQuery)),
      _guardPhase(ctx, 'places', () => _hotspotPhase(ctx, st, st.spotQuery)),
      _guardPhase(ctx, 'journey', () => _transportPhase(ctx, st)),
      _guardPhase(ctx, 'weather', () => _weatherPhase(ctx, st)),
    ]);

    // Lay out the days, audit and price them, and keep going until the whole
    // trip is planned.
    final itinerary = await _settle(ctx, st);
    final stopped = ctx.cancelled;
    final visits = itinerary == null ? 0 : itinerary.days.fold<int>(0, (s, d) => s + PlanCompleteness.visitsOn(d));
    return PlanOutcome(
      status: stopped ? PlanStatus.partial : (itinerary == null ? PlanStatus.failed : PlanStatus.planned),
      summary: itinerary == null
          ? (stopped ? 'Stopped before any days were planned' : 'Could not build the days')
          : '${stopped ? 'Stopped early: ' : 'Planned '}${itinerary.dayCount} days in $destination with $visits place${visits == 1 ? '' : 's'}',
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
        'ran into a problem with the $name, and will come back to it',
        why: 'A failed specialist never stops the plan: Yatri routes around it now and repairs it before the plan is finished.',
        kind: FeedKind.warn,
      );
    }
  }

  // --- hotels ---------------------------------------------------------------

  Future<void> _hotelPhase(TaskContext ctx, _State st, HotelQuery first) async {
    var query = first;
    HotelSearchResult? found;
    HotelOption? picked;
    var skipped = false;

    for (var round = 0; round <= maxSearches; round++) {
      final n = st.hotelRuns++;
      final atithiId = 'atithi.hotels.$n';
      final report = await ctx.delegate(
        TaskSpec(
          id: atithiId,
          agent: AgentKind.atithi,
          title: n == 0 ? 'Find hotels' : 'Search again',
          goal: 'Find stays for ${query.nights} nights',
          why: n == 0
              ? 'Yatri needs somewhere to base the plan. Atithi searches hotels, prices and access details.'
              : 'The search is looking for something different now, so Atithi is trying again.',
        ),
        (c) => st.atithi.run(c, query),
        say: n == 0 ? 'allocated the hotel search to Atithi' : 're-tasked Atithi with the new limits',
      );
      st.hotelTask = atithiId;

      final result = report.payload is HotelSearchResult ? report.payload as HotelSearchResult : null;
      if (result == null) {
        ctx.say(
          'Atithi could not finish the hotel search; Yatri will come back to the stay',
          why: 'A failed specialist never stops the plan: the stay is repaired before the plan is finished.',
          kind: FeedKind.warn,
        );
        break;
      }
      found = result;

      final hisab = await ctx.delegate(
        TaskSpec(
          id: 'hisab.hotels.$n',
          agent: AgentKind.hisab,
          title: 'Check the hotel budget',
          why: 'Hisab checks that a suitable hotel fits your budget before anything is planned around it.',
          parents: [atithiId],
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

      final issue = round == maxSearches ? HotelGates.withoutSearching(issues.first) : issues.first;
      _asked.add(issue.id);
      ctx.say('needs your decision on the hotels', why: issue.why, kind: FeedKind.ask);
      final option = await _askIssue(ctx, issue);
      ctx.say('you chose: ${option.label}', why: 'Yatri acts on your choice and re-plans if needed.', kind: FeedKind.decide);
      final action = option.effect['action'];
      if (action == 'skip') {
        skipped = true;
        break;
      }
      if (action == 'swapHotel') {
        picked = result.options.where((o) => o.id == option.effect['hotelId']).firstOrNull;
        if (picked != null) {
          st.notes.add('You chose ${picked.name} knowing it does not meet every need or the budget; confirm with the hotel.');
          break;
        }
      }
      final next = HotelGates.apply(query, option);
      if (next == null) break;
      if (next.nightlyCapInr != query.nightlyCapInr && next.nightlyCapInr != null) {
        st.notes.add('You raised the hotel budget to ${rupees(next.nightlyCapInr!)} a night.');
      }
      query = next;
    }

    st.hotels = found;
    if (found != null) st.notes.addAll(found.warnings);
    if (skipped) {
      st.stayOwn = true;
      return;
    }
    if (found == null || found.options.isEmpty) return;
    st.hotel = picked ?? await _chooseHotel(ctx, found, st.brief.accessibilityNeeds, st.brief.accessibilityDetails);
  }

  /// The traveller picks the stay; “let Yatri choose” (or a single candidate)
  /// takes the best fit. Stays confirmed to suit the group's access needs come
  /// first, then those with the facilities the traveller asked for (a lift, a
  /// roll-in shower); the best fit is the recommended answer.
  Future<HotelOption> _chooseHotel(TaskContext ctx, HotelSearchResult found, Set<AccessibilityNeed> groupNeeds, Map<String, Set<String>> details) async {
    final ranked = rankStays(found.options, groupNeeds, details, nightlyCapInr: found.query.nightlyCapInr);
    final options = ranked.take(maxChoices).toList();
    if (options.length == 1) {
      ctx.say('picked ${options.first.name}', why: 'It was the only stay that fit.', kind: FeedKind.decide);
      return options.first;
    }

    ctx.say(
      'found ${options.length} stays worth a look and is asking which you prefer',
      why: 'The stay is your decision. Yatri ranks them for you, but you know what matters most.',
      kind: FeedKind.ask,
    );
    final needs = {for (final n in found.query.needs) if (n != AccessibilityNeed.none) n};
    final question = YatriQuestion(
      // A later choice (after a new search) is a new question, never the old answer.
      id: _hotelChoices++ == 0 ? 'plan.hotels.choice' : 'plan.hotels.choice.$_hotelChoices',
      fields: const [],
      widget: AnswerWidget.hotelChoice,
      defaultText: 'Here are the stays that fit best. Which would you like?',
      reason: IssueKind.optional,
      agent: AgentKind.yatri.name,
      why: 'Stays confirmed to suit your group come first, then by the facilities you asked for, budget and location. '
          'Access details show where they came from, and anything unconfirmed says so.',
      hotels: options,
      hotelNeeds: needs,
      options: [
        for (var i = 0; i < options.length; i++) QuestionOption(id: options[i].id, label: options[i].name, recommended: i == 0),
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

  /// A stable re-rank of Atithi's stays for the group: fewest needs known to
  /// fail, then fewest unconfirmed (see [HotelGates.fitKey]); then within the
  /// nightly budget before above it; then fewest needs only partly met; then
  /// the facilities the traveller asked for; otherwise Atithi's order. Access
  /// comes before price, but among stays that suit the group equally, the one
  /// that fits the budget is recommended. Public for tests.
  static List<HotelOption> rankStays(List<HotelOption> options, Set<AccessibilityNeed> groupNeeds, Map<String, Set<String>> details, {int? nightlyCapInr}) {
    final needs = {for (final n in groupNeeds) if (n != AccessibilityNeed.none) n};
    final wanted = <RegExp>[
      if ((details['a11y.wheelchair.facilities'] ?? const {}).contains('lift') || (details['a11y.elderly.support'] ?? const {}).contains('ground_floor'))
        RegExp(r'lift|elevator|ground floor', caseSensitive: false),
      if ((details['a11y.wheelchair.facilities'] ?? const {}).contains('roll_in')) RegExp(r'roll.?in|accessible (bath|shower)', caseSensitive: false),
      if ((details['a11y.wheelchair.facilities'] ?? const {}).contains('toilet')) RegExp(r'accessible (toilet|bathroom|washroom)', caseSensitive: false),
      if ((details['a11y.elderly.support'] ?? const {}).contains('medical')) RegExp(r'doctor|medical|hospital|first aid', caseSensitive: false),
    ];
    List<int> key(int i, HotelOption h) {
      final fit = HotelGates.fitKey(h, needs);
      final over = nightlyCapInr != null && h.nightlyInr != null && h.nightlyInr! > nightlyCapInr ? 1 : 0;
      return [fit[0], fit[1], over, fit[2], -wanted.where((r) => r.hasMatch([...h.amenities, ...h.labels].join(' '))).length, i];
    }

    final keyed = [for (var i = 0; i < options.length; i++) (key(i, options[i]), options[i])];
    keyed.sort((a, b) {
      for (var k = 0; k < a.$1.length; k++) {
        final c = a.$1[k].compareTo(b.$1[k]);
        if (c != 0) return c;
      }
      return 0;
    });
    return [for (final e in keyed) e.$2];
  }

  /// The option id meaning “you pick”.
  static const autoPick = 'auto';

  int _hotelChoices = 0;

  // --- places to visit --------------------------------------------------------

  /// Runs Bhatkanti once with [query]. Null when it could not search.
  Future<(HotspotSearchResult, List<Issue>)?> _runBhatkanti(TaskContext ctx, _State st, HotspotQuery query, {required String title, required String say}) async {
    final n = st.spotRuns++;
    final id = 'bhatkanti.spots.$n';
    final report = await ctx.delegate(
      TaskSpec(
        id: id,
        agent: AgentKind.bhatkanti,
        title: title,
        why: 'A trip needs things to do. Bhatkanti finds about ${query.perDay} places a day, mixing well-known sights with new ones.',
      ),
      (c) => st.bhatkanti.run(c, query),
      say: say,
    );
    st.spotsTask = id;
    final result = report.payload is HotspotSearchResult ? report.payload as HotspotSearchResult : null;
    return result == null ? null : (result, report.issues);
  }

  Future<void> _hotspotPhase(TaskContext ctx, _State st, HotspotQuery first) async {
    final found = await _runBhatkanti(ctx, st, first, title: 'Find places to visit', say: 'allocated the search for places to visit to Bhatkanti');
    if (found == null) {
      ctx.say(
        'Bhatkanti could not finish the search; Yatri will try again before the plan is done',
        why: 'A failed specialist never stops the plan, and the days are never left empty without asking you.',
        kind: FeedKind.warn,
      );
      return;
    }
    final (result, reported) = found;
    st.spots = result;
    st.notes.addAll(result.warnings);

    // "Nothing found" is the goal loop's to repair; only the question of taste is asked here.
    final issues = reported.where((i) => !_asked.contains(i.id) && i.id == 'hotspots.mix').toList();
    if (issues.isEmpty) return;
    final issue = issues.first;
    _asked.add(issue.id);
    ctx.say('needs your taste on the places', why: issue.why, kind: FeedKind.ask);
    final option = await _askIssue(ctx, issue);
    ctx.say('you chose: ${option.label}', why: 'Yatri re-picks the places to match.', kind: FeedKind.decide);
    final mix = HotspotGates.mixOf(option);
    if (mix != null) {
      // The newest search result may have arrived meanwhile: re-pick from it.
      final current = st.spots ?? result;
      st.spots = HotspotFinder.reselect(current, mix);
      st.spotQuery = st.spotQuery.withMix(mix);
      ctx.say(
        're-picked the places: ${mix.label.toLowerCase()}',
        why: 'No new search was needed: Yatri re-ranked what Bhatkanti had already found.',
        kind: FeedKind.decide,
      );
    }
  }

  /// Everything two searches found, one entry per place, re-picked under [q].
  static HotspotSearchResult _mergeSpots(HotspotSearchResult? old, HotspotSearchResult fresh, HotspotQuery q) {
    if (old == null) return HotspotFinder.reselect(HotspotSearchResult(query: q, selected: fresh.selected, pool: fresh.pool, considered: fresh.considered, sources: fresh.sources, warnings: fresh.warnings), q.mix);
    final pool = <Hotspot>[];
    for (final h in [...old.pool, ...fresh.pool]) {
      final dup = pool.any(
        (p) =>
            p.id == h.id ||
            p.name.trim().toLowerCase() == h.name.trim().toLowerCase() ||
            (HotspotCandidates.sameName(p.name, h.name) && _km(p.location, h.location) <= 1.5),
      );
      if (!dup) pool.add(h);
    }
    pool.sort((a, b) => b.score.compareTo(a.score));
    final merged = HotspotSearchResult(
      query: q,
      selected: const [],
      pool: pool,
      considered: old.considered + fresh.considered,
      sources: {...old.sources, ...fresh.sources}.toList(),
      warnings: {...old.warnings, ...fresh.warnings}.toList(),
    );
    return HotspotFinder.reselect(merged, q.mix);
  }

  // --- the journey ----------------------------------------------------------

  Future<void> _transportPhase(TaskContext ctx, _State st) async {
    final brief = st.brief;
    final origin = st.origin;
    if (origin == null) {
      if ((brief.originCity ?? '').trim().isNotEmpty) {
        ctx.say(
          'could not place ${brief.originCity} on the map yet; Yatri will come back to the journey',
          why: 'Travel time, cost and CO₂ need both ends of the journey.',
          kind: FeedKind.warn,
        );
      }
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
    final n = st.journeyRuns++;
    final id = n == 0 ? 'safar.transport' : 'safar.transport.$n';
    final report = await ctx.delegate(
      TaskSpec(
        id: id,
        agent: AgentKind.safar,
        title: n == 0 ? 'Plan the journey' : 'Plan the journey again',
        why: 'Yatri needs to know how you get there, how long it takes, what it costs and how much CO₂ it emits.',
      ),
      (c) => st.safar.run(c, query),
      say: n == 0 ? 'allocated the journey to Safar' : 'asked Safar to try the journey again',
    );
    st.transportTask = id;
    final plan = report.payload is TransportPlan ? report.payload as TransportPlan : null;
    if (plan == null) {
      ctx.say(
        'Safar could not plan the journey; Yatri will come back to it',
        why: 'A failed specialist never stops the plan: the journey is repaired or put to you before the plan is finished.',
        kind: FeedKind.warn,
      );
      return;
    }
    st.transport = plan;
    st.chosen = plan.recommended;

    final issues = report.issues.where((i) => !_asked.contains(i.id)).toList();
    if (issues.isEmpty) return;
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

  // --- the goal loop: days, audit, budget, completeness ------------------------

  /// Lays out the days, then audits and prices them, and keeps going until the
  /// trip is whole. Each pass is Raah, then Saksham, Hisab and Hariyali side by
  /// side. Then, in order: unsuitable minor places are swapped quietly; a gap
  /// in the plan (a thin day, no stay, no journey) is repaired by Yatri itself
  /// if it still has something to try, or put to the traveller as a choice of
  /// real options; then access, weather, budget and footprint questions. The
  /// loop ends only when nothing is missing and nothing is left to decide.
  Future<Itinerary?> _settle(TaskContext ctx, _State st) async {
    final brief = st.brief;
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

    for (var round = 0; round < maxRounds; round++) {
      if (ctx.cancelled) break;
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

      // The goal: is this a whole trip yet?
      final gaps = PlanCompleteness.check(
        days: days,
        brief: brief,
        hasPlaces: _hasPlaces(st),
        hasStay: st.hotel != null || st.stayOwn,
        journeyNeeded: (brief.originCity ?? '').trim().isNotEmpty,
        hasJourney: st.chosen != null,
        accepted: st.accepted,
        slowPace: _slowPace(brief),
      );
      if (gaps.isNotEmpty) {
        final gap = gaps.first;
        _narrateGaps(ctx, gaps);
        if (await _autoRepair(ctx, st, gap)) {
          dirty = true;
          continue;
        }
        dirty = await _askGap(ctx, st, gap);
        continue;
      }

      final unconfirmed = days == null ? null : _unconfirmedAccess(st, days);
      final issues = [...fixes.issues, ?unconfirmed, ...rainIssues, ...budgetIssues, ...greenIssues].where((i) => !_asked.contains(i.id)).toList();
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
      dirty = option.effect['action'] == 'pickUnconfirmed' ? await _pickUnconfirmed(ctx, st, days!) : _applyChoice(ctx, st, option);
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
      center: st.center,
      origin: st.origin,
      bannedOutdoor: st.bannedOutdoor,
      droppedIds: st.droppedIds,
      extraAssumptions: [
        ...st.notes,
        if (st.stayOwn) 'You chose to arrange your own stay, so no hotel is included.',
        if ((st.search?.unansweredReviewSearches ?? 0) > 0 && !_anyReviews(st)) 'Guest reviews were unavailable: no search provider answered the review searches.',
      ],
    );
    final timed = itinerary.copyWith(timings: _timings());
    final visits = d.days.fold<int>(0, (s, day) => s + PlanCompleteness.visitsOn(day));
    ctx.say(
      'put the plan together: ${itinerary.dayCount} days, $visits place${visits == 1 ? '' : 's'}, ${rupees(b.totalInr)}',
      why: ctx.cancelled
          ? 'You stopped the plan, so this is what was ready.'
          : 'Every day you are there has enough to do (or you chose a lighter day), and the stay, journey, access and budget are settled.',
      kind: FeedKind.decide,
    );
    return timed;
  }

  static const _mobilityNeeds = {AccessibilityNeed.wheelchair, AccessibilityNeed.limitedMobility, AccessibilityNeed.elderlyCare};

  /// Places in the plan that no source confirms for the group's mobility needs.
  List<Hotspot> _unconfirmedVisits(_State st, DayPlanResult days) {
    final needs = [for (final n in st.brief.accessibilityNeeds) if (_mobilityNeeds.contains(n)) n];
    if (needs.isEmpty) return const [];
    final byId = {for (final h in [...?st.spots?.pool, ...?st.spots?.selected]) h.id: h};
    final out = <Hotspot>[];
    for (final d in days.days) {
      for (final slot in d.slots) {
        if (slot.kind != SlotKind.visit) continue;
        final h = byId[slot.refId];
        if (h == null || st.forcedIds.contains(h.id) || out.any((o) => o.id == h.id)) continue;
        if (!HotspotFinder.accessConfirmed(h, needs.toSet())) out.add(h);
      }
    }
    return out;
  }

  /// When places in the plan have no confirmed access for a wheelchair user or
  /// someone with limited mobility, the traveller decides, once: swap them for
  /// confirmed places, pick which to keep, or keep them and check ahead.
  Issue? _unconfirmedAccess(_State st, DayPlanResult days) {
    final unknown = _unconfirmedVisits(st, days);
    if (unknown.isEmpty) return null;
    final needs = {for (final n in st.brief.accessibilityNeeds) if (_mobilityNeeds.contains(n)) n};
    final planned = {for (final d in days.days) for (final s in d.slots) if (s.kind == SlotKind.visit) s.refId};
    final confirmed = [
      for (final h in st.spots?.pool ?? const <Hotspot>[])
        if (!planned.contains(h.id) && !st.droppedIds.contains(h.id) && h.kind != HotspotKind.food && !HotspotFinder.isExcluded(h, st.spotQuery) && HotspotFinder.accessConfirmed(h, needs)) h,
    ];
    final what = needs.map((n) => n.label.toLowerCase()).join(', ');
    final names = unknown.take(4).map((h) => h.name).join(', ');
    final swap = unknown.take(confirmed.length).map((h) => h.id).toList();
    return Issue(
      id: 'access.unconfirmed',
      agent: AgentKind.saksham,
      severity: IssueSeverity.warning,
      message: '${unknown.length} of the places in the plan have no confirmed access for $what: $names${unknown.length > 4 ? '…' : ''}. What should I do?',
      why: 'Saksham found nothing (in maps, reviews or the places\' own pages) saying these work for your group. '
          'Nothing says they do not either, so it is your call.',
      options: [
        if (swap.isNotEmpty)
          IssueOption(
            id: 'swap',
            label: 'Swap ${swap.length == unknown.length ? 'them' : '${swap.length} of them'} for places with confirmed access',
            subtitle: '${confirmed.length} confirmed place${confirmed.length == 1 ? '' : 's'} available, e.g. ${confirmed.take(2).map((h) => h.name).join(', ')}',
            effect: {'action': 'replacePlaces', 'ids': swap},
            recommended: true,
          ),
        const IssueOption(id: 'pick', label: 'Let me choose which of them to keep', effect: {'action': 'pickUnconfirmed'}),
        IssueOption(
          id: 'keep',
          label: 'Keep them; I will check access before going',
          effect: const {'action': 'keepUnconfirmed'},
          recommended: swap.isEmpty,
        ),
      ],
    );
  }

  /// The traveller ticks the unconfirmed places to keep; the rest are replaced.
  Future<bool> _pickUnconfirmed(TaskContext ctx, _State st, DayPlanResult days) async {
    final unknown = _unconfirmedVisits(st, days);
    if (unknown.isEmpty) return false;
    final question = YatriQuestion(
      id: 'plan.access.unconfirmed.pick',
      fields: const [],
      widget: AnswerWidget.multiSelect,
      defaultText: 'Tick the places to keep. The others will be replaced with better-suited ones where possible.',
      reason: IssueKind.conflict,
      agent: AgentKind.yatri.name,
      why: 'None of these has confirmed access for your group; you know best which are worth the risk.',
      options: [for (final h in unknown) QuestionOption(id: h.id, label: h.name, subtitle: '${h.kind.name} · access not confirmed')],
    );
    final answer = await _askQuestion(ctx, question);
    final keep = switch (answer) {
      MultiChoiceAnswer(:final optionIds) => optionIds,
      ChoiceAnswer(:final optionId) => {optionId},
      _ => {for (final h in unknown) h.id},
    };
    st.forcedIds.addAll(keep.where((id) => unknown.any((h) => h.id == id)));
    final drop = [for (final h in unknown) if (!keep.contains(h.id)) h.id];
    if (keep.isNotEmpty) {
      st.notes.add('You kept ${unknown.where((h) => keep.contains(h.id)).map((h) => h.name).join(', ')} without confirmed access; check before going.');
    }
    if (drop.isEmpty) return false;
    _replacePlaces(ctx, st, drop);
    return true;
  }

  static double _km(LatLng a, LatLng b) => const Distance().as(LengthUnit.Kilometer, a, b);

  static bool _anyReviews(_State st) => [?st.hotel, ...?st.hotels?.options].any((h) => h.claims.any((c) => c.isReviews));

  bool _hasPlaces(_State st) {
    final s = st.spots;
    if (s == null) return false;
    return s.selected.isNotEmpty || s.pool.isNotEmpty;
  }

  static bool _slowPace(TripBrief b) =>
      b.accessibilityNeeds.contains(AccessibilityNeed.elderlyCare) || (b.accessibilityDetails['a11y.elderly.support']?.contains('slow_pace') ?? false);

  final Set<String> _narrated = {};

  void _narrateGaps(TaskContext ctx, List<PlanGap> gaps) {
    final key = gaps.map((g) => g.id).join(',');
    if (!_narrated.add(key)) return;
    final thin = [for (final g in gaps) if (g.kind == GapKind.day) 'day ${g.day}'];
    final parts = [
      if (gaps.any((g) => g.kind == GapKind.places)) 'no places to visit yet',
      if (thin.isNotEmpty) '${thin.join(', ')} ${thin.length == 1 ? 'is' : 'are'} too thin',
      if (gaps.any((g) => g.kind == GapKind.time)) 'the journey leaves no time there',
      if (gaps.any((g) => g.kind == GapKind.stay)) 'no stay yet',
      if (gaps.any((g) => g.kind == GapKind.journey)) 'the journey is not planned',
    ];
    ctx.say(
      'is not finished: ${parts.join('; ')}',
      why: 'Yatri keeps working until the whole trip is planned, and asks you only when it has nothing left to try.',
      kind: FeedKind.decide,
    );
  }

  /// One thing Yatri can do on its own about [gap], if it has not done it yet.
  /// True when something changed and the days should be laid out again.
  Future<bool> _autoRepair(TaskContext ctx, _State st, PlanGap gap) async {
    switch (gap.kind) {
      case GapKind.places:
        if (st.repairs.add('places.retry')) {
          return _searchPlaces(ctx, st, st.spotQuery, why: 'the first search came back empty or failed');
        }
        return false;
      case GapKind.day:
        // 1. More of what Bhatkanti already found: no new search.
        final spots = st.spots;
        if (spots != null && spots.pool.length > spots.selected.length && st.repairs.add('places.more')) {
          st.spotQuery = st.spotQuery.copyWith(extra: st.spotQuery.extra + st.spotQuery.perDay * 2);
          final before = spots.selected.length;
          st.spots = HotspotFinder.reselect(HotspotSearchResult(query: st.spotQuery, selected: spots.selected, pool: spots.pool, considered: spots.considered, sources: spots.sources, warnings: spots.warnings), st.spotQuery.mix);
          ctx.say(
            'is adding more of the places Bhatkanti found to fill day ${gap.day}',
            why: 'Day ${gap.day} has ${gap.visits} of the ${gap.needed} places it needs; Bhatkanti found more than the first pick used.',
            kind: FeedKind.decide,
          );
          return st.spots!.selected.length > before;
        }
        // 2. A wider search, at full depth.
        if (st.repairs.add('places.wider')) {
          return _searchPlaces(ctx, st, st.spotQuery.copyWith(radiusFactor: st.spotQuery.radiusFactor * 1.6), why: 'day ${gap.day} is still short of places');
        }
        return false;
      case GapKind.stay:
        if (st.repairs.add('stay.retry')) {
          ctx.say('is searching for a stay again', why: 'There is no stay yet and you have not said you will arrange one.', kind: FeedKind.decide);
          final before = st.hotel;
          await _hotelPhase(ctx, st, st.hotelQuery.copyWith(radiusKm: (st.hotelQuery.radiusKm * 2).clamp(10.0, HotelGates.maxRadiusKm)));
          return st.hotel != before || st.stayOwn;
        }
        return false;
      case GapKind.journey:
        if (st.repairs.add('journey.retry')) {
          if (st.origin == null && (st.brief.originCity ?? '').trim().isNotEmpty) st.origin = await _locateOrigin(st.brief.originCity!.trim());
          await _transportPhase(ctx, st);
          return st.chosen != null;
        }
        return false;
      case GapKind.time:
        return false; // how to travel is the traveller's call
    }
  }

  /// Runs Bhatkanti again with [query] and merges what it finds with what was
  /// already there. True when there is anything new to plan with.
  Future<bool> _searchPlaces(TaskContext ctx, _State st, HotspotQuery query, {required String why}) async {
    ctx.say('is asking Bhatkanti to search again', why: 'The plan is not finished: $why.', kind: FeedKind.delegate);
    final found = await _runBhatkanti(
      ctx,
      st,
      query,
      title: query.radiusFactor > st.spotQuery.radiusFactor ? 'Look further out' : 'Search places again',
      say: query.radiusFactor > st.spotQuery.radiusFactor ? 'asked Bhatkanti to look further out' : 'asked Bhatkanti to search again',
    );
    if (found == null) return false;
    final before = st.spots?.pool.length ?? 0;
    st.spotQuery = query;
    st.spots = _mergeSpots(st.spots, found.$1, query);
    st.notes.addAll(found.$1.warnings.where((w) => !st.notes.contains(w)));
    return (st.spots?.pool.length ?? 0) > before;
  }

  /// Puts [gap] to the traveller as a choice of real options. Returns whether
  /// the plan changed and the days must be laid out again.
  Future<bool> _askGap(TaskContext ctx, _State st, PlanGap gap) async {
    final used = st.usedOptions.putIfAbsent(gap.id, () => {});
    final attempt = st.gapAsks[gap.id] = (st.gapAsks[gap.id] ?? 0) + 1;
    final near = gap.kind == GapKind.places || gap.kind == GapKind.day ? _nearMisses(st, gap) : const <(Hotspot, String)>[];
    final issue = PlanCompleteness.issueFor(
      gap,
      destination: st.brief.destination ?? 'the destination',
      used: used,
      rainBanned: gap.date != null && st.bannedOutdoor.contains(gap.date),
      nearMisses: near.length,
      transport: st.transport,
      chosen: st.chosen,
      origin: st.brief.originCity,
      attempt: attempt,
    );
    ctx.say('needs your decision to finish the plan', why: issue.why, kind: FeedKind.ask);
    final option = await _askIssue(ctx, issue);
    used.add(option.id);
    ctx.say('you chose: ${option.label}', why: 'Yatri acts on it and keeps going until the trip is whole.', kind: FeedKind.decide);

    switch (option.effect['action']) {
      case 'acceptGap':
        st.accepted.add(gap.id);
        st.notes.add(switch (gap.kind) {
          GapKind.day => 'You chose to keep day ${gap.day} light.',
          GapKind.places => 'You chose to explore on your own rather than have places planned.',
          GapKind.time => 'You chose to keep a journey that leaves little time at the destination.',
          GapKind.journey => 'You will book the journey yourself, so it is not in the plan or the budget.',
          GapKind.stay => 'You will arrange your own stay.',
        });
        return false;
      case 'stayOwn':
        st.stayOwn = true;
        st.accepted.add(gap.id);
        return true;
      case 'unbanOutdoor':
        final dates = option.effect['dates'];
        if (dates is List) st.bannedOutdoor.removeAll(dates.whereType<String>());
        st.notes.add('You chose to keep outdoor places on a rainy day; carry rain gear.');
        return true;
      case 'widenPlaces':
        final factor = st.spotQuery.radiusFactor * (st.repairs.contains('places.wider') ? 1.5 : 1.6);
        st.repairs.add('places.wider');
        return _searchPlaces(ctx, st, st.spotQuery.copyWith(radiusFactor: factor), why: 'you asked to look further out');
      case 'pickNearMiss':
        return _pickNearMisses(ctx, st, near);
      case 'widenStay':
        final before = st.hotel;
        await _hotelPhase(ctx, st, st.hotelQuery.copyWith(radiusKm: HotelGates.maxRadiusKm));
        return st.hotel != before;
      case 'retryJourney':
        if (st.origin == null && (st.brief.originCity ?? '').trim().isNotEmpty) st.origin = await _locateOrigin(st.brief.originCity!.trim());
        await _transportPhase(ctx, st);
        return st.chosen != null;
      default:
        return _applyChoice(ctx, st, option);
    }
  }

  /// Places Bhatkanti found that were not picked, with what keeps each from
  /// fitting, so the traveller can decide what is good enough.
  List<(Hotspot, String)> _nearMisses(_State st, PlanGap gap) {
    final spots = st.spots;
    if (spots == null) return const [];
    final picked = {...spots.selected.map((h) => h.id), ...st.forcedIds};
    final q = st.spotQuery;
    final rainy = gap.date != null && st.bannedOutdoor.contains(gap.date);
    final out = <(Hotspot, String)>[];
    for (final h in spots.pool) {
      if (picked.contains(h.id) || st.droppedIds.contains(h.id) || h.kind == HotspotKind.food || HotspotFinder.lodgingWords.hasMatch(h.name)) continue;
      if (rainy && h.isOutdoor) continue;
      final ruledOut = [for (final n in q.needs) if (h.access[n]?.level == SupportLevel.no) n];
      final unknown = [for (final n in q.needs) if (n != AccessibilityNeed.none && (h.access[n]?.level ?? SupportLevel.unknown) == SupportLevel.unknown) n];
      final reason = ruledOut.isNotEmpty
          ? 'Reported not to suit ${ruledOut.first.label.toLowerCase()}'
          : q.avoidsStairs && (h.kind == HotspotKind.adventure || HotspotFinder.stairWords.hasMatch(h.name) || RegExp(r'\b(trek|climb|steps|stairs|caves?)\b', caseSensitive: false).hasMatch(h.name))
          ? 'May involve stairs or a climb'
          : q.walksLittle && HotspotFinder.longWalkWords.hasMatch(h.name)
          ? 'Means a long walk'
          : unknown.isNotEmpty
          ? 'Access not confirmed for ${unknown.first.label.toLowerCase()}'
          : 'Further away or less known';
      out.add((h, reason));
      if (out.length >= 6) break;
    }
    return out;
  }

  /// The traveller picks which near misses are good enough; they join the plan.
  Future<bool> _pickNearMisses(TaskContext ctx, _State st, List<(Hotspot, String)> near) async {
    if (near.isEmpty) return false;
    final question = YatriQuestion(
      id: 'plan.places.nearMiss.${st.gapAsks.values.fold<int>(0, (a, b) => a + b)}',
      fields: const [],
      widget: AnswerWidget.multiSelect,
      defaultText: 'These places did not fully match your needs. Pick any that would be good enough:',
      reason: IssueKind.conflict,
      agent: AgentKind.yatri.name,
      why: 'Yatri left them out because of what is shown under each. You know your group best, so the choice is yours.',
      options: [
        for (final (h, reason) in near)
          QuestionOption(id: h.id, label: h.name, subtitle: '$reason · ${h.kind.name} · about ${durationLabel(h.visitMinutes)}'),
      ],
    );
    final answer = await _askQuestion(ctx, question);
    final ids = switch (answer) {
      MultiChoiceAnswer(:final optionIds) => optionIds,
      ChoiceAnswer(:final optionId) => {optionId},
      _ => const <String>{},
    };
    final chosen = [for (final (h, _) in near) if (ids.contains(h.id)) h];
    if (chosen.isEmpty) {
      ctx.say('added none of them', why: 'Yatri will offer the other ways to fill the day.', kind: FeedKind.decide);
      return false;
    }
    st.forcedIds.addAll(chosen.map((h) => h.id));
    st.notes.add('You added ${chosen.map((h) => h.name).join(', ')} knowing ${chosen.length == 1 ? 'it does' : 'they do'} not fully match your needs.');
    ctx.say(
      'added ${chosen.map((h) => h.name).take(3).join(', ')}${chosen.length > 3 ? ' and ${chosen.length - 3} more' : ''} to the plan',
      why: 'You chose them; Raah fits them into the days.',
      kind: FeedKind.decide,
    );
    return true;
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

  /// The farthest the group can walk between stops, from their own answer.
  static double? _walkLimitKm(TripBrief b) {
    final w = b.accessibilityDetails['a11y.mobility.walking'] ?? const {};
    if (w.contains('lt100')) return 0.1;
    if (w.contains('100_500')) return 0.4;
    if (w.contains('500_1000')) return 0.8;
    return null;
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
      ),
      (c) async {
        final pool = st.spots?.pool ?? const <Hotspot>[];
        final forced = [for (final h in pool) if (st.forcedIds.contains(h.id)) h];
        final chosen = [...?st.spots?.selected, for (final h in forced) if (!(st.spots?.selected.any((s) => s.id == h.id) ?? false)) h];
        final chosenIds = chosen.map((h) => h.id).toSet();
        // Spares may fill a short day, but never with a place the group must avoid.
        final alternates = [for (final h in pool) if (!chosenIds.contains(h.id) && !HotspotFinder.isExcluded(h, st.spotQuery)) h];
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
          walkLimitKm: _walkLimitKm(brief),
          slowPace: _slowPace(brief),
          restStops: brief.accessibilityDetails['a11y.mobility.support']?.contains('rest_stops') ?? false,
          dietary: brief.dietary,
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
      case 'keepUnconfirmed':
        st.notes.add('Some places have no confirmed access for your group; check with them before going.');
        return false;
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

  /// The destination, with its extent when it is a region rather than a town.
  Future<GeoArea?> _geocodeArea(String place) async {
    try {
      final a = await toolkit.geocoder.lookupArea(place);
      if (a != null) return a;
    } catch (_) {
      // fall through to the next geocoder
    }
    final p = await _geocode(place);
    return p == null ? null : GeoArea(p);
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

  /// Whether the geocoding service answers at all, to tell "no such place"
  /// from "no connection".
  Future<bool> _isOnline() async {
    try {
      final r = await toolkit.client
          .get(Uri.https('geocoding-api.open-meteo.com', '/v1/search', {'name': 'London', 'count': '1'}))
          .timeout(const Duration(seconds: 5));
      return r.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// A place name safe to put into searches and prompts: control characters
  /// and runs of spaces collapsed, and a sane length. Empty if nothing is left.
  static String cleanPlace(String? raw) {
    final t = (raw ?? '').replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= 80 ? t : t.substring(0, 80).trimRight();
  }

  static String? _notes(TripBrief brief) {
    final parts = [
      if (brief.stayTypes.isNotEmpty) brief.stayTypes.map((s) => s.label.toLowerCase()).join(' or '),
      if (cleanPlace(brief.notes).isNotEmpty) cleanPlace(brief.notes).substring(0, cleanPlace(brief.notes).length.clamp(0, 120)),
    ];
    return parts.isEmpty ? null : parts.join('; ');
  }
}
