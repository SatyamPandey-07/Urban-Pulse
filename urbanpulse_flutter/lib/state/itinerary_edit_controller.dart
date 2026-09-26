import 'dart:async';

import 'package:flutter/material.dart';

import '../agents/editor/edit_ops.dart';
import '../agents/editor/itinerary_diff.dart';
import '../agents/editor/itinerary_editor.dart';
import '../agents/runtime/agent_toolkit.dart';
import '../agents/runtime/plan_clock.dart';
import '../agents/runtime/task_graph.dart';
import '../models/itinerary/itinerary.dart';
import '../models/trip_brief.dart';
import '../models/yatri_question.dart';
import '../services/groq_api_client.dart';

/// One line of the edit conversation.
class EditMessage {
  EditMessage(this.text, {this.fromUser = false, this.diff, this.failed = false});

  final String text;
  final bool fromUser;

  /// What the edit changed, on the agent's reply that applied it.
  final ItineraryDiff? diff;
  final bool failed;
}

/// A one-tap change offered under the composer.
class EditChip {
  const EditChip(this.label, this.icon, this.ops);

  final String label;
  final IconData icon;
  final List<EditOp> ops;
}

/// Runs edits for one open itinerary: each request goes to Yatri in edit mode
/// ([ItineraryEditor]), questions come back to the traveller, and the plan is
/// replaced (with undo) only when an edit fully succeeds.
class ItineraryEditController extends ChangeNotifier {
  ItineraryEditController({required this.toolkit, required Itinerary itinerary, this.onChanged, DateTime Function()? now})
    : current = itinerary,
      _now = now ?? DateTime.now;

  final AgentToolkit toolkit;
  final Future<void> Function(Itinerary)? onChanged;
  final DateTime Function() _now;

  /// The plan as it is now.
  Itinerary current;

  final List<EditMessage> messages = [];
  final List<Itinerary> _undo = [];
  final List<Itinerary> _redo = [];
  final List<GroqMessage> _history = [];

  bool busy = false;
  YatriQuestion? pending;
  Completer<YatriAnswer>? _pendingAnswer;
  ItineraryEditor? _editor;
  int _token = 0;
  bool _disposed = false;

  static const maxUndo = 5;

  TaskGraph? get graph => _editor?.graph;
  PlanClock? get clock => _editor?.clock;
  bool get canUndo => _undo.isNotEmpty && !busy;
  bool get canRedo => _redo.isNotEmpty && !busy;

  /// Whether this plan can be edited at all (it needs its trip details).
  bool get editable => current.brief != null && current.days.isNotEmpty;

  // --- what to offer ----------------------------------------------------------

  List<EditChip> get chips {
    final it = current;
    final brief = it.brief;
    if (brief == null) return const [];
    int visits(ItineraryDay d) => d.slots.where((s) => s.kind == SlotKind.visit).length;
    final busiest = ([...it.days]..sort((a, b) => visits(b).compareTo(visits(a)))).where((d) => visits(d) >= 3).take(2).toList()..sort((a, b) => a.number.compareTo(b.number));
    return [
      for (final d in busiest) EditChip('More rest on day ${d.number}', Icons.self_improvement_rounded, [RestDayOp(d.number, RestLevel.light)]),
      if (brief.sustainability != SustainabilityPriority.greenest) const EditChip('Make it greener', Icons.eco_rounded, [SetPreferencesOp(sustainability: SustainabilityPriority.greenest)]),
      if (brief.budgetMaxInr != null) const EditChip('Make it cheaper', Icons.savings_rounded, [SetPreferencesOp(budgetFactor: 0.85)]),
      const EditChip('A different hotel', Icons.hotel_rounded, [ChangeHotelOp()]),
      if (it.days.length < 14) const EditChip('Add a day', Icons.add_circle_outline_rounded, [ChangeDatesOp(deltaDays: 1)]),
      if (brief.pace != TripPace.relaxed) const EditChip('Slower pace', Icons.hourglass_bottom_rounded, [SetPreferencesOp(pace: TripPace.relaxed)]),
    ];
  }

