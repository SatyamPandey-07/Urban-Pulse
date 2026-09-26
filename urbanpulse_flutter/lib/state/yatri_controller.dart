import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../agents/core/yatri_agent.dart';
import '../agents/runtime/agent_toolkit.dart';
import '../agents/runtime/demo_plan.dart';
import '../agents/runtime/plan_clock.dart';
import '../agents/runtime/task_board.dart';
import '../agents/runtime/task_graph.dart';
import '../agents/planner/trip_plan_handoff_agent.dart';
import '../agents/receptionist/receptionist_agent.dart';
import '../agents/yatri/planner_orchestrator.dart';
import '../domain/trip_brief/answer_applier.dart';
import '../domain/trip_brief/brief_merger.dart';
import '../domain/trip_brief/brief_validator.dart';
import '../domain/trip_brief/extraction.dart';
import '../domain/trip_brief/question_catalog.dart';
import '../domain/route_path.dart';
import '../domain/trip_brief/question_planner.dart';
import '../models/itinerary/itinerary.dart';
import '../models/trip_brief.dart';
import '../models/trip_models.dart';
import '../models/yatri_question.dart';
import '../repositories/trip_brief_repository.dart';
import '../repositories/trip_repository.dart';
import '../services/groq_api_client.dart';

enum YatriPhase { intake, review, planning, done }

/// One row in the Yatri conversation.
sealed class ChatEntry {
  ChatEntry() : id = _next++;

  static int _next = 0;

  /// Stable key so a card keeps its local state while the list rebuilds.
  final int id;
}

class AgentText extends ChatEntry {
  AgentText(this.text);

  final String text;
}

class UserText extends ChatEntry {
  UserText(this.text);

  final String text;
}

class QuestionEntry extends ChatEntry {
  QuestionEntry(this.question);

  YatriQuestion question;
  YatriAnswer? answer;

  /// A newer question replaced this one before it was answered.
  bool superseded = false;

  bool get isActive => answer == null && !superseded;
}

class WelcomeEntry extends ChatEntry {}

class NoKeyEntry extends ChatEntry {
  NoKeyEntry({this.rejected = false});

  /// The key exists but the provider refused it (e.g. the example placeholder).
  final bool rejected;
}

class ErrorEntry extends ChatEntry {
  ErrorEntry(this.kind, this.retry);

  final GroqErrorKind kind;
  final Future<void> Function() retry;

  String get message => switch (kind) {
    GroqErrorKind.timeout => 'That took too long to answer.',
    GroqErrorKind.rateLimited => 'Yatri is getting a lot of requests right now.',
    GroqErrorKind.network => 'I couldn’t reach the network.',
    _ => 'Something went wrong on my side.',
  };
}

class ReviewReadyEntry extends ChatEntry {
  ReviewReadyEntry(this.brief);

  final TripBrief brief;
}

class PlanningEntry extends ChatEntry {}

/// The live multi-agent task graph, drawn inline in the chat.
class TaskGraphEntry extends ChatEntry {
  TaskGraphEntry(this.graph, this.clock);

  final TaskGraph graph;
  final PlanClock clock;
}

/// The route preview: origin and destination on a map, joined by an animated
/// line styled by the selected transport mode. It appears once both places are
/// fixed and updates in place as the places or transport change.
class RouteMapEntry extends ChatEntry {
  RouteMapEntry({required this.origin, required this.destination});

  String origin;
  String destination;
  LatLng? originPoint;
  LatLng? destinationPoint;
  bool loading = true;
  List<TripTransportMode> modes = const [];

  /// The mode currently previewed.
  TripTransportMode? shown;

  bool get ready => !loading && originPoint != null && destinationPoint != null;
}

class PlanEntry extends ChatEntry {
  PlanEntry(this.plan);

  final TripPlan plan;
  bool saved = false;
}

/// The finished multi-agent itinerary, with Save and Open actions.
class ItineraryEntry extends ChatEntry {
  ItineraryEntry(this.itinerary);

  final Itinerary itinerary;
  bool saved = false;
}

/// One chip of the progress strip / side panel.
class ProgressItem {
  const ProgressItem(this.label, this.questionId, this.done, this.value);

  final String label;
  final String questionId;
  final bool done;
  final String? value;
}

