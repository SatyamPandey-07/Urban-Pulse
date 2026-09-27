/// Turns a day of the itinerary into the numbered steps the watch scrolls
/// through.
///
/// The watch shows one step per screen — "3) Take the train from Panvel to
/// CST" — so each step has to be a complete instruction on its own. That is
/// what this builds: a sentence per slot, with the mode and the endpoints spelled
/// out, rather than the bare titles the phone's timeline can afford to use
/// because it has the surrounding rows for context.
///
/// Nothing is invented. Where the plan has no `from`/`to` for a leg, the step
/// says only what is known.
library;

import '../../models/itinerary/itinerary.dart';
import '../../models/trip_brief.dart';
import 'watch_protocol.dart';

/// What the watch should be showing right now, built from the plan alone.
///
/// This exists because Live Mode is not the only time the watch should have
/// something on it. A traveller who has a trip today and a paired watch expects
/// to see the day there, and "start Live Mode first" is a rule the watch has no
/// way to explain. So the phone publishes this whenever the watch connects, and
/// Live Mode then refines it with the traveller's actual position.
class WatchSnapshot {
  const WatchSnapshot({
    required this.steps,
    this.day,
    this.next,
    this.live = false,
  });

  final List<WatchStep> steps;

  /// "Day 2", when the trip has more than one.
  final String? day;

  /// The next stop by the clock. Carries no distance: without Live Mode running
  /// there is no position to measure from, and a guessed distance would be worse
  /// than none.
  final WatchNextStop? next;

  /// Whether Live Mode is driving this. False here by construction.
  final bool live;
}

/// How many days are sent to the watch at once.
///
/// A trip is scrolled through on a wrist, so the far end of a long one is of
/// little use, and every step costs memory the watch does not have much of.
const maxWatchPlanDays = 5;

/// How many steps are sent in total, across all days.
///
/// Must stay at or under the watch's own `LinkState.MAX_STEPS`, which is what
/// actually has to hold them.
const maxWatchPlanSteps = 40;

/// Builds the snapshot for [now] from the trips in [itineraries].
///
/// Carries **every upcoming day**, not just one: the watch shows them as a
/// single scrolling list with a heading per day, so scrolling past the end of
/// today continues into tomorrow. Days that have already passed are left out —
/// they are not a plan any more.
///
/// The trip chosen is the one that has today, or failing that the one starting
/// soonest. Days from different trips are never mixed: a traveller on a trip
/// does not want next month's holiday interleaved with this afternoon.
///
/// [WatchSnapshot.next] is only filled in when the first day is today: a "next
/// stop at 09:30" would otherwise be a claim about a day that has not arrived.
WatchSnapshot? buildWatchSnapshot(List<Itinerary> itineraries, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);

  List<ItineraryDay>? bestDays;
  DateTime? bestStart;
  var bestHasToday = false;

  for (final trip in itineraries) {
    // The trip's own upcoming days, in date order.
    final upcoming = [...trip.days]
      ..removeWhere((d) => DateTime(d.date.year, d.date.month, d.date.day).isBefore(today))
      ..sort((a, b) => a.date.compareTo(b.date));
    if (upcoming.isEmpty) continue;

    final withSteps = upcoming.where((d) => buildWatchPlan(d).isNotEmpty).toList();
    if (withSteps.isEmpty) continue;

    final first = DateTime(
      withSteps.first.date.year,
      withSteps.first.date.month,
      withSteps.first.date.day,
    );
    final hasToday = first == today;

    final better = bestDays == null ||
        (hasToday && !bestHasToday) ||
        (hasToday == bestHasToday && bestStart != null && first.isBefore(bestStart));
    if (better) {
      bestDays = withSteps;
      bestStart = first;
      bestHasToday = hasToday;
    }
    if (bestHasToday) break;
  }

  if (bestDays == null || bestDays.isEmpty) return null;

  final steps = <WatchStep>[];
  for (final day in bestDays.take(maxWatchPlanDays)) {
    for (final step in buildWatchPlan(day)) {
      if (steps.length >= maxWatchPlanSteps) break;
      steps.add(step);
    }
    if (steps.length >= maxWatchPlanSteps) break;
  }
  if (steps.isEmpty) return null;

  return WatchSnapshot(
    steps: steps,
    day: 'Day ${bestDays.first.number}',
    next: bestHasToday ? _nextByClock(bestDays.first, now) : null,
  );
}

