import 'package:latlong2/latlong.dart';

import '../../core/formatting.dart';
import '../trip_brief.dart';
import '../trip_models.dart';
import 'itinerary_parts.dart';

enum SlotKind { stay, visit, meal, transit, rest }

/// One entry on a day's timeline.
class ItinerarySlot {
  const ItinerarySlot({
    required this.kind,
    required this.start,
    required this.end,
    required this.title,
    this.location,
    this.refId,
    this.note,
    this.costInr,
    this.leg,
    this.access,
    this.flags = const [],
  });

  final SlotKind kind;
  final DateTime start;
  final DateTime end;
  final String title;
  final LatLng? location;

  /// The hotel or hotspot this slot is about.
  final String? refId;
  final String? note;
  final int? costInr;

  /// For transit slots.
  final TransportLeg? leg;

  /// Overall accessibility of this step for the group, from Saksham.
  final SupportLevel? access;

  /// Short warnings ("Needs confirmation", "Rain likely").
  final List<String> flags;

  Duration get duration => end.difference(start);

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'title': title,
    'location': latLngToJson(location),
    'refId': refId,
    'note': note,
    'costInr': costInr,
    'leg': leg?.toJson(),
    'access': access?.name,
    'flags': flags,
  };

  static ItinerarySlot fromJson(Map<String, dynamic> j) => ItinerarySlot(
    kind: enumByName(SlotKind.values, j['kind'], SlotKind.visit),
    start: DateTime.tryParse(j['start'] as String? ?? '') ?? DateTime.now(),
    end: DateTime.tryParse(j['end'] as String? ?? '') ?? DateTime.now(),
    title: j['title'] as String? ?? '',
    location: latLngFromJson(j['location']),
    refId: j['refId'] as String?,
    note: j['note'] as String?,
    costInr: (j['costInr'] as num?)?.toInt(),
    leg: j['leg'] is Map<String, dynamic> ? TransportLeg.fromJson(j['leg'] as Map<String, dynamic>) : null,
    access: j['access'] == null ? null : enumByName(SupportLevel.values, j['access'], SupportLevel.unknown),
    flags: [for (final f in (j['flags'] as List<dynamic>? ?? const [])) '$f'],
  );
}

class ItineraryDay {
  const ItineraryDay({
    required this.number,
    required this.date,
    required this.title,
    required this.slots,
    this.weather,
  });

  final int number;
  final DateTime date;
  final String title;
  final List<ItinerarySlot> slots;

  /// e.g. "31°C, 20% rain".
  final String? weather;

  Map<String, dynamic> toJson() => {
    'number': number,
    'date': date.toIso8601String(),
    'title': title,
    'slots': [for (final s in slots) s.toJson()],
    'weather': weather,
  };

  static ItineraryDay fromJson(Map<String, dynamic> j) => ItineraryDay(
    number: (j['number'] as num?)?.toInt() ?? 1,
    date: DateTime.tryParse(j['date'] as String? ?? '') ?? DateTime.now(),
    title: j['title'] as String? ?? '',
    slots: [
      for (final s in (j['slots'] as List<dynamic>? ?? const []))
        if (s is Map<String, dynamic>) ItinerarySlot.fromJson(s),
    ],
    weather: j['weather'] as String?,
  );
}

enum BudgetCategory { stay, transport, activities, food, buffer }

class BudgetLine {
  const BudgetLine({
    required this.label,
    required this.amountInr,
    required this.category,
    this.isEstimated = true,
  });

  final String label;
  final int amountInr;
  final BudgetCategory category;
  final bool isEstimated;

  Map<String, dynamic> toJson() => {
    'label': label,
    'amountInr': amountInr,
    'category': category.name,
    'isEstimated': isEstimated,
  };

  static BudgetLine fromJson(Map<String, dynamic> j) => BudgetLine(
    label: j['label'] as String? ?? '',
    amountInr: (j['amountInr'] as num?)?.toInt() ?? 0,
    category: enumByName(BudgetCategory.values, j['category'], BudgetCategory.buffer),
    isEstimated: j['isEstimated'] as bool? ?? true,
  );
}

