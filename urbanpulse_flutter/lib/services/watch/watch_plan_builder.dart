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

/// Builds the steps for [day], in time order.
///
/// [rest] slots are dropped: "free time" is not an instruction, and every step
/// on the watch costs a press to scroll past.
List<WatchStep> buildWatchPlan(ItineraryDay day) {
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
