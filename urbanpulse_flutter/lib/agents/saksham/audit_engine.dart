import '../../domain/access/access_rules.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../runtime/report.dart';
import '../safar/transport_planner.dart';

/// What Saksham audits.
class AuditInput {
  const AuditInput({
    required this.needs,
    required this.days,
    required this.spots,
    this.hotel,
    this.outbound,
    this.inbound,
  });

  final Set<AccessibilityNeed> needs;
  final List<ItineraryDay> days;

  /// Every place the days can refer to, by id.
  final Map<String, Hotspot> spots;
  final HotelOption? hotel;
  final TransportLeg? outbound;
  final TransportLeg? inbound;
}

/// One thing in the plan that fails a need, with the evidence that says so.
class AccessFailure {
  const AccessFailure({required this.id, required this.name, required this.kind, required this.needs, this.importance = 0});

  final String id;
  final String name;
  final SlotKind kind;
  final List<AccessibilityNeed> needs;

  /// 0..1 how important the place is to the trip (for deciding to ask).
  final double importance;
}

class AuditResult {
  const AuditResult({required this.audit, this.failures = const [], this.unknownPlaces = const []});

  final AccessibilityAudit audit;

  /// Places, the stay and the journey with a real source saying "no".
  final List<AccessFailure> failures;

  /// Places nobody could say anything about (candidates for a model reading).
  final List<Hotspot> unknownPlaces;

  List<AccessFailure> get failedPlaces => [for (final f in failures) if (f.kind == SlotKind.visit || f.kind == SlotKind.meal) f];
  AccessFailure? get failedHotel => failures.where((f) => f.kind == SlotKind.stay).firstOrNull;
  AccessFailure? get failedJourney => failures.where((f) => f.kind == SlotKind.transit).firstOrNull;
}

/// Saksham's rules: walks through every step of the journey (the stay, the
/// travel there and back, each place, each way of getting around) and reads
/// how well it works for every need in the group. Deterministic; gaps stay
/// "unknown" until a labelled model reading fills them.
abstract final class AuditEngine {
  static AuditResult run(AuditInput i) {
    final needs = [for (final n in AccessRules.relevant(i.needs)) n];
    final items = <AuditItem>[];
    final failures = <AccessFailure>[];
    final unknown = <Hotspot>[];

    NeedSupport reading(Map<AccessibilityNeed, NeedSupport> m, AccessibilityNeed n) =>
        m[n] ??
        NeedSupport(need: n, level: SupportLevel.unknown, detail: 'No information found', provenance: const Provenance(source: 'none', confidence: 0));

    void add(String name, SlotKind kind, List<NeedSupport> checks, {String? id, double importance = 0}) {
      final overall = AuditItem(name: name, kind: kind, checks: checks).overall;
      final realNo = [for (final c in checks) if (c.level == SupportLevel.no && !c.provenance.isEstimated) c.need];
      items.add(
        AuditItem(
          name: name,
          kind: kind,
          checks: checks,
          action: switch (overall) {
            SupportLevel.yes => 'Keep',
            SupportLevel.no => realNo.isNotEmpty ? 'Replace or ask' : 'Confirm before booking',
            SupportLevel.partial => 'Confirm before booking',
            SupportLevel.unknown => 'Confirm before booking',
          },
        ),
      );
      if (realNo.isNotEmpty) {
        failures.add(AccessFailure(id: id ?? name, name: name, kind: kind, needs: realNo, importance: importance));
      }
    }

    if (needs.isEmpty) {
      return AuditResult(audit: const AccessibilityAudit(items: []));
    }

    // 1. The stay
    final hotel = i.hotel;
    if (hotel != null) {
      add(hotel.name, SlotKind.stay, [for (final n in needs) reading(hotel.access, n)], id: hotel.id);
    }

    // 2. The journey there and back
    for (final leg in [i.outbound, i.inbound]) {
      if (leg == null) continue;
      final label = leg == i.outbound ? '${leg.mode.label} to ${leg.to}' : '${leg.mode.label} home';
      add(label, SlotKind.transit, [for (final n in needs) _modeReading(leg.mode, n)], id: leg.id);
      if (i.outbound != null && i.inbound != null && leg == i.outbound && i.inbound!.mode == leg.mode) break; // the same mode twice reads the same
    }

    // 3. Each place, and each meal at a named place
    final seen = <String>{};
    for (final d in i.days) {
      for (final s in d.slots) {
        if ((s.kind != SlotKind.visit && s.kind != SlotKind.meal) || s.refId == null || !seen.add(s.refId!)) continue;
        final h = i.spots[s.refId!];
        if (h == null) continue;
        final checks = [for (final n in needs) reading(h.access, n)];
        add(h.name, s.kind, checks, id: h.id, importance: h.score);
        if (checks.any((c) => c.level == SupportLevel.unknown)) unknown.add(h);
      }
    }

    // 4. Getting around: once per way of travelling
    final modes = <String, TransportLeg>{};
    var longestWalk = 0.0;
    for (final d in i.days) {
      for (final s in d.slots) {
        final l = s.leg;
        if (s.kind != SlotKind.transit || l == null || l.id.startsWith('intercity')) continue;
        if (l.walking) {
          if (l.distanceKm > longestWalk) longestWalk = l.distanceKm;
          modes.putIfAbsent('walk', () => l);
        } else {
          modes.putIfAbsent(l.mode.name, () => l);
        }
      }
    }
    for (final e in modes.entries) {
      final l = e.value;
      if (l.walking) {
        add('Short walks (up to ${(longestWalk * 1000).round()} m)', SlotKind.transit, [for (final n in needs) _walkReading(n, longestWalk)], id: 'local.walk');
      } else {
        add('Local travel by ${l.mode.label.toLowerCase()}', SlotKind.transit, [for (final n in needs) _modeReading(l.mode, n)], id: 'local.${l.mode.name}');
      }
    }

    // What the traveller still has to confirm, in plain language.
    final actions = <String>[];
    for (final item in items) {
      if (item.overall == SupportLevel.yes) continue;
      final needy = [
        for (final c in item.checks)
          if (c.level != SupportLevel.yes) _short(c.need),
      ];
      if (needy.isEmpty) continue;
      final verb = item.overall == SupportLevel.no ? 'is not suited to' : 'is unconfirmed for';
      actions.add('${item.name} $verb ${_join(needy)}: check with them before you go.');
    }

    return AuditResult(
      audit: AccessibilityAudit(items: items, actionsRequired: actions.take(10).toList()),
      failures: failures,
      unknownPlaces: unknown,
    );
  }