/// Runs the receptionist loop: user input -> extract -> merge -> validate ->
/// next question, until every mandatory field is valid, then review and
/// hand-off. All decisions live in the pure domain layer; this class only
/// sequences them and owns the conversation list.
class YatriController extends ChangeNotifier {
  YatriController({
    required this.receptionist,
    required this.handoff,
    required this.briefs,
    required this.trips,
    required this.hasKey,
    this.detectedCity = _none,
    this.settingsNeeds = _noNeeds,
    this.onTripPlanned,
    this.onTripSaved,
    this.geocode,
    this.toolkit,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    brief = TripBrief.empty(_clock());
  }

  static String? _none() => null;
  static Set<AccessibilityNeed> _noNeeds() => const {};

  final ReceptionistAgent receptionist;
  final TripPlanHandoffAgent handoff;
  final TripBriefRepository briefs;
  final TripRepository trips;
  final bool Function() hasKey;
  final String? Function() detectedCity;
  final Set<AccessibilityNeed> Function() settingsNeeds;
  final Future<void> Function()? onTripPlanned;
  final Future<void> Function()? onTripSaved;

  /// Looks up a place's coordinates for the route map. Null disables the map.
  final Future<LatLng?> Function(String place)? geocode;

  /// The multi-agent planner's tools. Null keeps the phase-1 single-call planner.
  final AgentToolkit? toolkit;
  final DateTime Function() _clock;

  final List<ChatEntry> entries = [];
  final Map<String, Completer<YatriAnswer>> _planWaiters = {};
  final PlannerState _state = PlannerState();
  final List<GroqMessage> _history = [];

  late TripBrief brief;
  YatriPhase phase = YatriPhase.intake;
  bool busy = false;
  bool _disposed = false;

  DateTime get now => _clock();

  ValidationReport get report => BriefValidator.validate(brief, now);

  QuestionEntry? get activeQuestion {
    for (final e in entries.reversed) {
      if (e is QuestionEntry && e.isActive) return e;
    }
    return null;
  }

  /// The composer only works while a conversation with the model is possible.
  bool get canType =>
      hasKey() && !busy && (phase == YatriPhase.intake || phase == YatriPhase.review);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // --- lifecycle -----------------------------------------------------------

  void start() {
    entries.clear();
    _history.clear();
    _state.reset();
    brief = TripBrief.empty(now);
    phase = YatriPhase.intake;
    busy = false;
    entries.add(hasKey() ? WelcomeEntry() : NoKeyEntry());
    _notify();
  }

  // --- progress ------------------------------------------------------------

  List<ProgressItem> get progress {
    final r = report;
    bool done(BriefField f) => !r.hasIssueFor(f);
    String? date() => brief.start == null || brief.end == null
        ? null
        : DateRangeAnswer(brief.start!, brief.end!).displayLabel;

    return [
      ProgressItem('Destination', 'destination', done(BriefField.destination), brief.destination),
      ProgressItem('From', 'origin', done(BriefField.origin), brief.originCity),
      ProgressItem('Dates', 'dates', done(BriefField.dates), date()),
      ProgressItem('Travellers', 'travellers', done(BriefField.travellers),
          brief.travellerCount?.toString()),
      ProgressItem('Group', 'group', done(BriefField.group),
          brief.hasPartsBreakdown
              ? GroupAnswer(
                  adults: brief.adults!,
                  seniors: brief.seniors!,
                  children: brief.children!,
                  women: brief.women ?? 0,
                  childAges: brief.childAges,
                ).displayLabel
              : null),
      if ((brief.women ?? 0) > 0)
        ProgressItem('Safety', 'womenSafety', done(BriefField.womenSafety),
            brief.womenSafety.map((s) => s.label).join(', ')),
      ProgressItem(
        'Accessibility',
        'accessibility',
        done(BriefField.accessibility) && done(BriefField.accessibilityDetails),
        brief.accessibilityConfirmed
            ? brief.accessibilityNeeds.map((n) => n.label).join(', ')
            : null,
      ),
      ProgressItem('Transport', 'transport', done(BriefField.transport),
          brief.transportModes.map((m) => m.label).join(', ')),
      ProgressItem('Budget', 'budget', done(BriefField.budget),
          brief.budgetMaxInr == null ? null : '₹${brief.budgetMinInr ?? 0} – ₹${brief.budgetMaxInr}'),
    ];
  }

  // --- user input ----------------------------------------------------------

  /// Free text, typed or dictated. Goes through model extraction.
  Future<void> sendText(String raw, {bool addBubble = true}) async {
    final text = raw.trim();
    if (text.isEmpty || busy) return;
    if (phase == YatriPhase.planning || phase == YatriPhase.done) return;

    if (!hasKey()) {
      if (entries.isEmpty || entries.last is! NoKeyEntry) entries.add(NoKeyEntry());
      _notify();
      return;
    }

    if (addBubble) entries.add(UserText(text));
    if (phase == YatriPhase.review) phase = YatriPhase.intake;
    busy = true;
    _notify();

    final pending = activeQuestion;
    final result = await receptionist.run(
      ReceptionistInput(
        text: text,
        brief: brief,
        pending: pending?.question,
        history: List.unmodifiable(_history),
      ),
    );

    switch (result) {
      case AgentErr(:final kind, :final isKeyProblem):
        busy = false;
        entries.add(
          isKeyProblem
              ? NoKeyEntry(rejected: kind == GroqErrorKind.unauthorized)
              : ErrorEntry(kind, () => sendText(text, addBubble: false)),
        );
        _notify();
        return;
      case AgentOk(:final value):
        _remember('user', text);
        await _handleExtraction(value, pending);
    }
  }

  Future<void> _handleExtraction(Extraction ex, QuestionEntry? pending) async {
    var b = brief;

    // The message may also answer the card that is on screen.
    if (pending != null) {
      final answer = _answerFromExtraction(pending.question, ex);
      if (answer != null) {
        final res = AnswerApplier.apply(b, pending.question, answer, now);
        if (res.isOk) {
          b = res.brief!;
          pending.answer = answer;
          _state.attempts.remove(pending.question.id);
        }
      }
    }

    final merge = BriefMerger.apply(b, ex);
    brief = merge.brief;

    if (ex.offTopic && ex.updates.isEmpty) {
      entries.add(
        AgentText(
          ex.ack ??
              'I can only help with planning your trip here. '
                  'Tell me about it or use the cards below.',
        ),
      );
      busy = false;
      _notify();
      return;
    }

    final understood =
        !ex.isEmpty || merge.changes.isNotEmpty || (pending?.answer != null);
    if (!understood) {
      entries.add(
        AgentText(
          ex.clarify ??
              'I didn’t catch any trip details there. Try something like '
                  '“Munnar with my family of 4 next weekend”, or use the cards.',
        ),
      );
      if (pending != null) {
        busy = false;
        _notify();
        return;
      }
    }

    await _advance(
      ack: understood ? (ex.clarify ?? ex.ack) : null,
      changes: merge.changes,
      phrase: true,
    );
  }

  YatriAnswer? _answerFromExtraction(YatriQuestion q, Extraction ex) {
    switch (q.widget) {
      case AnswerWidget.yesNo:
        return ex.pendingBool == null ? null : BoolAnswer(ex.pendingBool!);
      case AnswerWidget.mcq:
        final ids = ex.pendingOptionIds;
        if (ids == null || ids.isEmpty) return null;
        for (final o in q.options) {
          if (ids.contains(o.id)) return ChoiceAnswer(o.id, o.label);
        }
        return null;
      case AnswerWidget.multiSelect:
        final ids = ex.pendingOptionIds;
        if (ids == null || ids.isEmpty) return null;
        final chosen = [for (final o in q.options) if (ids.contains(o.id)) o];
        if (chosen.isEmpty) return null;
        return MultiChoiceAnswer(
          {for (final o in chosen) o.id},
          [for (final o in chosen) o.label],
        );
      default:
        return null;
    }
  }

  /// A structured answer from a card. No model call is needed to apply it.
  Future<void> answer(YatriQuestion q, YatriAnswer a) async {
    // A question an agent asked mid-plan: hand the answer straight back to the
    // waiting agent. (It is allowed while the plan is busy, that is the point.)
    final waiter = _planWaiters[q.id];
    if (waiter != null) {
      final planEntry = _entryFor(q);
      if (planEntry == null || !planEntry.isActive) return;
      planEntry.answer = a;
      entries.add(UserText(a.displayLabel));
      _planWaiters.remove(q.id);
      waiter.complete(a);
      _notify();
      return;
    }

    if (busy) return;
    final entry = _entryFor(q);
    if (entry == null || !entry.isActive) return;

    final res = AnswerApplier.apply(brief, q, a, now);
    if (!res.isOk) {
      final attempt = (_state.attempts[q.id] ?? 0) + 1;
      _state.attempts[q.id] = attempt;
      entry.question = q.copyWith(hint: res.error, attempt: attempt);
      _notify();
      return;
    }

    entry.answer = a;
    entries.add(UserText(a.displayLabel));
    _remember('user', a.displayLabel);
    brief = res.brief!;
    _state.attempts.remove(q.id);
    _state.nbaQueue.remove(q.id);
    if (phase == YatriPhase.review) phase = YatriPhase.intake;
    busy = true;
    _notify();
    await _advance();
  }

  QuestionEntry? _entryFor(YatriQuestion q) {
    for (final e in entries.reversed) {
      if (e is QuestionEntry && e.question.id == q.id && e.isActive) return e;
    }
    return null;
  }

  /// Re-opens one answered question, pre-filled, from the progress strip.
  Future<void> editQuestion(String questionId) async {
    if (busy || phase == YatriPhase.planning || phase == YatriPhase.done) return;
    for (final e in entries) {
      if (e is QuestionEntry && e.isActive) e.superseded = true;
    }
    if (phase == YatriPhase.review) phase = YatriPhase.intake;
    final q = QuestionCatalog.build(
      questionId,
      brief,
      now: now,
      reason: IssueKind.edit,
      detectedCity: detectedCity(),
      settingsNeeds: settingsNeeds(),
    );
    entries.add(QuestionEntry(q));
    _notify();
  }

  // --- loop ---------------------------------------------------------------

  Future<void> _advance({
    String? ack,
    List<BriefChange> changes = const [],
    bool phrase = false,
  }) async {
    _syncMap();

    YatriQuestion? planNext() => QuestionPlanner.next(
      brief,
      report,
      _state,
      now: now,
      detectedCity: detectedCity(),
      settingsNeeds: settingsNeeds(),
    );

    var q = planNext();

    // Every mandatory field is valid: let the model decide, once, whether an
    // extra question or two would improve the plan. It costs at most one small
    // call and none when the brief is already rich.
    if (q == null && !_state.nbaConsulted && hasKey()) {
      _state.nbaConsulted = true;
      _state.nbaQueue.addAll(await receptionist.nextBest(brief));
      q = planNext();
    }

    if (q == null) {
      _enterReview();
      return;
    }

    final needsPhrasing =
        phrase ||
        q.reason == IssueKind.conflict ||
        q.reason == IssueKind.invalid;
    PhrasedQuestion? phrased;
    if (needsPhrasing && hasKey()) {
      phrased = await receptionist.phrase(q, brief, ack: ack, changes: changes);
      if (phrased != null) {
        // The model may choose the widget, but only from the allow-list.
        q = q.copyWith(
          text: phrased.message,
          variant: QuestionCatalog.validVariant(q.id, phrased.widget),
        );
      }
    }
    if (phrased == null && ack != null) entries.add(AgentText(ack));

    for (final e in entries) {
      if (e is QuestionEntry && e.isActive) e.superseded = true;
    }
    entries.add(QuestionEntry(q));
    _remember('assistant', q.displayText);
    busy = false;
    _notify();
  }

  // --- multi-agent planning -------------------------------------------------

  /// Puts a question from a planner agent in front of the user and waits for
  /// the answer. Used by agents through `TaskContext.waitForUser`, which pauses
  /// the plan clock meanwhile. The question card carries a “?” with [why].
  Future<YatriAnswer> askPlanQuestion(YatriQuestion q) {
    final existing = _planWaiters[q.id];
    if (existing != null) return existing.future;
    final completer = Completer<YatriAnswer>();
    _planWaiters[q.id] = completer;
    entries.add(QuestionEntry(q));
    _remember('assistant', q.displayText);
    _notify();
    return completer.future;
  }

  /// A scripted, offline run of the whole planner so the task graph can be
  /// seen working (menu: "Preview agent graph"). No model or network is used.
  Future<void> startDemoPlan({double speed = 1.0}) async {
    if (busy || phase == YatriPhase.planning) return;
    phase = YatriPhase.planning;
    busy = true;
    final graph = TaskGraph();
    final clock = PlanClock();
    final board = TaskBoard(graph: graph, clock: clock);
    entries.add(TaskGraphEntry(graph, clock));
    _notify();

    var n = 0;
    final report = await runDemoPlan(
      board,
      speed: speed,
      ask: (question, options) async {
        final id = 'plan.demo.${n++}';
        final a = await askPlanQuestion(
          YatriQuestion(
            id: id,
            fields: const [],
            widget: AnswerWidget.mcq,
            defaultText: question,
            reason: IssueKind.optional,
            agent: 'yatri',
            why:
                'Yatri is the only agent that decides. When two goals collide '
                '(access and budget here), it asks you rather than choosing for you.',
            options: [
              for (var i = 0; i < options.length; i++)
                QuestionOption(id: 'o$i', label: options[i], recommended: i == 0),
            ],
          ),
        );
        return a is ChoiceAnswer ? a.label : options.first;
      },
    );

    entries.add(AgentText('${report.summary}. This was a preview run: no real data was used.'));
    phase = YatriPhase.done;
    busy = false;
    _notify();
  }

  // --- route map ------------------------------------------------------------

  /// Adds the route map once the origin and destination are both fixed (valid
  /// and confirmed), and keeps it in step with later changes to the places or
  /// the selected transport modes.
  void _syncMap() {
    final lookup = geocode;
    if (lookup == null) return;

    final origin = brief.originCity?.trim();
    final destination = brief.destination?.trim();
    final r = report;
    final fixed =
        origin != null &&
        origin.isNotEmpty &&
        destination != null &&
        destination.isNotEmpty &&
        !r.hasIssueFor(BriefField.origin) &&
        !r.hasIssueFor(BriefField.destination);
    if (!fixed) return;

    var entry = entries.whereType<RouteMapEntry>().firstOrNull;
    if (entry == null) {
      entry = RouteMapEntry(origin: origin, destination: destination);
      entries.add(entry);
      _resolveMap(entry, lookup);
    } else if (entry.origin != origin || entry.destination != destination) {
      entry
        ..origin = origin
        ..destination = destination
        ..loading = true;
      _resolveMap(entry, lookup);
    }

    entry.modes = [
      for (final m in TripTransportMode.values)
        if (brief.transportModes.contains(m)) m,
    ];
    if (entry.shown == null || !entry.modes.contains(entry.shown)) {
      entry.shown = RouteStyles.preferred(entry.modes);
    }
  }

  Future<void> _resolveMap(
    RouteMapEntry entry,
    Future<LatLng?> Function(String) lookup,
  ) async {
    final o = entry.origin;
    final d = entry.destination;
    final points = await Future.wait([lookup(o), lookup(d)]);
    // The places changed while we were looking these up.
    if (entry.origin != o || entry.destination != d) return;
    entry
      ..originPoint = points[0]
      ..destinationPoint = points[1]
      ..loading = false;
    // The map is a nicety: if either place can't be found, drop it silently.
    if (!entry.ready) entries.remove(entry);
    _notify();
  }

  /// Previews another selected transport mode on the map.
  void showMode(RouteMapEntry entry, TripTransportMode mode) {
    if (!entry.modes.contains(mode)) return;
    entry.shown = mode;
    _notify();
  }

  void _enterReview() {
    phase = YatriPhase.review;
    for (final e in entries) {
      if (e is QuestionEntry && e.isActive) e.superseded = true;
    }
    final warnings = report.warnings;
    entries.add(
      AgentText(
        'That’s everything I need. '
        '${warnings.isEmpty ? '' : '${warnings.join(' ')} '}'
        'Please review your trip brief.',
      ),
    );
    entries.add(ReviewReadyEntry(brief));
    busy = false;
    _notify();
  }

  void _remember(String role, String content) {
    _history.add(GroqMessage(role, content));
    if (_history.length > 6) _history.removeRange(0, _history.length - 6);
  }

  // --- confirm & hand-off ---------------------------------------------------

  /// Called with the brief the review form validated and returned.
  Future<void> confirmBrief(TripBrief confirmed) async {
    if (busy) return;
    brief = confirmed;
    phase = YatriPhase.planning;
    busy = true;
    entries.add(UserText('Confirmed — plan my trip'));
    final tk = toolkit;
    if (tk == null) entries.add(PlanningEntry());
    _notify();

    await briefs.save(confirmed);
    if (tk != null) {
      await _planWithAgents(tk, confirmed);
      return;
    }
    final result = await handoff.run(confirmed);
    entries.removeWhere((e) => e is PlanningEntry);

    switch (result) {
      case AgentOk(:final value):
        phase = YatriPhase.done;
        entries
          ..add(
            AgentText(
              'Here’s a sustainable plan for ${confirmed.destination}. '
              'Save it to My Trips or open the full itinerary.',
            ),
          )
          ..add(PlanEntry(value));
        await onTripPlanned?.call();
      case AgentErr(:final kind):
        phase = YatriPhase.review;
        entries.add(ErrorEntry(kind, () => confirmBrief(confirmed)));
    }
    busy = false;
    _notify();
  }

  /// The multi-agent plan: Yatri and the workers run as a live task graph in
  /// the chat, and the result is a full itinerary. If the agents cannot produce
  /// one, the phase-1 planner drafts a plan instead so there is always a result.
  Future<void> _planWithAgents(AgentToolkit tk, TripBrief confirmed) async {
    final orchestrator = PlannerOrchestrator(toolkit: tk, ask: askPlanQuestion, now: () => now);
    entries.add(TaskGraphEntry(orchestrator.graph, orchestrator.clock));
    _notify();

    PlanOutcome outcome;
    try {
      outcome = await orchestrator.run(confirmed);
    } catch (_) {
      outcome = PlanOutcome.failed('Planning stopped unexpectedly');
    }

    if (outcome.status == PlanStatus.unlocatable) {
      // Nothing can be planned around a place that is not on the map: take the
      // destination back and ask again.
      brief = confirmed.clearing(BriefField.destination);
      phase = YatriPhase.intake;
      entries.add(
        AgentText(
          '${outcome.summary}. Which destination would you like instead? '
          'A city, town or region works best.',
        ),
      );
      busy = true;
      _notify();
      await _advance();
      return;
    }

    final itinerary = outcome.itinerary;
    if (itinerary != null) {
      phase = YatriPhase.done;
      final hotel = outcome.hotel;
      entries
        ..add(
          AgentText(
            hotel == null
                ? 'Here’s your ${itinerary.dayCount}-day plan for ${confirmed.destination}.'
                : 'Here’s your ${itinerary.dayCount}-day plan for ${confirmed.destination}, staying at ${hotel.name}.',
          ),
        )
        ..add(ItineraryEntry(itinerary));
      await onTripPlanned?.call();
      busy = false;
      _notify();
      return;
    }

    // The agents could not build a full itinerary: fall back to the phase-1 plan.
    final result = await handoff.run(confirmed);
    switch (result) {
      case AgentOk(:final value):
        final hotel = outcome.hotel;
        final needs = {
          for (final n in confirmed.accessibilityNeeds)
            if (n != AccessibilityNeed.none) n,
        };
        final plan = hotel == null
            ? value
            : value.copyWith(
                hotelName: hotel.name,
                hotelRating: hotel.rating,
                isStepFreeAccessible: needs.isNotEmpty && hotel.meets(needs) ? true : null,
              );
        phase = YatriPhase.done;
        final notes = outcome.notes.isEmpty ? '' : ' Note: ${outcome.notes.join('; ')}.';
        entries
          ..add(
            AgentText(
              hotel == null
                  ? 'Here’s a plan for ${confirmed.destination}, without a hotel.$notes'
                  : 'Here’s a plan for ${confirmed.destination}, staying at ${hotel.name}.$notes',
            ),
          )
          ..add(PlanEntry(plan));
        await onTripPlanned?.call();
      case AgentErr(:final kind):
        phase = YatriPhase.review;
        entries.add(ErrorEntry(kind, () => confirmBrief(confirmed)));
    }
    busy = false;
    _notify();
  }

  Future<void> saveItinerary(ItineraryEntry entry) async {
    if (entry.saved) return;
    await trips.addTrip(entry.itinerary.toTripPlan());
    entry.saved = true;
    await onTripSaved?.call();
    _notify();
  }

  Future<void> saveTrip(PlanEntry entry) async {
    if (entry.saved) return;
    await trips.addTrip(entry.plan);
    entry.saved = true;
    await onTripSaved?.call();
    _notify();
  }

  Future<void> retry(ErrorEntry entry) async {
    entries.remove(entry);
    _notify();
    await entry.retry();
  }
}
