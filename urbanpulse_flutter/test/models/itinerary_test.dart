import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/agents/runtime/report.dart';
import 'package:urbanpulse/models/itinerary/itinerary.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';
import 'package:urbanpulse/models/trip_brief.dart';
import 'package:urbanpulse/models/trip_models.dart';

import '../yatri/test_support.dart';

const munnar = LatLng(10.0889, 77.0595);

HotelOption sampleHotel({Map<AccessibilityNeed, NeedSupport>? access}) => HotelOption(
  id: 'g1-d2',
  name: 'Sunrise Heritage Homestay',
  location: const LatLng(10.09, 77.06),
  address: 'Tea Estate Road, Munnar',
  type: 'Hotel',
  rating: 4.4,
  reviewCount: 812,
  nightlyInr: 3200,
  totalStayInr: 9600,
  priceIsEstimated: false,
  cheapestOta: 'Agoda.com',
  bookingUrl: 'https://agoda.example/h',
  tripAdvisorUrl: 'https://tripadvisor.example/h',
  access: access ??
      {
        AccessibilityNeed.wheelchair: const NeedSupport(
          need: AccessibilityNeed.wheelchair,
          level: SupportLevel.yes,
          detail: 'Step-free entrance and a ground-floor room',
          provenance: Provenance(source: 'OpenStreetMap', url: 'https://osm.example/n/1', confidence: 0.8),
        ),
        AccessibilityNeed.visual: const NeedSupport(need: AccessibilityNeed.visual, level: SupportLevel.unknown),
      },
  amenities: const ['Free parking', 'Breakfast'],
  claims: const [
    Claim(
      text: 'Step-free entrance',
      verdict: Verdict.confirmed,
      sources: [SourceRef(title: 'Guest review', url: 'https://r.example/1', source: 'TripAdvisor')],
      reviewQuotes: ['Ramp at the front, easy for my father’s chair'],
      confidence: 0.7,
    ),
  ],
  distanceToCenterKm: 1.8,
  ecoScore: 0.7,
  labels: const ['Breakfast included'],
  priceBand: 'cheap',
  provenance: const Provenance(source: 'Xotelo', url: 'https://data.xotelo.com', confidence: 0.9),
);

Hotspot sampleSpot(String id, String name, {double score = 0.8}) => Hotspot(
  id: id,
  name: name,
  location: const LatLng(10.2, 77.05),
  kind: HotspotKind.nature,
  why: 'Rolling tea gardens with a gentle boardwalk',
  visitMinutes: 120,
  feeInr: 150,
  openingHours: 'Mo-Su 08:00-17:00',
  isOutdoor: true,
  score: score,
  access: const {
    AccessibilityNeed.wheelchair: NeedSupport(need: AccessibilityNeed.wheelchair, level: SupportLevel.partial, detail: 'Boardwalk is flat; the viewpoint has steps'),
  },
  sources: const [SourceRef(title: 'Wikipedia', url: 'https://en.wikipedia.org/wiki/Munnar', source: 'Wikipedia')],
  provenance: const Provenance(source: 'Geoapify'),
);

TransportLeg sampleLeg(TripTransportMode mode, {int cost = 1800, int minutes = 480, int co2 = 42000}) => TransportLeg(
  id: 'leg-${mode.name}',
  from: 'Pune',
  to: 'Munnar',
  mode: mode,
  distanceKm: 1190,
  durationMin: minutes,
  costInr: cost,
  co2Grams: co2,
  stepFree: mode == TripTransportMode.train,
  note: 'Overnight',
  isEstimated: true,
  fromPoint: const LatLng(18.52, 73.86),
  toPoint: munnar,
);

