import '../../domain/regional_defaults.dart';
import '../../models/trip_brief.dart';

/// Hisab's first job: how much of the trip budget the stay can take. Pure and
/// deterministic. The full budget engine (transport, food, fees, buffer) comes
/// with the later stages; this is the part hotels need.
abstract final class HotelBudget {
  /// Share of the whole-trip budget a stay normally takes.
  static const stayShare = 0.4;

  /// The most to spend per room per night, or null when no budget was given.
  static int? nightlyCapInr(TripBrief brief) {
    final total = brief.budgetMaxInr;
    if (total == null || total <= 0) return null;
    final nights = stayNights(brief);
    final rooms = roomsFor(brief);
    final cap = (total * stayShare / nights / rooms);
    if (cap.isNaN || cap.isInfinite) return null;
    return cap.round().clamp(300, 500000);
  }

  /// Nights away, at least one.
  static int stayNights(TripBrief brief) {
    final s = brief.start;
    final e = brief.end;
    if (s == null || e == null) return 1;
    final n = DateTime(e.year, e.month, e.day).difference(DateTime(s.year, s.month, s.day)).inDays;
    return n < 1 ? 1 : n;
  }

  /// Rooms for the group.
  static int roomsFor(TripBrief brief) {
    if (brief.hasPartsBreakdown) {
      return RegionalDefaults.roomsFor(
        adults: brief.adults!,
        seniors: brief.seniors!,
        children: brief.children!,
      ).clamp(1, 20);
    }
    final n = brief.travellerCount ?? 2;
    return ((n < 1 ? 1 : n) + 1) ~/ 2;
  }

  /// Grown-ups, for a booking search (children usually do not change the price).
  static int adultsFor(TripBrief brief) {
    if (brief.hasPartsBreakdown) {
      final a = brief.adults! + brief.seniors!;
      return a < 1 ? 1 : a;
    }
    final n = brief.travellerCount ?? 2;
    return n < 1 ? 1 : n;
  }
}
