import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/runtime/report.dart';
import 'package:urbanpulse/domain/access/access_rules.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';
import 'package:urbanpulse/models/trip_brief.dart';

const osm = Provenance(source: 'OpenStreetMap', confidence: 0.8);
const listing = Provenance(source: 'TripAdvisor', confidence: 0.6);
const guess = Provenance.aiEstimate;

SupportLevel level(Map<AccessibilityNeed, NeedSupport> m, AccessibilityNeed n) =>
    m[n]?.level ?? SupportLevel.unknown;

void main() {
  group('OSM tags', () {
    const wc = {AccessibilityNeed.wheelchair};

    test('wheelchair values map to support levels', () {
      for (final (tag, expected) in [
        ('yes', SupportLevel.yes),
        ('designated', SupportLevel.yes),
        ('limited', SupportLevel.partial),
        ('no', SupportLevel.no),
        ('YES', SupportLevel.yes),
        ('', SupportLevel.unknown),
        ('banana', SupportLevel.unknown),
      ]) {
        final m = AccessRules.fromOsmTags({if (tag.isNotEmpty) 'wheelchair': tag}, wc, provenance: osm);
        expect(level(m, AccessibilityNeed.wheelchair), expected, reason: 'wheelchair=$tag');
      }
    });

    test('details mention the accessible toilet and the lift', () {
      final m = AccessRules.fromOsmTags({'wheelchair': 'yes', 'toilets:wheelchair': 'yes', 'elevator': 'yes'}, wc, provenance: osm);
      final d = m[AccessibilityNeed.wheelchair]!.detail;
      expect(d, contains('accessible toilet'));
      expect(d, contains('lift'));
      expect(m[AccessibilityNeed.wheelchair]!.provenance.source, 'OpenStreetMap');
    });

    test('a lift alone is only partial for wheelchairs', () {
      final m = AccessRules.fromOsmTags({'elevator': 'yes'}, wc, provenance: osm);
      expect(level(m, AccessibilityNeed.wheelchair), SupportLevel.partial);
    });

    test('mobility and elderly needs follow the wheelchair tag', () {
      const needs = {AccessibilityNeed.limitedMobility, AccessibilityNeed.elderlyCare};
      expect(level(AccessRules.fromOsmTags({'wheelchair': 'yes'}, needs, provenance: osm), AccessibilityNeed.limitedMobility), SupportLevel.yes);
      expect(level(AccessRules.fromOsmTags({'wheelchair': 'yes'}, needs, provenance: osm), AccessibilityNeed.elderlyCare), SupportLevel.yes);
      expect(level(AccessRules.fromOsmTags({'wheelchair': 'no'}, needs, provenance: osm), AccessibilityNeed.elderlyCare), SupportLevel.no);
      expect(level(AccessRules.fromOsmTags({'elevator': 'yes'}, needs, provenance: osm), AccessibilityNeed.elderlyCare), SupportLevel.partial);
      expect(level(AccessRules.fromOsmTags(const {}, needs, provenance: osm), AccessibilityNeed.limitedMobility), SupportLevel.unknown);
    });

    test('visual, hearing and service-animal tags', () {
      const needs = {AccessibilityNeed.visual, AccessibilityNeed.hearing, AccessibilityNeed.serviceAnimal};
      final m = AccessRules.fromOsmTags({'tactile_writing:braille': 'yes', 'hearing_loop': 'yes', 'dog': 'leashed'}, needs, provenance: osm);
      expect(level(m, AccessibilityNeed.visual), SupportLevel.yes);
      expect(level(m, AccessibilityNeed.hearing), SupportLevel.yes);
      expect(level(m, AccessibilityNeed.serviceAnimal), SupportLevel.yes);
      expect(level(AccessRules.fromOsmTags({'tactile_paving': 'yes'}, needs, provenance: osm), AccessibilityNeed.visual), SupportLevel.partial);
      // "No dogs" does not mean no service animals.
      final no = AccessRules.fromOsmTags({'dog': 'no'}, needs, provenance: osm);
      expect(level(no, AccessibilityNeed.serviceAnimal), SupportLevel.partial);
      expect(no[AccessibilityNeed.serviceAnimal]!.detail, contains('service animals usually still are'));
    });

    test('needs OSM cannot speak to stay unknown rather than guessed', () {
      final m = AccessRules.fromOsmTags({'wheelchair': 'yes'}, {AccessibilityNeed.cognitiveSensory, AccessibilityNeed.otherSpecial, AccessibilityNeed.hearing}, provenance: osm);
      expect(m.values.every((s) => s.level == SupportLevel.unknown), isTrue);
    });

    test('only the requested needs are returned, and “none” is ignored', () {
      final m = AccessRules.fromOsmTags({'wheelchair': 'yes'}, {AccessibilityNeed.wheelchair, AccessibilityNeed.none}, provenance: osm);
      expect(m.keys, [AccessibilityNeed.wheelchair]);
      expect(AccessRules.fromOsmTags({'wheelchair': 'yes'}, const {AccessibilityNeed.none}, provenance: osm), isEmpty);
    });
  });

  group('listing text', () {
    const wc = {AccessibilityNeed.wheelchair};

    test('positive phrases', () {
      for (final t in [
        'Wheelchair accessible rooms and a roll-in shower',
        'Step-free access to all floors',
        'We offer an accessible bathroom.',
        'Barrier free entrance',
      ]) {
        final m = AccessRules.fromText(t, wc, provenance: listing);
        expect(level(m, AccessibilityNeed.wheelchair), SupportLevel.yes, reason: t);
        expect(m[AccessibilityNeed.wheelchair]!.detail, contains('listing mentions'));
      }
    });

    test('negations win over positives: the dangerous case', () {
      for (final t in [
        'A charming heritage stay. Not wheelchair accessible.',
        'Wheelchair accessible lobby, but no elevator to the rooms',
        'The property is not suitable for wheelchair users',
        'Stairs only to reach the rooms. Wheelchair accessible bar.',
      ]) {
        final m = AccessRules.fromText(t, wc, provenance: listing);
        expect(level(m, AccessibilityNeed.wheelchair), SupportLevel.no, reason: t);
      }
    });

    test('a negation must be a word of its own and must not cross a comma', () {
      for (final t in [
        'Ground floor rooms, wheelchair accessible bathroom',
        'Nonsmoking rooms; wheelchair accessible',
        'No pets, wheelchair accessible rooms available',
        'Notable heritage stay with wheelchair accessible rooms',
      ]) {
        final m = AccessRules.fromText(t, wc, provenance: listing);
        expect(level(m, AccessibilityNeed.wheelchair), SupportLevel.yes, reason: t);
      }
    });

    test('a lift or ramp is only partial evidence', () {
      final m = AccessRules.fromText('Rooms on the ground floor, lift to upper levels', wc, provenance: listing);
      expect(level(m, AccessibilityNeed.wheelchair), SupportLevel.partial);
      expect(m[AccessibilityNeed.wheelchair]!.detail, contains('not confirmed'));
    });

    test('silence is unknown, not a guess', () {
      final m = AccessRules.fromText('Free parking, pool, bar/lounge, business center', wc, provenance: listing);
      expect(m, isEmpty);
    });

    test('other needs have their own phrases', () {
      const all = {AccessibilityNeed.visual, AccessibilityNeed.hearing, AccessibilityNeed.serviceAnimal, AccessibilityNeed.cognitiveSensory, AccessibilityNeed.elderlyCare};
      final m = AccessRules.fromText(
        'Braille menus. Visual alarms in every room. Service dogs are welcome. Sensory-friendly quiet rooms. Elevator and 24-hour front desk.',
        all,
        provenance: listing,
      );
      expect(level(m, AccessibilityNeed.visual), SupportLevel.partial);
      expect(level(m, AccessibilityNeed.hearing), SupportLevel.partial);
      expect(level(m, AccessibilityNeed.serviceAnimal), SupportLevel.yes);
      expect(level(m, AccessibilityNeed.cognitiveSensory), SupportLevel.partial);
      expect(level(m, AccessibilityNeed.elderlyCare), SupportLevel.partial);
    });

    test('no pets is not the same as no service animals', () {
      final m = AccessRules.fromText('Sorry, no pets.', {AccessibilityNeed.serviceAnimal}, provenance: listing);
      expect(level(m, AccessibilityNeed.serviceAnimal), SupportLevel.partial);
    });
  });

  group('merging evidence', () {
    NeedSupport s(SupportLevel l, Provenance p, [String d = '']) =>
        NeedSupport(need: AccessibilityNeed.wheelchair, level: l, provenance: p, detail: d);

    test('unknown yields to anything known', () {
      final known = s(SupportLevel.yes, osm, 'ok');
      expect(AccessRules.merge(s(SupportLevel.unknown, osm), known), same(known));
      expect(AccessRules.merge(known, s(SupportLevel.unknown, guess)), same(known));
    });

    test('a real source beats an AI estimate, whichever way round', () {
      final real = s(SupportLevel.no, listing, 'listing says no');
      final est = s(SupportLevel.yes, guess, 'guess');
      expect(AccessRules.merge(real, est).level, SupportLevel.no);
      expect(AccessRules.merge(est, real).level, SupportLevel.no);
    });

    test('two real sources that disagree become “partly”, with both named', () {
      final m = AccessRules.merge(s(SupportLevel.yes, osm), s(SupportLevel.no, listing));
      expect(m.level, SupportLevel.partial);
      expect(m.detail, contains('OpenStreetMap'));
      expect(m.detail, contains('TripAdvisor'));
      expect(m.detail, contains('Confirm before booking'));
      expect(m.provenance.confidence, 0.6, reason: 'as sure as the less sure source');
    });

    test('a real “no” against a real “partly” is also a disagreement, not a quiet win for the optimist', () {
      final m = AccessRules.merge(s(SupportLevel.partial, osm, 'OSM: limited'), s(SupportLevel.no, listing, 'listing: not accessible'));
      expect(m.level, SupportLevel.partial);
      expect(m.detail, contains('Sources disagree'));
      expect(AccessRules.merge(s(SupportLevel.no, listing), s(SupportLevel.partial, osm)).detail, contains('Sources disagree'));
    });

    test('agreeing sources keep the more trusted one', () {
      final a = s(SupportLevel.yes, osm, 'osm');
      final b = s(SupportLevel.yes, listing, 'listing');
      expect(AccessRules.merge(a, b).detail, 'osm');
      expect(AccessRules.merge(b, a).detail, 'osm');
    });

    test('mergeAll works need by need', () {
      final merged = AccessRules.mergeAll([
        {
          AccessibilityNeed.wheelchair: s(SupportLevel.unknown, osm),
          AccessibilityNeed.visual: NeedSupport(need: AccessibilityNeed.visual, level: SupportLevel.partial, provenance: osm),
        },
        {AccessibilityNeed.wheelchair: s(SupportLevel.yes, listing)},
      ]);
      expect(level(merged, AccessibilityNeed.wheelchair), SupportLevel.yes);
      expect(level(merged, AccessibilityNeed.visual), SupportLevel.partial);
    });
  });
}
