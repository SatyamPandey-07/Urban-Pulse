import 'package:latlong2/latlong.dart';

import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';
import '../../state/live_map_controller.dart' show distanceWords;

/// What kind of thing Live Mode says.
enum UpdateKind { briefing, arrived, leaveNow, late, upcoming, meal, dayDone, info }

/// One line to be spoken (and shown).
class LiveUpdate {
  const LiveUpdate({required this.id, required this.kind, required this.text, required this.at});

  final String id;
  final UpdateKind kind;
  final String text;
  final DateTime at;

  /// Lower comes first when several are due together.
  int get priority => switch (kind) {
    UpdateKind.arrived => 0,
    UpdateKind.leaveNow => 1,
    UpdateKind.late => 2,
    UpdateKind.upcoming => 3,
    UpdateKind.meal => 4,
    UpdateKind.dayDone => 5,
    _ => 6,
  };
}

/// Decides what to say during a day of the trip, from the plan, the time and
/// where the traveller is. Pure: it holds what it already said, and nothing
/// else, so it can be tested without a phone. Nothing here is invented; the
/// times and places come from the plan, the position from the device, and
/// travel times are stated as estimates.
class LiveModeEngine {
  LiveModeEngine({required this.day, this.rainProbability, this.arriveWithinM = 80});

  final ItineraryDay day;

  /// Chance of rain for the day (0 to 100), when the forecast has one.
  final int? rainProbability;

  /// How close counts as having arrived.
  final double arriveWithinM;

  static const _dist = Distance();
  final Set<String> _said = {};
  final Set<int> _arrived = {};

  /// The slots worth speaking about: places and meals, in time order.
  late final List<ItinerarySlot> slots = [
    for (final s in day.slots)
      if (s.kind == SlotKind.visit || s.kind == SlotKind.meal) s,
  ]..sort((a, b) => a.start.compareTo(b.start));

  int get visited => _arrived.length;

  /// The first place or meal that is not over and not yet reached.
  ItinerarySlot? nextSlot(DateTime now) {
    for (var i = 0; i < slots.length; i++) {
      if (_arrived.contains(i)) continue;
      if (slots[i].end.isAfter(now)) return slots[i];
    }
    return null;
  }

  int? indexOf(ItinerarySlot s) {
    final i = slots.indexOf(s);
    return i < 0 ? null : i;
  }

  // --- the words ------------------------------------------------------------------

  /// What is said when Live Mode starts.
  LiveUpdate briefing(DateTime now) {
    final first = nextSlot(now);
    final rain = rainProbability;
    final bits = <String>[
      'Live mode is on. Day ${day.number}: ${day.title}.',
      if (first == null) 'There is nothing left in the plan for today.' else 'Coming up: ${first.title} at ${clock12(first.start)}.',
      if (rain != null && rain >= 50) 'Rain is likely today, about $rain percent. ${_outdoorNote()}',
      if (day.weather != null && (rain == null || rain < 50)) 'Weather: ${day.weather}.',
      'I will speak up before each stop. Say what is next, how far, or take me there whenever you like.',
    ];
    return LiveUpdate(id: 'briefing', kind: UpdateKind.briefing, text: bits.join(' '), at: now);
  }

  String _outdoorNote() {
    final outdoors = [for (final s in slots) if (s.kind == SlotKind.visit && s.flags.any((f) => f.toLowerCase().contains('outdoor'))) s.title];
    return outdoors.isEmpty ? 'Keep something for the rain with you.' : 'Outdoor today: ${outdoors.take(3).join(', ')}.';
  }

  /// Travel time estimate in minutes and how it is done, from a straight-line
  /// distance: on foot up close, otherwise by road with a detour allowance.
  static (int minutes, String how) travelEstimate(double meters) {
    if (meters <= 1500) return (((meters * 1.25) / 1000 / 4.8 * 60).ceil(), 'on foot');
    return (((meters * 1.35) / 1000 / 22 * 60).ceil(), 'by road');
  }

