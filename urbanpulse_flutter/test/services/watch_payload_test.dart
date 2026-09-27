import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/services/watch_payload.dart';

import '../fixtures/demo_itinerary.dart';

void main() {
  final anchor = DateTime(2026, 9, 26);
  final payload = buildWatchPayload(demoItinerary(from: anchor));

  List<Map<String, dynamic>> days() =>
      (payload['d'] as List).cast<Map<String, dynamic>>();

  group('buildWatchPayload', () {
    test('carries the trip the watch has to draw, and nothing else', () {
      expect(payload['v'], watchPayloadVersion);
      expect(payload['t'], 'Rishikesh');
      expect(payload['o'], 'Delhi');
      expect(payload['hn'], 'Ganga View Homestay');
      expect(payload['b'], 22280);
      expect(payload['bx'], 30000);
      expect(payload['co2'], 38);
      expect(days(), hasLength(3));
      // The heavy half of an Itinerary — sources, claims, per-need audits,
      // hotel alternatives, the brief — has no business crossing Bluetooth.
      expect(payload.keys, isNot(contains('sources')));
      expect(payload.keys, isNot(contains('audit')));
    });

    test('renders wall-clock times so the watch does no date arithmetic', () {
      final first = (days().first['sl'] as List).first as Map<String, dynamic>;
      expect(first['hm'], '06:50');
      expect(first['ti'], 'Train to Rishikesh');
      expect(first['k'], 'transit');
      // The epochs are still there, for countdowns only.
      expect(
        DateTime.fromMillisecondsSinceEpoch((first['a'] as int) * 1000),
        DateTime(2026, 9, 26, 6, 50),
      );
      expect(first['z'] as int, greaterThan(first['a'] as int));
    });

    test('keeps a coordinate only where the planner resolved one', () {
      final slots = (days().first['sl'] as List).cast<Map<String, dynamic>>();
      final aarti = slots.firstWhere((s) => s['ti'] == 'Ganga Aarti at Triveni Ghat');
      expect(aarti['la'], 30.1087);
      expect(aarti['ln'], 78.2932);
      // Dinner at the homestay has no location on the slot.
      final dinner = slots.firstWhere((s) => s['ti'] == 'Dinner at the homestay');
      expect(dinner.containsKey('la'), isFalse);
      expect(dinner['c'], 450);
    });

    test('omits every empty field rather than sending a null', () {
      for (final day in days()) {
        for (final slot in (day['sl'] as List).cast<Map<String, dynamic>>()) {
          expect(slot.values, isNot(contains(null)));
          expect(slot.containsKey('no'), slot['no'] != null);
        }
      }
    });

    test('flags travel to the watch, since that is what changes a plan', () {
      final day2 = (days()[1]['sl'] as List).cast<Map<String, dynamic>>();
      final taxi = day2.firstWhere((s) => s['ti'] == 'Shared taxi to Neelkanth');
      expect(taxi['fl'], 'Needs confirmation');
    });

    test('is ASCII only — the watch fonts have no rupee sign or en dash', () {
      final json = jsonEncode(payload);
      expect(json.runes.every((r) => r >= 0x20 && r < 0x7F), isTrue,
          reason: json.runes.where((r) => r < 0x20 || r >= 0x7F).map(String.fromCharCode).join());
      // 31°C, 20% rain -> "31 degC, 20% rain"; the degree sign is transliterated.
      expect(days().first['w'], '31 degC, 20% rain');
      expect(days().first['dt'], 'Sat 26 Sep');
      expect(payload['dr'], '26 Sep - 28 Sep 2026');
    });

    test('fits in the budget a watch response has', () {
      final bytes = utf8.encode(jsonEncode(payload)).length;
      expect(bytes, lessThan(4096), reason: '$bytes bytes for a 3-day plan');
    });

    test('caps a plan no watch could hold', () {
      // 30 days of 40 slots: the caps have to bite, or the server rejects it.
      final long = demoItinerary(from: anchor);
      final fat = buildWatchPayload(
        long.copyWith(days: [for (var i = 0; i < 30; i++) ...long.days]),
      );
      expect((fat['d'] as List), hasLength(14));
      expect(utf8.encode(jsonEncode(fat)).length, lessThan(16 * 1024));
    });
  });
}
