import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';

/// What changed between two versions of a plan, for the diff card and the log.
class ItineraryDiff {
  const ItineraryDiff({
    this.added = const [],
    this.removed = const [],
    this.moved = const [],
    this.hotelChange,
    this.transportChange,
    this.dayCountChange = 0,
    this.budgetDeltaInr = 0,
    this.co2DeltaKg = 0,
    this.accessChange,
  });

  /// "Tea Museum (day 2)".
  final List<String> added;
  final List<String> removed;

  /// "Fort: day 2 to day 3".
  final List<String> moved;
  final String? hotelChange;
  final String? transportChange;
  final int dayCountChange;
  final int budgetDeltaInr;
  final double co2DeltaKg;
  final String? accessChange;

  bool get isEmpty =>
      added.isEmpty && removed.isEmpty && moved.isEmpty && hotelChange == null && transportChange == null && dayCountChange == 0 && budgetDeltaInr == 0 && accessChange == null;

  /// Plain lines, most important first.
  List<String> lines() => [
    if (dayCountChange != 0) dayCountChange > 0 ? '${dayCountChange == 1 ? 'One day' : '$dayCountChange days'} added' : '${dayCountChange == -1 ? 'One day' : '${-dayCountChange} days'} removed',
    ?hotelChange,
    ?transportChange,
    for (final m in moved) 'Moved: $m',
    for (final a in added) 'Added: $a',
    for (final r in removed) 'Removed: $r',
    if (budgetDeltaInr != 0) 'Cost ${budgetDeltaInr > 0 ? 'up' : 'down'} by ${rupees(budgetDeltaInr.abs())}',
    if (co2DeltaKg.abs() >= 1) 'CO₂ ${co2DeltaKg > 0 ? 'up' : 'down'} by ${fixed(co2DeltaKg.abs(), 0)} kg',
    ?accessChange,
  ];

  static ItineraryDiff compute(Itinerary a, Itinerary b) {
    Map<String, (String, int)> stops(Itinerary it) {
      final out = <String, (String, int)>{};
      for (final d in it.days) {
        for (final s in d.slots) {
          if (s.kind == SlotKind.visit && s.refId != null) out.putIfAbsent(s.refId!, () => (s.title, d.number));
        }
      }
      return out;
    }

    final before = stops(a);
    final after = stops(b);
    final added = [for (final e in after.entries) if (!before.containsKey(e.key)) '${e.value.$1} (day ${e.value.$2})'];
    final removed = [for (final e in before.entries) if (!after.containsKey(e.key)) e.value.$1];
    final moved = [
      for (final e in after.entries)
        if (before[e.key] != null && before[e.key]!.$2 != e.value.$2) '${e.value.$1}: day ${before[e.key]!.$2} to day ${e.value.$2}',
    ];

    String? hotel;
    if (a.hotel?.id != b.hotel?.id) {
      hotel = b.hotel == null ? 'Stay removed' : 'Stay: ${a.hotel == null ? '' : '${a.hotel!.name} to '}${b.hotel!.name}';
    }
    String? transport;
    if (a.chosenTransport?.mode != b.chosenTransport?.mode && b.chosenTransport != null) {
      transport = 'Journey: ${a.chosenTransport == null ? '' : '${a.chosenTransport!.mode.label} to '}${b.chosenTransport!.mode.label}';
    }
    String? access;
    final ao = a.audit?.overall;
    final bo = b.audit?.overall;
    if (ao != null && bo != null && ao != bo) access = 'Access: ${ao.label} to ${bo.label}';

    return ItineraryDiff(
      added: added,
      removed: removed,
      moved: moved,
      hotelChange: hotel,
      transportChange: transport,
      dayCountChange: b.days.length - a.days.length,
      budgetDeltaInr: b.budget.totalInr - a.budget.totalInr,
      co2DeltaKg: (b.green?.co2Kg ?? 0) - (a.green?.co2Kg ?? 0),
      accessChange: access,
    );
  }
}
