import '../../domain/regional_defaults.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';

/// What the budget is worked out from.
class BudgetInput {
  const BudgetInput({
    required this.brief,
    required this.days,
    this.hotel,
    this.outbound,
    this.inbound,
    this.stayOwnArrangement = false,
  });

  final TripBrief brief;
  final List<ItineraryDay> days;
  final HotelOption? hotel;
  final TransportLeg? outbound;
  final TransportLeg? inbound;

  /// The traveller chose to arrange their own stay.
  final bool stayOwnArrangement;
}

/// Hisab's engine: adds up what the trip costs, line by line, from the choices
/// made. Deterministic. Every line says whether it is a real price or an
/// estimate, so the total is never more certain than it looks.
abstract final class BudgetEngine {
  /// Contingency on top of the subtotal.
  static const bufferShare = 0.07;

  static int nights(TripBrief b) {
    final s = b.start;
    final e = b.end;
    if (s == null || e == null) return 1;
    final n = DateTime(e.year, e.month, e.day).difference(DateTime(s.year, s.month, s.day)).inDays;
    return n < 1 ? 1 : n;
  }

  static int rooms(TripBrief b) {
    if (b.hasPartsBreakdown) {
      return RegionalDefaults.roomsFor(adults: b.adults!, seniors: b.seniors!, children: b.children!).clamp(1, 20);
    }
    final n = b.travellerCount ?? 2;
    return ((n < 1 ? 1 : n) + 1) ~/ 2;
  }

  static int travellers(TripBrief b) => (b.travellerCount ?? 1).clamp(1, 200);

  static int childCount(TripBrief b) => b.hasPartsBreakdown ? b.children! : 0;

  /// How pricey the place is, judged from the stay when there is one.
  static CostTier tierOf(HotelOption? hotel) {
    final p = hotel?.nightlyInr;
    if (p == null) return CostTier.mid;
    if (p <= 1800) return CostTier.budget;
    if (p <= 5500) return CostTier.mid;
    return CostTier.premium;
  }

  static Budget build(BudgetInput i) {
    final b = i.brief;
    final lines = <BudgetLine>[];
    final n = nights(b);
    final r = rooms(b);
    final pax = travellers(b);
    final kids = childCount(b);

    // Stay
    final hotel = i.hotel;
    if (hotel != null && hotel.nightlyInr != null) {
      final live = !hotel.priceIsEstimated && hotel.totalStayInr != null;
      final total = live ? hotel.totalStayInr! : hotel.nightlyInr! * n * r;
      lines.add(
        BudgetLine(
          label: '${hotel.name}: $n night${n == 1 ? '' : 's'}, $r room${r == 1 ? '' : 's'}',
          amountInr: total,
          category: BudgetCategory.stay,
          isEstimated: !live,
        ),
      );
    } else if (!i.stayOwnArrangement) {
      lines.add(
        BudgetLine(
          label: 'Stay (regional average): $n night${n == 1 ? '' : 's'}, $r room${r == 1 ? '' : 's'}',
          amountInr: RegionalDefaults.hotelNightlyInr(CostTier.mid) * n * r,
          category: BudgetCategory.stay,
        ),
      );
    }

    // Getting there and back
    final out = i.outbound;
    if (out != null) {
      final back = i.inbound ?? out;
      lines.add(BudgetLine(label: '${out.modeLabel} to ${out.to}', amountInr: out.costInr, category: BudgetCategory.transport, isEstimated: out.isEstimated));
      lines.add(BudgetLine(label: '${back.modeLabel} home', amountInr: back.costInr, category: BudgetCategory.transport, isEstimated: back.isEstimated));
    }

    // Moving around at the destination and paying to get in
    var local = 0;
    var fees = 0;
    for (final d in i.days) {
      for (final s in d.slots) {
        if (s.kind == SlotKind.transit && s.leg != null && !s.leg!.id.startsWith('intercity')) local += s.leg!.costInr;
        if (s.kind == SlotKind.visit) fees += s.costInr ?? 0;
      }
    }
    if (local > 0) {
      lines.add(BudgetLine(label: 'Local travel (cabs, autos)', amountInr: local, category: BudgetCategory.transport));
    }
    if (fees > 0) {
      lines.add(BudgetLine(label: 'Entry fees and activities', amountInr: fees, category: BudgetCategory.activities));
    }

    // Food
    final tier = tierOf(hotel);
    final perDay = RegionalDefaults.foodPerPersonDayInr(tier);
    final foodDays = i.days.isEmpty ? b.days : i.days.length;
    final eaters = (pax - kids) + kids * 0.6;
    lines.add(
      BudgetLine(
        label: 'Meals: about ₹$perDay per person a day',
        amountInr: (perDay * eaters * foodDays).round(),
        category: BudgetCategory.food,
      ),
    );

    final subtotal = lines.fold<int>(0, (s, l) => s + l.amountInr);
    lines.add(
      BudgetLine(
        label: 'Buffer for surprises (${(bufferShare * 100).round()}%)',
        amountInr: (subtotal * bufferShare / 50).round() * 50,
        category: BudgetCategory.buffer,
      ),
    );

    return Budget(lines: lines, budgetMinInr: b.budgetMinInr, budgetMaxInr: b.budgetMaxInr);
  }

  /// The paid visits Yatri could drop, cheapest to lose first (lowest importance).
  static List<({String id, String name, int fee, double score})> paidVisits(List<ItineraryDay> days, Map<String, Hotspot> byId) {
    final out = <({String id, String name, int fee, double score})>[];
    for (final d in days) {
      for (final s in d.slots) {
        if (s.kind != SlotKind.visit || s.refId == null || (s.costInr ?? 0) <= 0) continue;
        out.add((id: s.refId!, name: s.title, fee: s.costInr!, score: byId[s.refId!]?.score ?? 0.5));
      }
    }
    out.sort((a, b) => a.score.compareTo(b.score));
    return out;
  }
}