  /// A mode of transport read for one need, from the mode profile.
  static NeedSupport _modeReading(TripTransportMode mode, AccessibilityNeed n) {
    final (level, detail) = ModeAccess.of(mode, n);
    return NeedSupport(need: n, level: level, detail: detail, provenance: modeProvenance);
  }

  static NeedSupport _walkReading(AccessibilityNeed n, double km) {
    const prov = Provenance(source: 'Distance of the planned walks', confidence: 0.6);
    final m = (km * 1000).round();
    switch (n) {
      case AccessibilityNeed.wheelchair:
        return NeedSupport(need: n, level: m <= 150 ? SupportLevel.yes : SupportLevel.partial, detail: 'The longest walk is about $m m; pavements and kerbs on the way are not checked.', provenance: prov);
      case AccessibilityNeed.limitedMobility:
      case AccessibilityNeed.elderlyCare:
        return NeedSupport(need: n, level: m <= 300 ? SupportLevel.yes : SupportLevel.partial, detail: 'The longest walk is about $m m; the plan uses a cab for longer hops.', provenance: prov);
      case AccessibilityNeed.visual:
        return NeedSupport(need: n, level: SupportLevel.partial, detail: 'Short walks are best done with a companion or guide.', provenance: prov);
      case AccessibilityNeed.hearing:
        return NeedSupport(need: n, level: SupportLevel.yes, detail: 'Nothing about short walks depends on hearing, apart from traffic.', provenance: prov);
      default:
        return NeedSupport(need: n, level: SupportLevel.unknown, detail: 'Not assessed for short walks.', provenance: prov);
    }
  }

  static String _short(AccessibilityNeed n) => switch (n) {
    AccessibilityNeed.wheelchair => 'wheelchair access',
    AccessibilityNeed.limitedMobility => 'step-free access',
    AccessibilityNeed.visual => 'visual impairment',
    AccessibilityNeed.hearing => 'hearing impairment',
    AccessibilityNeed.elderlyCare => 'elderly guests',
    AccessibilityNeed.serviceAnimal => 'a service animal',
    AccessibilityNeed.cognitiveSensory => 'sensory or cognitive needs',
    AccessibilityNeed.otherSpecial => 'your special needs',
    AccessibilityNeed.none => 'your needs',
  };

  static String _join(List<String> parts) {
    if (parts.length <= 1) return parts.join();
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }
}
