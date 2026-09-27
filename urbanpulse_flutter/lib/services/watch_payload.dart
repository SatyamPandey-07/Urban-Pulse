// The itinerary, shrunk to something a watch can hold and read.
//
// A Garmin device app has kilobytes to spend on a response and a single text
// font, so this projection does three jobs the watch should not have to:
//
//  * short keys - `ti` not `title`, because every byte crosses Bluetooth;
//  * wall-clock times already rendered (`hm`), so the watch does no date
//    arithmetic beyond comparing the epoch seconds it also gets (`a`, `z`);
//  * ASCII only, because the watch fonts have no rupee sign, degree sign or
//    en dash.
//
// The shape is the contract `garmin/source/TripStore.mc` reads, and `v` is what
// lets an older watch build refuse a payload it would only half understand.

import '../core/formatting.dart';
import '../models/itinerary/itinerary.dart';

/// The payload shape the watch app understands. Bump it only for a change the
/// watch cannot read past - the watch refuses anything newer than its own.
const watchPayloadVersion = 1;

/// Caps. A fortnight of days and a dozen stops a day is more than any plan the
/// planner produces, and keeps the payload inside the server's 16 KB limit.
const _maxDays = 14;
const _maxSlotsPerDay = 12;
const _maxTitle = 44;
const _maxNote = 64;

Map<String, dynamic> buildWatchPayload(Itinerary it) {
  final days = <Map<String, dynamic>>[];
  for (final day in it.days.take(_maxDays)) {
    days.add({
      'n': day.number,
      'dt': _ascii(compactDate(day.date)),
      if (day.weather != null && day.weather!.isNotEmpty)
        'w': _ascii(day.weather!),
      'sl': [
        for (final slot in day.slots.take(_maxSlotsPerDay)) _slot(slot),
      ],
    });
  }

  return {
    'v': watchPayloadVersion,
    't': _ascii(it.destination),
    if (it.origin.isNotEmpty) 'o': _ascii(it.origin),
    'dr': _ascii(dateRangeLabel(it.start, it.end)),
    if (it.hotel != null) 'hn': _ascii(it.hotel!.name),
    'b': it.budget.totalInr,
    if (it.budget.budgetMaxInr != null) 'bx': it.budget.budgetMaxInr,
    if (it.green != null) 'co2': it.green!.co2Kg.round(),
    // Overwritten by the server with its own clock, which is what makes the
    // watch's conditional GET immune to skew between the three devices.
    'u': it.createdAt.millisecondsSinceEpoch ~/ 1000,
    'd': days,
  };
}

Map<String, dynamic> _slot(ItinerarySlot slot) {
  final flags = slot.flags.where((f) => f.trim().isNotEmpty).toList();
  final position = slot.location;

  return {
    'k': slot.kind.name,
    'hm': clock24(slot.start),
    'a': slot.start.millisecondsSinceEpoch ~/ 1000,
    'z': slot.end.millisecondsSinceEpoch ~/ 1000,
    'ti': _ascii(slot.title, _maxTitle),
    if (slot.note != null && slot.note!.isNotEmpty)
      'no': _ascii(slot.note!, _maxNote),
    if (slot.costInr != null && slot.costInr! > 0) 'c': slot.costInr,
    if (flags.isNotEmpty) 'fl': _ascii(flags.join(' / '), _maxNote),
    // Only sent when the planner actually resolved the place: it is what lets
    // the watch show a distance and bearing to the next stop.
    if (position != null) 'la': _round5(position.latitude),
    if (position != null) 'ln': _round5(position.longitude),
  };
}

/// ~1 m of precision, which is finer than any fix a watch will have and saves
/// a dozen bytes per stop against a full double.
double _round5(double value) => (value * 100000).round() / 100000;

/// The punctuation the app uses freely and the watch cannot draw. Anything else
/// outside printable ASCII is dropped rather than shown as a blank box.
const _transliterations = {
  '₹': 'Rs ',
  '–': '-',
  '—': '-',
  '‑': '-',
  '·': '-',
  '•': '-',
  '’': "'",
  '‘': "'",
  '“': '"',
  '”': '"',
  '…': '...',
  '°': ' deg',
  '×': 'x',
  '₂': '2',
  'é': 'e',
  'á': 'a',
  'í': 'i',
  'ó': 'o',
  'ú': 'u',
  'ñ': 'n',
  'ü': 'u',
  'ā': 'a',
  'ī': 'i',
  'ū': 'u',
  'ṇ': 'n',
  'ṭ': 't',
  'ś': 's',
  'ṣ': 's',
};

String _ascii(String input, [int? max]) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final mapped = _transliterations[char];
    if (mapped != null) {
      out.write(mapped);
    } else if (rune >= 0x20 && rune < 0x7F) {
      out.write(char);
    }
    // Everything else — emoji, Devanagari, anything the watch cannot render —
    // is dropped, not replaced, so it leaves no debris on screen.
  }

  var text = out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (max != null && text.length > max) {
    // Cut back to a word boundary when there is a sensible one.
    var cut = text.substring(0, max);
    final space = cut.lastIndexOf(' ');
    if (space > max ~/ 2) cut = cut.substring(0, space);
    text = '$cut...';
  }
  return text;
}