/// Exact costs, plus how they sit against what the traveller said they can spend.
class Budget {
  const Budget({required this.lines, this.budgetMinInr, this.budgetMaxInr});

  final List<BudgetLine> lines;
  final int? budgetMinInr;
  final int? budgetMaxInr;

  int get totalInr => lines.fold(0, (sum, l) => sum + l.amountInr);

  int totalOf(BudgetCategory c) =>
      lines.where((l) => l.category == c).fold(0, (sum, l) => sum + l.amountInr);

  /// Positive when there is room left, negative when over.
  int? get remainingInr => budgetMaxInr == null ? null : budgetMaxInr! - totalInr;

  bool get isWithinBudget => remainingInr == null || remainingInr! >= 0;

  /// True when any line is a guess rather than a real price.
  bool get hasEstimates => lines.any((l) => l.isEstimated);

  Map<String, dynamic> toJson() => {
    'lines': [for (final l in lines) l.toJson()],
    'budgetMinInr': budgetMinInr,
    'budgetMaxInr': budgetMaxInr,
  };

  static Budget fromJson(Map<String, dynamic> j) => Budget(
    lines: [
      for (final l in (j['lines'] as List<dynamic>? ?? const []))
        if (l is Map<String, dynamic>) BudgetLine.fromJson(l),
    ],
    budgetMinInr: (j['budgetMinInr'] as num?)?.toInt(),
    budgetMaxInr: (j['budgetMaxInr'] as num?)?.toInt(),
  );
}

/// Saksham's verdict on one step of the journey, need by need.
class AuditItem {
  const AuditItem({
    required this.name,
    required this.kind,
    required this.checks,
    this.action,
  });

  final String name;
  final SlotKind kind;
  final List<NeedSupport> checks;

  /// What Yatri should do about it (keep / replace / ask).
  final String? action;

  SupportLevel get overall {
    if (checks.isEmpty) return SupportLevel.unknown;
    if (checks.any((c) => c.level == SupportLevel.no)) return SupportLevel.no;
    if (checks.any((c) => c.level == SupportLevel.partial)) return SupportLevel.partial;
    if (checks.any((c) => c.level == SupportLevel.unknown)) return SupportLevel.unknown;
    return SupportLevel.yes;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind.name,
    'checks': [for (final c in checks) c.toJson()],
    'action': action,
  };

  static AuditItem fromJson(Map<String, dynamic> j) => AuditItem(
    name: j['name'] as String? ?? '',
    kind: enumByName(SlotKind.values, j['kind'], SlotKind.visit),
    checks: [
      for (final c in (j['checks'] as List<dynamic>? ?? const []))
        if (c is Map<String, dynamic>) NeedSupport.fromJson(c),
    ],
    action: j['action'] as String?,
  );
}

class AccessibilityAudit {
  const AccessibilityAudit({required this.items, this.actionsRequired = const []});

  final List<AuditItem> items;

  /// Plain-language things still to confirm.
  final List<String> actionsRequired;

  SupportLevel get overall {
    if (items.isEmpty) return SupportLevel.unknown;
    if (items.any((i) => i.overall == SupportLevel.no)) return SupportLevel.no;
    if (items.any((i) => i.overall == SupportLevel.partial || i.overall == SupportLevel.unknown)) {
      return SupportLevel.partial;
    }
    return SupportLevel.yes;
  }

  Map<String, dynamic> toJson() => {
    'items': [for (final i in items) i.toJson()],
    'actionsRequired': actionsRequired,
  };

  static AccessibilityAudit fromJson(Map<String, dynamic> j) => AccessibilityAudit(
    items: [
      for (final i in (j['items'] as List<dynamic>? ?? const []))
        if (i is Map<String, dynamic>) AuditItem.fromJson(i),
    ],
    actionsRequired: [for (final a in (j['actionsRequired'] as List<dynamic>? ?? const [])) '$a'],
  );
}

class GreenReport {
  const GreenReport({
    required this.co2Kg,
    this.co2SavedKg = 0,
    this.score = 0,
    this.tips = const [],
  });

  /// Estimated emissions of the whole plan.
  final double co2Kg;

  /// Versus the most polluting comparable option.
  final double co2SavedKg;

  /// 0..100.
  final int score;
  final List<String> tips;