  /// What is due now. At most two updates, the most important first; the rest
  /// wait for the next check.
  List<LiveUpdate> check(DateTime now, LatLng? position) {
    final due = <LiveUpdate>[];

    for (var i = 0; i < slots.length; i++) {
      final s = slots[i];
      final loc = s.location;
      final metres = position != null && loc != null ? _dist.as(LengthUnit.Meter, position, loc) : null;
      final name = s.title;
      final isMeal = s.kind == SlotKind.meal;

      // arrived (places only, and only around their time)
      if (!isMeal && metres != null && metres <= arriveWithinM && !_arrived.contains(i) && now.isAfter(s.start.subtract(const Duration(minutes: 45))) && now.isBefore(s.end.add(const Duration(minutes: 45)))) {
        _arrived.add(i);
        final note = (s.note ?? '').trim();
        final left = s.end.difference(now).inMinutes;
        due.add(LiveUpdate(
          id: 'arrive:$i',
          kind: UpdateKind.arrived,
          text: "You've arrived at $name.${note.isEmpty ? '' : ' ${_short(note)}'}${left > 5 ? ' The plan gives you until ${clock12(s.end)}.' : ''}",
          at: now,
        ));
        continue;
      }
      if (_arrived.contains(i) || !s.end.isAfter(now)) continue;

      final untilStart = s.start.difference(now).inMinutes;

      // time to leave
      if (metres != null && !isMeal && untilStart >= 0 && untilStart <= 90 && !_said.contains('leave:$i')) {
        final (mins, how) = travelEstimate(metres);
        if (mins >= 4 && untilStart <= mins + 5) {
          _said.add('leave:$i');
          _said.add('soon:$i');
          due.add(LiveUpdate(
            id: 'leave:$i',
            kind: UpdateKind.leaveNow,
            text: 'Time to leave for $name at ${clock12(s.start)}. It is about ${distanceWords(metres)} away, roughly $mins minutes $how. That is an estimate.',
            at: now,
          ));
          continue;
        }
      }

      // running late
      if (!isMeal && untilStart < -15 && untilStart > -180 && !_said.contains('late:$i') && identical(nextSlot(now), s)) {
        _said.add('late:$i');
        due.add(LiveUpdate(
          id: 'late:$i',
          kind: UpdateKind.late,
          text: "You are about ${-untilStart} minutes behind for $name. Say what is next, or change the plan from the edit screen when you can.",
          at: now,
        ));
        continue;
      }

      // coming up
      if (untilStart >= 0 && untilStart <= 15 && !_said.contains('soon:$i')) {
        _said.add('soon:$i');
        final away = metres == null ? '' : ' It is ${distanceWords(metres)} from you.';
        due.add(LiveUpdate(
          id: 'soon:$i',
          kind: isMeal ? UpdateKind.meal : UpdateKind.upcoming,
          text: isMeal ? '$name is coming up at ${clock12(s.start)}, in $untilStart minutes.$away' : '$name at ${clock12(s.start)}, in $untilStart minutes.$away',
          at: now,
        ));
      }
    }

    // the end of the day
    if (slots.isNotEmpty && !slots.last.end.isAfter(now) && !_said.contains('done')) {
      _said.add('done');
      due.add(LiveUpdate(id: 'done', kind: UpdateKind.dayDone, text: "That is the plan for today. You reached $visited of ${slots.where((s) => s.kind == SlotKind.visit).length} places.", at: now));
    }

    due.sort((a, b) => a.priority.compareTo(b.priority));
    if (due.length > 2) {
      // Put back what will wait for the next check.
      for (final late in due.skip(2)) {
        _said.remove(late.id);
        if (late.kind == UpdateKind.arrived) _arrived.remove(int.parse(late.id.split(':').last));
        if (late.kind == UpdateKind.leaveNow) _said.remove('soon:${late.id.split(':').last}');
      }
      return due.take(2).toList();
    }
    return due;
  }

  static String _short(String s) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final end = one.indexOf(RegExp(r'[.!?]'));
    final first = end > 0 ? one.substring(0, end + 1) : one;
    return first.length > 160 ? '${first.substring(0, 157)}…' : first;
  }
}

/// What the traveller can ask for by voice.
enum LiveCommand { whatsNext, whereAmI, howFar, navigate, repeatLast, today, weather, quiet, resume, stop, unknown }

/// Reads a spoken request. Plain keywords, in English and common Hindi
/// phrasing, so it works without a model and never guesses beyond them.
LiveCommand parseLiveCommand(String raw) {
  final t = raw.toLowerCase().replaceAll(RegExp(r"[^a-z0-9ऀ-ॿ' ]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return LiveCommand.unknown;
  bool any(List<String> keys) => keys.any(t.contains);
  if (any(['stop live', 'end live', 'turn off live', 'stop hands', 'exit live', 'band karo'])) return LiveCommand.stop;
  if (any(['quiet', 'mute', 'be quiet', 'shut up', 'no updates', 'pause updates', 'chup'])) return LiveCommand.quiet;
  if (any(['resume', 'unmute', 'start updates', 'talk again', 'continue updates'])) return LiveCommand.resume;
  if (any(['repeat', 'say that again', 'say again', 'again please', 'dobara'])) return LiveCommand.repeatLast;
  if (any(['navigate', 'take me', 'directions', 'lead me', 'guide me', 'chalo', 'le chalo'])) return LiveCommand.navigate;
  if (any(['how far', 'how long', 'how much time', 'distance', 'kitna door', 'kitni door', 'eta'])) return LiveCommand.howFar;
  if (any(['where am i', 'my location', 'where are we', 'main kahan', 'mai kahan'])) return LiveCommand.whereAmI;
  if (any(['weather', 'rain', 'temperature', 'mausam', 'barish'])) return LiveCommand.weather;
  if (any(["what's next", 'whats next', 'what is next', 'next stop', 'next place', 'what now', 'what should i do', 'aage kya', 'agla', 'kya next'])) return LiveCommand.whatsNext;
  if (any(['today', 'plan for the day', 'the plan', 'schedule', 'aaj'])) return LiveCommand.today;
  return LiveCommand.unknown;
}