  // --- requests ---------------------------------------------------------------

  /// A request in the traveller's own words.
  Future<void> send(String text) async {
    final t = text.trim();
    if (t.isEmpty || busy) return;
    messages.add(EditMessage(t, fromUser: true));
    await _execute((ed) => ed.edit(current, t, history: List.of(_history)), userText: t);
  }

  /// Operations that are already known (a chip, a tap on a stop).
  Future<void> run(List<EditOp> ops, {required String label}) async {
    if (busy || ops.isEmpty) return;
    messages.add(EditMessage(label, fromUser: true));
    await _execute((ed) => ed.apply(current, ops, request: label), userText: label);
  }

  Future<void> _execute(Future<EditOutcome> Function(ItineraryEditor) body, {required String userText}) async {
    if (!editable) {
      messages.add(EditMessage('This plan cannot be edited because it was saved without its trip details.', failed: true));
      _notify();
      return;
    }
    final token = ++_token;
    busy = true;
    final editor = ItineraryEditor(toolkit: toolkit, ask: _ask, now: _now);
    _editor = editor;
    _notify();

    EditOutcome outcome;
    try {
      outcome = await body(editor);
    } catch (_) {
      outcome = EditOutcome.failed('Something went wrong, so your plan was left as it was.');
    }
    if (_disposed || token != _token) return;

    busy = false;
    pending = null;
    _pendingAnswer = null;
    _history
      ..add(GroqMessage('user', userText.length > 300 ? userText.substring(0, 300) : userText))
      ..add(GroqMessage('assistant', outcome.say.length > 300 ? outcome.say.substring(0, 300) : outcome.say));
    if (_history.length > 6) _history.removeRange(0, _history.length - 6);

    final next = outcome.itinerary;
    if (outcome.status == EditStatus.applied && next != null) {
      _undo.add(current);
      if (_undo.length > maxUndo) _undo.removeAt(0);
      _redo.clear();
      current = next;
      messages.add(EditMessage(outcome.say, diff: outcome.diff));
      _notify();
      await _persist(next);
    } else {
      messages.add(EditMessage(outcome.say, failed: outcome.status == EditStatus.failed));
      _notify();
    }
  }

  // --- questions from the agents ----------------------------------------------

  Future<YatriAnswer> _ask(YatriQuestion q) {
    final c = Completer<YatriAnswer>();
    _pendingAnswer = c;
    pending = q;
    _notify();
    return c.future;
  }

  /// The traveller's answer to the open question.
  void answer(YatriAnswer a) {
    final c = _pendingAnswer;
    if (c == null || c.isCompleted) return;
    messages.add(EditMessage(a.displayLabel, fromUser: true));
    pending = null;
    _pendingAnswer = null;
    c.complete(a);
    _notify();
  }

  /// Stops the running edit; the plan stays as it was.
  void stop() {
    _editor?.stop();
    _release();
  }

  void _release() {
    final c = _pendingAnswer;
    pending = null;
    _pendingAnswer = null;
    if (c != null && !c.isCompleted) c.complete(const ChoiceAnswer('', ''));
    _notify();
  }

  // --- history ----------------------------------------------------------------

  Future<void> undo() async {
    if (!canUndo) return;
    _redo.add(current);
    current = _undo.removeLast();
    messages.add(EditMessage('Undone. Your plan is back to version ${current.version}.'));
    _notify();
    await _persist(current);
  }

  Future<void> redo() async {
    if (!canRedo) return;
    _undo.add(current);
    current = _redo.removeLast();
    messages.add(EditMessage('Redone. Your plan is at version ${current.version} again.'));
    _notify();
    await _persist(current);
  }

  Future<void> _persist(Itinerary it) async {
    try {
      await onChanged?.call(it);
    } catch (_) {
      // saving is best effort: the plan on screen is what matters
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token++;
    _editor?.stop();
    final c = _pendingAnswer;
    if (c != null && !c.isCompleted) c.complete(const ChoiceAnswer('', ''));
    super.dispose();
  }
}