  Map<String, dynamic> toJson() => {
    'co2Kg': co2Kg,
    'co2SavedKg': co2SavedKg,
    'score': score,
    'tips': tips,
  };

  static GreenReport fromJson(Map<String, dynamic> j) => GreenReport(
    co2Kg: (j['co2Kg'] as num?)?.toDouble() ?? 0,
    co2SavedKg: (j['co2SavedKg'] as num?)?.toDouble() ?? 0,
    score: (j['score'] as num?)?.toInt() ?? 0,
    tips: [for (final t in (j['tips'] as List<dynamic>? ?? const [])) '$t'],
  );
}

/// What the multi-agent planner produces. Immutable, so phase 3 (editing a
/// finished itinerary) can patch it by copying.
class Itinerary {
  const Itinerary({
    required this.id,
    required this.createdAt,
    required this.destination,
    required this.origin,
    required this.start,
    required this.end,
    required this.days,
    required this.budget,
    this.travellerSummary = '',
    this.hotel,
    this.hotelAlternatives = const [],
    this.transportOptions = const [],
    this.chosenTransport,
    this.audit,
    this.green,
    this.sources = const [],
    this.assumptions = const [],
    this.confidence = 0.5,
    this.brief,
  });

  final String id;
  final DateTime createdAt;
  final String destination;
  final String origin;
  final DateTime start;
  final DateTime end;
  final String travellerSummary;
  final HotelOption? hotel;
  final List<HotelOption> hotelAlternatives;

  /// Origin → destination options; [chosenTransport] is the one planned around.
  final List<TransportLeg> transportOptions;
  final TransportLeg? chosenTransport;
  final List<ItineraryDay> days;
  final Budget budget;
  final AccessibilityAudit? audit;
  final GreenReport? green;

  /// Everything Khoji and the tools consulted.
  final List<SourceRef> sources;

  /// Plain-language things the plan assumes or estimated, so nothing is hidden.
  final List<String> assumptions;

  /// 0..1: how much of the plan rests on real data rather than estimates.
  final double confidence;

  /// The brief this plan was made from (kept for phase 3).
  final TripBrief? brief;

  int get dayCount => days.length;

  Itinerary copyWith({
    HotelOption? hotel,
    List<HotelOption>? hotelAlternatives,
    List<TransportLeg>? transportOptions,
    TransportLeg? chosenTransport,
    List<ItineraryDay>? days,
    Budget? budget,
    AccessibilityAudit? audit,
    GreenReport? green,
    List<SourceRef>? sources,
    List<String>? assumptions,
    double? confidence,
  }) => Itinerary(
    id: id,
    createdAt: createdAt,
    destination: destination,
    origin: origin,
    start: start,
    end: end,
    travellerSummary: travellerSummary,
    hotel: hotel ?? this.hotel,
    hotelAlternatives: hotelAlternatives ?? this.hotelAlternatives,
    transportOptions: transportOptions ?? this.transportOptions,
    chosenTransport: chosenTransport ?? this.chosenTransport,
    days: days ?? this.days,
    budget: budget ?? this.budget,
    audit: audit ?? this.audit,
    green: green ?? this.green,
    sources: sources ?? this.sources,
    assumptions: assumptions ?? this.assumptions,
    confidence: confidence ?? this.confidence,
    brief: brief,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'destination': destination,
    'origin': origin,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'travellerSummary': travellerSummary,
    'hotel': hotel?.toJson(),
    'hotelAlternatives': [for (final h in hotelAlternatives) h.toJson()],
    'transportOptions': [for (final t in transportOptions) t.toJson()],
    'chosenTransport': chosenTransport?.toJson(),
    'days': [for (final d in days) d.toJson()],
    'budget': budget.toJson(),
    'audit': audit?.toJson(),
    'green': green?.toJson(),
    'sources': [for (final s in sources) s.toJson()],
    'assumptions': assumptions,
    'confidence': confidence,
    'brief': brief?.toJson(),
  };

