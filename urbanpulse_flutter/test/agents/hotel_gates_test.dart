import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/atithi/hotel_finder.dart';
import 'package:urbanpulse/agents/hisab/hotel_budget.dart';
import 'package:urbanpulse/agents/runtime/agent_kind.dart';
import 'package:urbanpulse/agents/runtime/report.dart';
import 'package:urbanpulse/agents/yatri/hotel_gates.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';
import 'package:urbanpulse/models/trip_brief.dart';

import '../yatri/test_support.dart';
import 'hotel_world.dart';

NeedSupport sup(AccessibilityNeed n, SupportLevel l) =>
    NeedSupport(need: n, level: l, provenance: const Provenance(source: 'OpenStreetMap', confidence: 0.8));

HotelOption hotel(String name, int? nightly, {Map<AccessibilityNeed, SupportLevel> access = const {}, bool estimated = false}) => HotelOption(
  id: name,
  name: name,
  nightlyInr: nightly,
  priceIsEstimated: estimated,
  access: {for (final e in access.entries) e.key: sup(e.key, e.value)},
);

HotelSearchResult result(List<HotelOption> options, HotelQuery q) => HotelSearchResult(query: q, options: options);

const wc = AccessibilityNeed.wheelchair;

void main() {
  group('Atithi gates', () {
    test('no hotels at all is a blocking issue that can widen the search or skip', () {
      final issues = HotelGates.checkAtithi(result(const [], munnarQuery()));
      expect(issues, hasLength(1));
      final i = issues.single;
      expect(i.agent, AgentKind.atithi);
      expect(i.severity, IssueSeverity.blocking);
      expect(i.options.map((o) => o.id), ['wider', 'skip']);
      expect(i.options.first.recommended, isTrue);
      expect(i.why, isNotEmpty);
    });

    test('a search that is already wide offers only to carry on without one', () {
      final i = HotelGates.checkAtithi(result(const [], munnarQuery(radiusKm: 30))).single;
      expect(i.options.map((o) => o.id), ['skip']);
      expect(i.options.single.recommended, isTrue);
    });

    test('no needs, no access issue', () {
      expect(HotelGates.checkAtithi(result([hotel('a', 2000)], munnarQuery())), isEmpty);
    });

    test('one confirmed hotel is enough, and “partly” counts', () {
      final q = munnarQuery(needs: {wc});
      expect(HotelGates.checkAtithi(result([hotel('a', 2000, access: {wc: SupportLevel.yes})], q)), isEmpty);
      expect(HotelGates.checkAtithi(result([hotel('a', 2000, access: {wc: SupportLevel.partial})], q)), isEmpty);
    });

    test('unconfirmed hotels are not ruled out: the traveller may accept them', () {
      final q = munnarQuery(needs: {wc});
      final i = HotelGates.checkAtithi(result([hotel('a', 2000), hotel('b', 2500, access: {wc: SupportLevel.no})], q)).single;
      expect(i.id, startsWith('hotels.access@'));
      expect(i.message, contains('none is confirmed'));
      expect(i.options.map((o) => o.id), ['accept', 'wider']);
      expect(i.options.first.recommended, isTrue);
    });

    test('only hotels known to fail: accepting is possible but widening is recommended', () {
      final q = munnarQuery(needs: {wc});
      final i = HotelGates.checkAtithi(result([hotel('a', 2000, access: {wc: SupportLevel.no})], q)).single;
      expect(i.message, contains('suits wheelchair access'));
      expect(i.options.map((o) => o.id), ['wider', 'accept']);
      expect(i.options.firstWhere((o) => o.id == 'wider').recommended, isTrue);
      expect(i.options.firstWhere((o) => o.id == 'accept').recommended, isFalse);
    });

    test('every need must be met by the same hotel', () {
      final q = munnarQuery(needs: {wc, AccessibilityNeed.hearing});
      final split = result([
        hotel('a', 2000, access: {wc: SupportLevel.yes, AccessibilityNeed.hearing: SupportLevel.unknown}),
        hotel('b', 2000, access: {wc: SupportLevel.unknown, AccessibilityNeed.hearing: SupportLevel.yes}),
      ], q);
      expect(HotelGates.checkAtithi(split), hasLength(1));
    });

    test('“none” is not a need', () {
      final q = munnarQuery(needs: {AccessibilityNeed.none});
      expect(HotelGates.checkAtithi(result([hotel('a', 2000)], q)), isEmpty);
    });
  });

  group('Hisab gates', () {
    test('within the cap is fine, no cap is fine', () {
      expect(HotelGates.checkHisab(result([hotel('a', 900)], munnarQuery(cap: 1000))), isEmpty);
      expect(HotelGates.checkHisab(result([hotel('a', 9000)], munnarQuery())), isEmpty);
      expect(HotelGates.checkHisab(result(const [], munnarQuery(cap: 1000))), isEmpty);
    });

    test('over the cap offers to raise it to the cheapest price rounded up', () {
      final i = HotelGates.checkHisab(result([hotel('a', 1420), hotel('b', 2400)], munnarQuery(cap: 1000))).single;
      expect(i.agent, AgentKind.hisab);
      expect(i.id, 'hotels.budget@1000');
      final raise = i.options.firstWhere((o) => o.id == 'raise');
      expect(raise.effect['nightlyCapInr'], 1500);
      expect(raise.recommended, isTrue);
      expect(i.options.firstWhere((o) => o.id == 'raise_more').effect['nightlyCapInr'], greaterThan(1500));
      expect(i.options.map((o) => o.id), containsAll(['wider', 'accept']));
      expect(i.message, contains('₹1420'));
    });

    test('the price to beat is the cheapest SUITABLE one', () {
      // The ₹800 hotel is known not to be accessible, so it cannot rescue the budget.
      final q = munnarQuery(needs: {wc}, cap: 1000);
      final r = result([
        hotel('cheap-but-stairs', 800, access: {wc: SupportLevel.no}),
        hotel('ramp', 2600, access: {wc: SupportLevel.yes}),
      ], q);
      final i = HotelGates.checkHisab(r).single;
      expect(i.message, contains('₹2600'));
      expect(i.message, contains('wheelchair access'));
    });

    test('estimates are called estimates', () {
      final i = HotelGates.checkHisab(result([hotel('a', 3000, estimated: true)], munnarQuery(cap: 1000))).single;
      expect(i.message, contains('(estimated)'));
    });

    test('a hotel without a price does not trigger the budget gate', () {
      expect(HotelGates.checkHisab(result([hotel('a', null)], munnarQuery(cap: 1000))), isEmpty);
    });

    test('the same problem gets a new id when the cap changes, so it is not asked twice but can come back', () {
      final r1 = HotelGates.checkHisab(result([hotel('a', 3000)], munnarQuery(cap: 1000))).single;
      final r2 = HotelGates.checkHisab(result([hotel('a', 3000)], munnarQuery(cap: 1500))).single;
      expect(r1.id, isNot(r2.id));
    });
  });

  group('applying a choice', () {
    final q = munnarQuery(cap: 1000);

    test('raising the budget changes only the cap', () {
      final n = HotelGates.apply(q, const IssueOption(id: 'raise', label: 'x', effect: {'nightlyCapInr': 1500}))!;
      expect((n.nightlyCapInr, n.radiusKm), (1500, 10.0));
    });

    test('widening changes only the radius', () {
      final n = HotelGates.apply(q, const IssueOption(id: 'wider', label: 'x', effect: {'radiusKm': 30.0}))!;
      expect((n.nightlyCapInr, n.radiusKm), (1000, 30.0));
    });

    test('accepting or skipping ends the search', () {
      expect(HotelGates.apply(q, const IssueOption(id: 'accept', label: 'x', effect: {'action': 'accept'})), isNull);
      expect(HotelGates.apply(q, const IssueOption(id: 'skip', label: 'x', effect: {'action': 'skip'})), isNull);
      expect(HotelGates.apply(q, const IssueOption(id: '?', label: 'x')), isNull, reason: 'an unknown effect changes nothing');
    });
  });

  group('Hisab’s hotel budget', () {
    test('about 40% of the trip goes on the stay, per room and night', () {
      // 40,000 over 3 nights: 4 travellers (2 adults + 2 children) need one room.
      expect(HotelBudget.nightlyCapInr(completeBrief()), (40000 * 0.4 / 3).round());
    });

    test('more rooms means less per room', () {
      final b = completeBrief().copyWith(adults: 4, children: 0, travellerCount: 4, childAges: const []);
      expect(HotelBudget.roomsFor(b), 2);
      expect(HotelBudget.nightlyCapInr(b), (40000 * 0.4 / 3 / 2).round());
    });

    test('no budget means no cap, and silly budgets are clamped', () {
      expect(HotelBudget.nightlyCapInr(TripBrief.empty(testNow)), isNull);
      expect(HotelBudget.nightlyCapInr(completeBrief().copyWith(budgetMaxInr: 1)), 300);
      expect(HotelBudget.nightlyCapInr(completeBrief().copyWith(budgetMaxInr: 2000000000)), 500000);
    });

    test('a same-day trip is one night, and a group with no adults still gets a room', () {
      final b = completeBrief().copyWith(start: DateTime(2026, 10, 10, 8), end: DateTime(2026, 10, 10, 20));
      expect(HotelBudget.stayNights(b), 1);
      final kids = completeBrief().copyWith(adults: 0, seniors: 0, children: 3, travellerCount: 3);
      expect(HotelBudget.roomsFor(kids), 1);
      expect(HotelBudget.adultsFor(kids), 1);
    });

    test('a brief with only a head count still works', () {
      final b = TripBrief(id: 'x', createdAt: testNow, travellerCount: 5, start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 3));
      expect(HotelBudget.roomsFor(b), 3);
      expect(HotelBudget.adultsFor(b), 5);
    });
  });
}