Itinerary sampleItinerary({int nights = 3}) {
  final start = DateTime(2026, 10, 10, 9);
  return Itinerary(
    id: 'it-1',
    createdAt: DateTime(2026, 10, 2, 10),
    destination: 'Munnar',
    origin: 'Pune',
    start: start,
    end: start.add(Duration(days: nights)),
    travellerSummary: '2 adults, 2 children',
    hotel: sampleHotel(),
    hotelAlternatives: [sampleHotel().copyWith(nightlyInr: 4100)],
    transportOptions: [sampleLeg(TripTransportMode.train), sampleLeg(TripTransportMode.flight, cost: 9800, minutes: 190, co2: 250000)],
    chosenTransport: sampleLeg(TripTransportMode.train),
    days: [
      for (var d = 0; d <= nights; d++)
        ItineraryDay(
          number: d + 1,
          date: start.add(Duration(days: d)),
          title: 'Day ${d + 1}',
          weather: '28°C, 30% rain',
          slots: [
            ItinerarySlot(
              kind: SlotKind.visit,
              start: start.add(Duration(days: d, hours: 1)),
              end: start.add(Duration(days: d, hours: 3)),
              title: 'Tea Museum',
              location: const LatLng(10.2, 77.05),
              refId: 'sp1',
              costInr: 300,
              access: SupportLevel.partial,
              flags: const ['Confirm ramp'],
            ),
            ItinerarySlot(
              kind: SlotKind.transit,
              start: start.add(Duration(days: d, hours: 3)),
              end: start.add(Duration(days: d, hours: 4)),
              title: 'Cab to viewpoint',
              leg: sampleLeg(TripTransportMode.carTaxi, cost: 450, minutes: 60, co2: 3000),
            ),
          ],
        ),
    ],
    budget: const Budget(
      lines: [
        BudgetLine(label: 'Hotel, 3 nights', amountInr: 9600, category: BudgetCategory.stay, isEstimated: false),
        BudgetLine(label: 'Train, return', amountInr: 7200, category: BudgetCategory.transport),
        BudgetLine(label: 'Entry fees', amountInr: 1200, category: BudgetCategory.activities),
        BudgetLine(label: 'Food', amountInr: 6000, category: BudgetCategory.food),
      ],
      budgetMinInr: 20000,
      budgetMaxInr: 30000,
    ),
    audit: AccessibilityAudit(
      items: [
        AuditItem(name: 'Sunrise Heritage Homestay', kind: SlotKind.stay, checks: [sampleHotel().access.values.first]),
        AuditItem(name: 'Tea Museum', kind: SlotKind.visit, checks: sampleSpot('sp1', 'Tea Museum').access.values.toList(), action: 'Ask the user to confirm the viewpoint steps'),
      ],
      actionsRequired: const ['Confirm the museum ramp'],
    ),
    green: const GreenReport(co2Kg: 128.5, co2SavedKg: 96.25, score: 82, tips: ['Train instead of flight saves 96 kg CO2']),
    sources: const [SourceRef(title: 'Xotelo', url: 'https://data.xotelo.com', source: 'Xotelo')],
    assumptions: const ['Food is estimated at ₹500 per person per day'],
    confidence: 0.72,
    brief: completeBrief(),
  );
}