  static Itinerary fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? obj(String k) => j[k] is Map<String, dynamic> ? j[k] as Map<String, dynamic> : null;
    List<T> list<T>(String k, T Function(Map<String, dynamic>) f) => [
      for (final e in (j[k] as List<dynamic>? ?? const []))
        if (e is Map<String, dynamic>) f(e),
    ];
    final now = DateTime.now();
    return Itinerary(
      id: j['id'] as String? ?? 'itinerary',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? now,
      destination: j['destination'] as String? ?? '',
      origin: j['origin'] as String? ?? '',
      start: DateTime.tryParse(j['start'] as String? ?? '') ?? now,
      end: DateTime.tryParse(j['end'] as String? ?? '') ?? now,
      travellerSummary: j['travellerSummary'] as String? ?? '',
      hotel: obj('hotel') == null ? null : HotelOption.fromJson(obj('hotel')!),
      hotelAlternatives: list('hotelAlternatives', HotelOption.fromJson),
      transportOptions: list('transportOptions', TransportLeg.fromJson),
      chosenTransport: obj('chosenTransport') == null ? null : TransportLeg.fromJson(obj('chosenTransport')!),
      days: list('days', ItineraryDay.fromJson),
      budget: obj('budget') == null ? const Budget(lines: []) : Budget.fromJson(obj('budget')!),
      audit: obj('audit') == null ? null : AccessibilityAudit.fromJson(obj('audit')!),
      green: obj('green') == null ? null : GreenReport.fromJson(obj('green')!),
      sources: list('sources', SourceRef.fromJson),
      assumptions: [for (final a in (j['assumptions'] as List<dynamic>? ?? const [])) '$a'],
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0.5,
      brief: obj('brief') == null ? null : TripBrief.fromJson(obj('brief')!),
    );
  }

  /// The compatible view the Trips tab, saving and the old detail screen know.
  TripPlan toTripPlan() {
    final mode = chosenTransport?.mode;
    final savedKg = green?.co2SavedKg ?? 0;
    return TripPlan(
      id: id,
      destination: destination,
      title: '$destination — $dayCount-day trip',
      durationDays: dayCount,
      travelDates: dateRangeLabel(start, end),
      travelMode: mode?.label ?? 'Mixed',
      co2SavedKg: double.parse(savedKg.toStringAsFixed(1)),
      pulsePointsEarned: (savedKg * 10).round(),
      isCompleted: false,
      hotelName: hotel?.name ?? 'To be confirmed',
      hotelRating: hotel?.rating ?? 0,
      isStepFreeAccessible: audit != null && audit!.overall != SupportLevel.no,
      totalBudgetInr: budget.totalInr,
      aqiStatus: 'Not available',
      transitCostInr: chosenTransport?.costInr ?? budget.totalOf(BudgetCategory.transport),
      dailyItinerary: [
        for (final d in days)
          TripDaySchedule(
            dayNumber: d.number,
            dayTitle: d.title,
            activities: [
              for (final s in d.slots)
                TripActivity(
                  time: clock12(s.start),
                  title: s.title,
                  description: s.note ?? '',
                  transportType: s.leg?.mode.label ?? '',
                  isAccessible: s.access == null || s.access == SupportLevel.yes || s.access == SupportLevel.partial,
                  co2Grams: s.leg?.co2Grams ?? 0,
                  costInr: s.costInr ?? s.leg?.costInr ?? 0,
                ),
            ],
          ),
      ],
      transitOpt1Name: transportOptions.isNotEmpty ? transportOptions[0].mode.label : null,
      transitOpt1Metrics: transportOptions.isNotEmpty ? _metrics(transportOptions[0]) : null,
      transitOpt2Name: transportOptions.length > 1 ? transportOptions[1].mode.label : null,
      transitOpt2Metrics: transportOptions.length > 1 ? _metrics(transportOptions[1]) : null,
      transitOpt3Name: transportOptions.length > 2 ? transportOptions[2].mode.label : null,
      transitOpt3Metrics: transportOptions.length > 2 ? _metrics(transportOptions[2]) : null,
      source: 'multi_agent',
    );
  }

  static String _metrics(TransportLeg l) =>
      '${rupees(l.costInr)} • ${l.durationMin ~/ 60}h ${l.durationMin % 60}m • '
      '${fixed(l.co2Grams / 1000, 1)} kg CO2';
}