/// The first slot of [day] that has not started yet, as a next stop.
WatchNextStop? _nextByClock(ItineraryDay day, DateTime now) {
  final slots = [...day.slots]..sort((a, b) => a.start.compareTo(b.start));
  for (final slot in slots) {
    if (slot.kind == SlotKind.rest) continue;
    if (slot.end.isBefore(now)) continue;
    return WatchNextStop(title: slot.title, at: watchClock(slot.start));
  }
  return null;
}

/// Builds the steps for [day], in time order.
///
/// [rest] slots are dropped: "free time" is not an instruction, and every step
/// on the watch costs a press to scroll past.
///
/// Numbering restarts at 1 for each day, because that is how a traveller reads
/// an itinerary — "step 3 of Tuesday", not "step 17 of the trip".
List<WatchStep> buildWatchPlan(ItineraryDay day, {String? label}) {
  final slots = [...day.slots]..sort((a, b) => a.start.compareTo(b.start));
  final steps = <WatchStep>[];
  for (final slot in slots) {
    if (slot.kind == SlotKind.rest) continue;
    final text = _describe(slot);
    if (text.isEmpty) continue;
    steps.add(WatchStep(
      number: steps.length + 1,
      at: watchClock(slot.start),
      text: text,
      mode: _mode(slot),
      day: label ?? 'Day ${day.number}',
    ));
  }
  return steps;
}

/// One instruction, as a person would say it.
String _describe(ItinerarySlot slot) {
  final leg = slot.leg;
  if (slot.kind == SlotKind.transit && leg != null) {
    final verb = leg.walking ? 'Walk' : 'Take the ${leg.modeLabel.toLowerCase()}';
    final from = leg.from.trim();
    final to = leg.to.trim();
    if (from.isNotEmpty && to.isNotEmpty) return '$verb from $from to $to';
    if (to.isNotEmpty) return '$verb to $to';
    // No endpoints known: the title is all there is, and it is better than
    // a sentence with a blank in it.
    return slot.title.trim().isEmpty ? verb : slot.title.trim();
  }

  final title = slot.title.trim();
  if (title.isEmpty) return '';
  return switch (slot.kind) {
    // Titles already read like "Lunch at Laxmi Restaurant", so a verb in front
    // of them would double up.
    SlotKind.meal => title,
    SlotKind.stay => title.toLowerCase().startsWith('check') ? title : 'Stay at $title',
    SlotKind.visit => title.toLowerCase().startsWith('visit') ? title : 'Visit $title',
    SlotKind.transit => title,
    SlotKind.rest => title,
  };
}

WatchStepMode _mode(ItinerarySlot slot) {
  if (slot.kind == SlotKind.meal) return WatchStepMode.meal;
  if (slot.kind == SlotKind.stay) return WatchStepMode.hotel;
  if (slot.kind == SlotKind.visit) return WatchStepMode.visit;

  final leg = slot.leg;
  if (leg == null) return WatchStepMode.other;
  if (leg.walking) return WatchStepMode.walk;
  return switch (leg.mode) {
    TripTransportMode.train || TripTransportMode.metroLocal => WatchStepMode.train,
    TripTransportMode.bus || TripTransportMode.eBus => WatchStepMode.bus,
    TripTransportMode.sharedEv ||
    TripTransportMode.selfDriveEv ||
    TripTransportMode.carTaxi => WatchStepMode.cab,
    TripTransportMode.flight => WatchStepMode.flight,
  };
}