void main() {
  group('itinerary JSON', () {
    test('survives a full round trip through real JSON text', () {
      final original = sampleItinerary();
      final text = jsonEncode(original.toJson());
      final copy = Itinerary.fromJson(jsonDecode(text) as Map<String, dynamic>);
      expect(jsonEncode(copy.toJson()), text);
    });

    test('keeps the details agents rely on', () {
      final copy = Itinerary.fromJson(jsonDecode(jsonEncode(sampleItinerary().toJson())) as Map<String, dynamic>);
      final h = copy.hotel!;
      expect(h.location, const LatLng(10.09, 77.06));
      expect(h.access[AccessibilityNeed.wheelchair]!.level, SupportLevel.yes);
      expect(h.access[AccessibilityNeed.wheelchair]!.provenance.source, 'OpenStreetMap');
      expect(h.claims.single.verdict, Verdict.confirmed);
      expect(h.claims.single.reviewQuotes.single, contains('Ramp'));
      expect(copy.chosenTransport!.mode, TripTransportMode.train);
      expect(copy.days.first.slots.last.leg!.mode, TripTransportMode.carTaxi);
      expect(copy.brief!.destination, 'Munnar');
      expect(copy.audit!.items.last.action, contains('viewpoint'));
    });

    test('a damaged or empty document still loads', () {
      final it = Itinerary.fromJson(const {});
      expect(it.days, isEmpty);
      expect(it.budget.totalInr, 0);
      expect(it.hotel, isNull);
      // Unknown enum names fall back instead of throwing.
      final leg = TransportLeg.fromJson(const {'mode': 'teleporter', 'costInr': 5});
      expect(leg.mode, TripTransportMode.carTaxi);
      final s = NeedSupport.fromJson(const {'need': 'nonsense', 'level': 'maybe'});
      expect((s.need, s.level), (AccessibilityNeed.none, SupportLevel.unknown));
    });
  });

  group('budget', () {
    test('totals, categories and headroom', () {
      final b = sampleItinerary().budget;
      expect(b.totalInr, 24000);
      expect(b.totalOf(BudgetCategory.stay), 9600);
      expect(b.remainingInr, 6000);
      expect(b.isWithinBudget, isTrue);
      expect(b.hasEstimates, isTrue);
    });

    test('over budget is reported, and no budget means no limit', () {
      const over = Budget(lines: [BudgetLine(label: 'x', amountInr: 50000, category: BudgetCategory.stay)], budgetMaxInr: 40000);
      expect(over.remainingInr, -10000);
      expect(over.isWithinBudget, isFalse);
      const free = Budget(lines: [BudgetLine(label: 'x', amountInr: 50000, category: BudgetCategory.stay)]);
      expect(free.remainingInr, isNull);
      expect(free.isWithinBudget, isTrue);
    });
  });

  group('accessibility summary', () {
    test('an item is only as good as its weakest check', () {
      NeedSupport s(SupportLevel l) => NeedSupport(need: AccessibilityNeed.wheelchair, level: l);
      expect(AuditItem(name: 'a', kind: SlotKind.visit, checks: [s(SupportLevel.yes), s(SupportLevel.yes)]).overall, SupportLevel.yes);
      expect(AuditItem(name: 'a', kind: SlotKind.visit, checks: [s(SupportLevel.yes), s(SupportLevel.partial)]).overall, SupportLevel.partial);
      expect(AuditItem(name: 'a', kind: SlotKind.visit, checks: [s(SupportLevel.yes), s(SupportLevel.unknown)]).overall, SupportLevel.unknown);
      expect(AuditItem(name: 'a', kind: SlotKind.visit, checks: [s(SupportLevel.partial), s(SupportLevel.no)]).overall, SupportLevel.no);
      expect(const AuditItem(name: 'a', kind: SlotKind.visit, checks: []).overall, SupportLevel.unknown);
    });

    test('the audit flags a failing step and downgrades a partial one', () {
      NeedSupport s(SupportLevel l) => NeedSupport(need: AccessibilityNeed.visual, level: l);
      AuditItem item(SupportLevel l) => AuditItem(name: 'x', kind: SlotKind.visit, checks: [s(l)]);
      expect(AccessibilityAudit(items: [item(SupportLevel.yes), item(SupportLevel.yes)]).overall, SupportLevel.yes);
      expect(AccessibilityAudit(items: [item(SupportLevel.yes), item(SupportLevel.partial)]).overall, SupportLevel.partial);
      expect(AccessibilityAudit(items: [item(SupportLevel.yes), item(SupportLevel.no)]).overall, SupportLevel.no);
      expect(const AccessibilityAudit(items: []).overall, SupportLevel.unknown);
    });

    test('a hotel meets the group’s needs only if each is at least partly supported', () {
      final h = sampleHotel();
      expect(h.meets({AccessibilityNeed.wheelchair}), isTrue);
      expect(h.meets({AccessibilityNeed.wheelchair, AccessibilityNeed.visual}), isFalse, reason: 'visual is unconfirmed');
      expect(h.meets({AccessibilityNeed.hearing}), isFalse, reason: 'nothing known about hearing');
      expect(h.meets({AccessibilityNeed.none}), isTrue);
      expect(h.meets(const {}), isTrue);
    });
  });

  group('TripPlan compatibility view', () {
    test('maps the itinerary onto what the Trips tab and saving expect', () {
      final plan = sampleItinerary().toTripPlan();
      expect(plan.destination, 'Munnar');
      expect(plan.title, 'Munnar — 4-day trip');
      expect(plan.durationDays, 4);
      expect(plan.travelDates, '10 Oct – 13 Oct 2026');
      expect(plan.travelMode, 'Train');
      expect(plan.hotelName, 'Sunrise Heritage Homestay');
      expect(plan.hotelRating, 4.4);
      expect(plan.totalBudgetInr, 24000);
      expect(plan.transitCostInr, 1800);
      expect(plan.co2SavedKg, 96.3);
      expect(plan.isStepFreeAccessible, isTrue);
      expect(plan.isAiGenerated, isTrue);
      expect(plan.dailyItinerary, hasLength(4));
      final first = plan.dailyItinerary.first.activities;
      expect(first.first.title, 'Tea Museum');
      expect(first.first.costInr, 300);
      expect(first.last.transportType, 'Car / taxi');
      expect(plan.transitOpt1Name, 'Train');
      expect(plan.transitOpt2Name, 'Flight');
      expect(plan.transitOpt2Metrics, contains('kg CO2'));
      expect(plan.transitOpt3Name, isNull);
    });

    test('the old plan format still round-trips through its own JSON', () {
      final plan = sampleItinerary().toTripPlan();
      final copy = TripPlan.fromJson(jsonDecode(jsonEncode(plan.toJson())) as Map<String, dynamic>);
      expect(copy.title, plan.title);
      expect(copy.source, 'multi_agent');
    });

    test('an itinerary with nothing chosen yet still converts', () {
      final bare = Itinerary(
        id: 'x',
        createdAt: DateTime(2026),
        destination: 'Goa',
        origin: 'Pune',
        start: DateTime(2026, 10, 10),
        end: DateTime(2026, 10, 11),
        days: const [],
        budget: const Budget(lines: []),
      );
      final plan = bare.toTripPlan();
      expect(plan.hotelName, 'To be confirmed');
      expect(plan.isStepFreeAccessible, isFalse, reason: 'no audit yet, so nothing is claimed');
    });
  });
}
