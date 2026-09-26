import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/agents/atithi/hotel_candidate.dart';
import 'package:urbanpulse/agents/atithi/hotel_finder.dart';
import 'package:urbanpulse/agents/runtime/report.dart';
import 'package:urbanpulse/models/itinerary/itinerary_parts.dart';
import 'package:urbanpulse/models/trip_brief.dart';

import 'fakes.dart';
import 'hotel_world.dart';

HotelCandidate cand(String name, {LatLng? at, String source = 'Xotelo', String? key, double? rating, int? nightly}) =>
    HotelCandidate(name: name, source: source, location: at, xoteloKey: key, rating: rating, nightlyInr: nightly);

HotelOption byName(HotelSearchResult r, String name) => r.options.firstWhere((o) => o.name == name, orElse: () => fail('no option named $name in ${r.options.map((o) => o.name)}'));

void main() {
  group('matching and merging', () {
    test('names are compared on their distinctive words', () {
      expect(HotelCandidates.similarity('Sunrise Heritage Homestay', 'Sunrise Heritage Home Stay'), greaterThan(0.5));
      expect(HotelCandidates.similarity('Hotel Sunrise', 'The Sunrise Hotel & Resort'), 1.0);
      expect(HotelCandidates.similarity('Tea Valley Resort', 'Misty Hills Cottages'), 0.0);
      expect(HotelCandidates.similarity('', 'x'), 0.0);
    });

    test('the same hotel from two sources is one hotel', () {
      final a = cand('Sunrise Heritage Homestay', at: const LatLng(10.09, 77.06), key: 'g1-d1');
      final b = cand('Sunrise Heritage Home Stay', at: const LatLng(10.0902, 77.0603), source: 'Geoapify');
      expect(HotelCandidates.sameHotel(a, b), isTrue);
      expect(HotelCandidates.merge([a, b]), hasLength(1));
    });

    test('different hotels stay different, even nearby or with a shared word', () {
      final a = cand('Tea Valley Resort', at: const LatLng(10.09, 77.06));
      final b = cand('Tea Garden Cottage', at: const LatLng(10.0901, 77.0601), source: 'Geoapify');
      expect(HotelCandidates.sameHotel(a, b), isFalse);
      // Same name far apart (two branches) is not merged.
      final c = cand('Sunrise Palace', at: const LatLng(10.09, 77.06));
      final d = cand('Sunrise Palace', at: const LatLng(10.5, 77.4), source: 'Geoapify');
      expect(HotelCandidates.normalize(c.name), HotelCandidates.normalize(d.name));
      expect(HotelCandidates.sameHotel(c, d), isTrue, reason: 'identical names always match; branches are rare and distinct ids would be needed');
    });

    test('merging keeps the best of each field and the union of evidence', () {
      final x = HotelCandidate(name: 'Sunrise Heritage Homestay', source: 'Xotelo', xoteloKey: 'g1-d1', rating: 4.6, reviewCount: 800, nightlyInr: 3000, location: const LatLng(10.09, 77.06));
      final g = HotelCandidate(
        name: 'Sunrise Heritage Home Stay',
        source: 'Geoapify',
        location: const LatLng(10.0902, 77.0603),
        address: 'Tea Estate Rd',
        phone: '+91 1',
        geoapifyId: 'gp1',
        tags: {'wheelchair': 'yes'},
        amenities: ['Parking'],
      );
      final merged = HotelCandidates.merge([x, g]).single;
      expect(merged.xoteloKey, 'g1-d1');
      expect(merged.name, 'Sunrise Heritage Homestay', reason: 'the Xotelo name wins');
      expect(merged.address, 'Tea Estate Rd');
      expect(merged.phone, '+91 1');
      expect(merged.tags['wheelchair'], 'yes');
      expect(merged.amenities, ['Parking']);
      expect(merged.geoapifyId, 'gp1');
      expect(merged.rating, 4.6);
      expect(merged.id, 'g1-d1');
    });

    test('a live price is never replaced by an estimate', () {
      final live = cand('A', nightly: 2500)..priceIsEstimated = false;
      final guess = cand('A', nightly: 4000, source: 'web search');
      live.absorb(guess);
      expect((live.nightlyInr, live.priceIsEstimated), (2500, false));
      final est = cand('B', nightly: 4000);
      est.absorb(cand('B', nightly: 3100)..priceIsEstimated = false);
      expect((est.nightlyInr, est.priceIsEstimated), (3100, false));
    });

    test('evidence for the same need is combined, not overwritten', () {
      final a = cand('A')..access[AccessibilityNeed.wheelchair] = const NeedSupport(need: AccessibilityNeed.wheelchair, level: SupportLevel.yes, provenance: Provenance(source: 'OSM', confidence: 0.8));
      final b = cand('A')..access[AccessibilityNeed.wheelchair] = const NeedSupport(need: AccessibilityNeed.wheelchair, level: SupportLevel.no, provenance: Provenance(source: 'Listing', confidence: 0.6));
      a.absorb(b);
      expect(a.access[AccessibilityNeed.wheelchair]!.level, SupportLevel.partial);
      expect(a.access[AccessibilityNeed.wheelchair]!.detail, contains('Sources disagree'));
    });
  });

  group('ranking', () {
    HotelCandidate withAccess(String n, SupportLevel l, {int? price, double? rating = 4.0}) => cand(n, rating: rating, nightly: price)
      ..access[AccessibilityNeed.wheelchair] = NeedSupport(need: AccessibilityNeed.wheelchair, level: l, provenance: const Provenance(source: 'x'));

    double fit(HotelCandidate c, {Set<AccessibilityNeed> needs = const {AccessibilityNeed.wheelchair}, int? cap}) =>
        HotelCandidates.fit(c, needs: needs, nightlyCapInr: cap, center: munnarCenter);

    test('for a wheelchair user, access dominates a slightly better rating', () {
      final good = withAccess('accessible', SupportLevel.yes, rating: 3.8);
      final grand = withAccess('inaccessible', SupportLevel.no, rating: 4.9);
      expect(fit(good), greaterThan(fit(grand)));
    });

    test('verified beats unverified beats known-bad', () {
      final yes = fit(withAccess('a', SupportLevel.yes));
      final partial = fit(withAccess('b', SupportLevel.partial));
      final unknown = fit(withAccess('c', SupportLevel.unknown));
      final no = fit(withAccess('d', SupportLevel.no));
      expect(yes, greaterThan(partial));
      expect(partial, greaterThan(unknown));
      expect(unknown, greaterThan(no));
    });

    test('with no access needs, price and rating decide', () {
      final cheapGood = cand('a', rating: 4.5, nightly: 2000);
      final pricey = cand('b', rating: 4.5, nightly: 9000);
      expect(fit(cheapGood, needs: const {}, cap: 3000), greaterThan(fit(pricey, needs: const {}, cap: 3000)));
    });

    test('over budget is penalised, slightly over less than far over', () {
      final within = fit(cand('a', rating: 4, nightly: 2800), needs: const {}, cap: 3000);
      final slightly = fit(cand('b', rating: 4, nightly: 3400), needs: const {}, cap: 3000);
      final far = fit(cand('c', rating: 4, nightly: 8000), needs: const {}, cap: 3000);
      expect(within, greaterThan(slightly));
      expect(slightly, greaterThan(far));
    });

    test('a rating from a handful of reviews is trusted less', () {
      final few = HotelCandidate(name: 'a', source: 'x', rating: 5.0, reviewCount: 2);
      final many = HotelCandidate(name: 'b', source: 'x', rating: 4.6, reviewCount: 2000);
      expect(fit(many, needs: const {}), greaterThan(fit(few, needs: const {})));
    });

    test('nearer the centre is better, and eco signals count when asked', () {
      final near = cand('a', at: LatLng(munnarCenter.latitude + 0.005, munnarCenter.longitude), rating: 4);
      final far = cand('b', at: LatLng(munnarCenter.latitude + 0.12, munnarCenter.longitude), rating: 4);
      expect(fit(near, needs: const {}), greaterThan(fit(far, needs: const {})));

      final green = cand('Eco Solar Lodge', rating: 4)..labels.add('Sustainable stay');
      final plain = cand('Plain Lodge', rating: 4);
      double eco(HotelCandidate c) => HotelCandidates.fit(c, needs: const {}, preferEco: true);
      expect(eco(green), greaterThan(eco(plain)));
    });

    test('amenities are pulled from free text in a stable order', () {
      expect(
        HotelCandidates.amenitiesIn('Free parking, swimming pool, breakfast, Elevator, pet friendly'),
        ['Free parking', 'Parking', 'Pool', 'Breakfast', 'Elevator', 'Pet friendly'],
      );
      expect(HotelCandidates.amenitiesIn('nothing to see'), isEmpty);
    });
  });

  group('HotelFinder', () {
    final geo = [
      geoPlace('gp1', 'Sunrise Heritage Home Stay', 0.0021, 0.0011, tags: {'wheelchair': 'yes', 'toilets:wheelchair': 'yes'}),
      geoPlace('gp2', 'Accessible Cottage', 0.03, 0.0, tags: {'wheelchair': 'yes'}),
    ];
    final osm = [
      osmNode(11, 'Tea Valley Resort', 0.0121, -0.0059, tags: {'wheelchair': 'limited'}),
      osmNode(12, 'Roadside Lodge', -0.02, 0.0),
    ];

    test('merges every source, folds duplicates and prices from live rates', () async {
      final rig = FinderRig(HotelWorld(geoapifyPlaces: geo, overpassPlaces: osm));
      final r = await rig.finder.find(munnarQuery());

      final names = r.options.map((o) => o.name).toSet();
      expect(names, containsAll(['Sunrise Heritage Homestay', 'Tea Valley Resort', 'Accessible Cottage', 'Roadside Lodge']));
      expect(r.considered, 8, reason: '6 Xotelo + 2 others; the two duplicates folded');
      expect(r.sources, containsAll(['Xotelo', 'Geoapify', 'OpenStreetMap', 'Xotelo live rates']));
      expect(r.location!.key, 'g100001');

      final sunrise = byName(r, 'Sunrise Heritage Homestay');
      expect(sunrise.id, 'g100001-d1');
      expect(sunrise.totalStayInr, 9600);
      expect(sunrise.nightlyInr, 3200, reason: '9600 for 3 nights, 1 room');
      expect(sunrise.priceIsEstimated, isFalse);
      expect(sunrise.cheapestOta, 'Agoda.com');
      expect(sunrise.tripAdvisorUrl, contains('tripadvisor'));
      expect(sunrise.rating, 4.6);
      expect(sunrise.distanceToCenterKm, isNotNull);
      expect(sunrise.provenance.isEstimated, isFalse);
    });

    test('rates are for all rooms, so a family taking two rooms is priced per room', () async {
      final rig = FinderRig(HotelWorld());
      final r = await rig.finder.find(munnarQuery(rooms: 2, adults: 4));
      expect(byName(r, 'Sunrise Heritage Homestay').nightlyInr, 1600, reason: '9600 / 3 nights / 2 rooms');
      final rates = rig.world.hitsFor('/rates');
      expect(rates, greaterThan(0));
    });

    test('access needs are answered from OSM tags and listing text, never guessed', () async {
      final rig = FinderRig(HotelWorld(geoapifyPlaces: geo, overpassPlaces: osm));
      final r = await rig.finder.find(munnarQuery(needs: {AccessibilityNeed.wheelchair}));

      // OSM says yes (Geoapify), so does nothing contradict it.
      final sunrise = byName(r, 'Sunrise Heritage Homestay');
      expect(sunrise.access[AccessibilityNeed.wheelchair]!.level, SupportLevel.yes);
      expect(sunrise.access[AccessibilityNeed.wheelchair]!.provenance.source, contains('OpenStreetMap'));

      // The listing says the older wing is not accessible.
      final grand = byName(r, 'Grand Plaza Munnar');
      expect(grand.access[AccessibilityNeed.wheelchair]!.level, SupportLevel.no);
      expect(grand.access[AccessibilityNeed.wheelchair]!.provenance.source, 'TripAdvisor listing');

      // Stairs only: not accessible.
      expect(byName(r, 'Budget Inn Munnar').access[AccessibilityNeed.wheelchair]!.level, SupportLevel.no);

      // OSM "limited" for the resort, while its listing says accessible rooms exist.
      final resort = byName(r, 'Tea Valley Resort');
      expect(resort.access[AccessibilityNeed.wheelchair]!.level, isIn([SupportLevel.yes, SupportLevel.partial]));

      // Every option carries an entry for every requested need.
      expect(r.options.every((o) => o.access.containsKey(AccessibilityNeed.wheelchair)), isTrue);
      // Claims come from the listing with their source.
      expect(resort.claims.first.sources.first.url, contains('tripadvisor'));
      expect(resort.amenities, contains('Pool'));
    });

    test('the accessible hotels rise to the top for a wheelchair user', () async {
      final rig = FinderRig(HotelWorld(geoapifyPlaces: geo, overpassPlaces: osm));
      final r = await rig.finder.find(munnarQuery(needs: {AccessibilityNeed.wheelchair}));
      final firstTwo = r.options.take(2).map((o) => o.access[AccessibilityNeed.wheelchair]!.level).toList();
      expect(firstTwo.every((l) => l == SupportLevel.yes || l == SupportLevel.partial), isTrue);
      final bad = r.options.indexWhere((o) => o.name == 'Budget Inn Munnar');
      final good = r.options.indexWhere((o) => o.name == 'Sunrise Heritage Homestay');
      expect(good, lessThan(bad));
    });

    test('a budget cap pushes affordable hotels up', () async {
      final rig = FinderRig(HotelWorld());
      final r = await rig.finder.find(munnarQuery(cap: 3500));
      final resort = r.options.indexWhere((o) => o.name == 'Tea Valley Resort');
      final sunrise = r.options.indexWhere((o) => o.name == 'Sunrise Heritage Homestay');
      expect(sunrise, lessThan(resort));
    });

    test('a destination TripAdvisor does not know still gets hotels, priced as estimates', () async {
      final world = HotelWorld(locationKey: 'g999999', geoapifyPlaces: geo, overpassPlaces: osm);
      // The resolver can only find a wrong key (Bengaluru), which validation rejects.
      final rig = FinderRig(world);
      final r = await rig.finder.find(munnarQuery());
      expect(r.location, isNull);
      expect(r.warnings.join(' '), contains('not found on TripAdvisor'));
      expect(r.options, isNotEmpty);
      expect(r.options.every((o) => o.priceIsEstimated), isTrue, reason: 'no live rates without Xotelo');
      expect(r.options.every((o) => o.nightlyInr != null), isTrue, reason: 'a regional default fills the gap');
      expect(r.sources, isNot(contains('Xotelo')));
      expect(r.sources, contains('AI or regional estimate'));
    });

    test('with every service down it returns an empty result with warnings, never throwing', () async {
      final world = HotelWorld(xoteloDown: true, geoapifyDown: true, overpassDown: true, tripAdvisorDown: true);
      final r = await FinderRig(world).finder.find(munnarQuery(needs: {AccessibilityNeed.wheelchair}));
      expect(r.options, isEmpty);
      expect(r.isEmpty, isTrue);
      expect(r.warnings, isNotEmpty);
    });

    test('when live rates fail the hotels are still listed, with labelled estimates', () async {
      final r = await FinderRig(HotelWorld(ratesDown: true)).finder.find(munnarQuery());
      expect(r.options, isNotEmpty);
      expect(r.options.every((o) => o.priceIsEstimated), isTrue);
      expect(r.warnings.join(' '), contains('Live prices were not available'));
      // The list price (USD) converted to rupees is used as the estimate.
      expect(byName(r, 'Sunrise Heritage Homestay').nightlyInr, greaterThan(2000));
    });

    test('the TripAdvisor pages are optional: blocking them loses detail, not hotels', () async {
      final r = await FinderRig(HotelWorld(tripAdvisorDown: true)).finder.find(munnarQuery(needs: {AccessibilityNeed.wheelchair}));
      expect(r.options, isNotEmpty);
      expect(r.sources, isNot(contains('TripAdvisor listings')));
      // Without the listing text nothing says the older wing is inaccessible.
      expect(byName(r, 'Grand Plaza Munnar').access[AccessibilityNeed.wheelchair]!.level, SupportLevel.unknown);
    });

    test('the price band and cheaper nearby dates come from the heatmap', () async {
      final world = HotelWorld(heatmap: {
        'high': ['2026-10-10', '2026-10-11'],
        'cheap': ['2026-10-08', '2026-10-13', '2026-11-20'],
        'average': ['2026-10-09'],
      });
      final r = await FinderRig(world).finder.find(munnarQuery());
      expect(r.dateBand, 'high');
      expect(r.cheapDates, ['2026-10-08', '2026-10-13'], reason: 'only within three days, in order');
      expect(r.options.first.priceBand, 'high');
    });

    test('once the traveller stops the plan, the extra work is skipped: no web loop, no page reads, no AI', () async {
      final llm = ScriptedLlm()..fallback = '{"final":{"hotels":[]}}';
      final rig = FinderRig(HotelWorld(), llm: llm, webLoop: true);
      final r = await rig.finder.find(munnarQuery(needs: {AccessibilityNeed.wheelchair}), isCancelled: () => true);
      expect(r.options, isNotEmpty);
      expect(llm.asked, isEmpty, reason: 'no model call at all');
      expect(rig.world.hitsFor('tripadvisor.com/Hotel_Review'), 0);
    });
  });

  group('web search and AI fill', () {
    test('the web loop adds hotels the listings missed, located on the map and claim-tagged', () async {
      final world = HotelWorld(overpassPlaces: [osmNode(21, 'Elephant Trail Homestay', 0.02, 0.03)]);
      final llm = ScriptedLlm([
        '{"tool":"web_search","args":{"query":"wheelchair accessible homestay Munnar"}}',
        '{"final":{"hotels":[{"name":"Elephant Trail Homestay","area":"Chinnakanal","why":"ground-floor rooms","url":"https://blog.example/elephant","priceHintInr":2600,"accessibilityClaims":["Ground floor rooms, wheelchair accessible bathroom"]},{"name":"Ghost Hotel That Is Nowhere","url":"https://x.example"}]}}',
      ])..fallback = null;
      final rig = FinderRig(world, llm: llm, webLoop: true);
      final r = await rig.finder.find(munnarQuery(needs: {AccessibilityNeed.wheelchair}));

      expect(r.sources, contains('Web search'));
      final o = byName(r, 'Elephant Trail Homestay');
      expect(o.location, isNotNull, reason: 'found by name on OpenStreetMap');
      expect(o.access[AccessibilityNeed.wheelchair]!.level, SupportLevel.yes);
      expect(o.access[AccessibilityNeed.wheelchair]!.provenance.source, 'Web search');
      expect(o.access[AccessibilityNeed.wheelchair]!.provenance.confidence, lessThan(0.6), reason: 'a web claim is weaker than a tag');
      expect(o.claims.map((c) => c.text), contains('Ground floor rooms, wheelchair accessible bathroom'));
      expect(o.priceIsEstimated, isTrue);
      expect(rig.search.lastProvider, isNotNull);
      // The unlocatable hotel is kept, without a pin, rather than invented a place for.
      final ghost = r.options.where((x) => x.name == 'Ghost Hotel That Is Nowhere');
      expect(ghost.every((g) => g.location == null), isTrue);
    });

    test('a hotel the web loop places far from the destination is not given a location', () async {
      final world = HotelWorld(overpassPlaces: [
        {'type': 'node', 'id': 99, 'lat': 12.9, 'lon': 77.6, 'tags': {'name': 'Far Away Lodge', 'tourism': 'hotel'}},
      ]);
      final llm = ScriptedLlm(['{"final":{"hotels":[{"name":"Far Away Lodge","url":"https://x.example"}]}}']);
      final r = await FinderRig(world, llm: llm, webLoop: true).finder.find(munnarQuery(needs: {AccessibilityNeed.wheelchair}));
      final far = r.options.where((o) => o.name == 'Far Away Lodge');
      expect(far.every((o) => o.location == null), isTrue);
    });

    test('junk from the web loop is ignored and never breaks the search', () async {
      for (final junk in ['not json at all', '{"final":{"hotels":"nope"}}', '{"final":{"hotels":[1,null,{"name":""},{"name":"${'x' * 500}"}]}}']) {
        final llm = ScriptedLlm([junk])..fallback = null;
        final r = await FinderRig(HotelWorld(), llm: llm, webLoop: true).finder.find(munnarQuery(needs: {AccessibilityNeed.wheelchair}));
        expect(r.options, isNotEmpty, reason: junk);
      }
    });

    test('the model fills missing prices and needs, always labelled, and never says “confirmed”', () async {
      // Only OSM knows these hotels: no price, no access information.
      final world = HotelWorld(xoteloDown: true, overpassPlaces: [osmNode(31, 'Lakeview Lodge', 0.005, 0.005), osmNode(32, 'Pine Rest House', -0.005, 0.002)]);
      final llm = ScriptedLlm([
        '{"items":{"osm:node/31":{"nightlyInr":2400,"access_wheelchair":"yes"},"osm:node/32":{"nightlyInr":1800,"access_wheelchair":"no"}}}',
      ]);
      final r = await FinderRig(world, llm: llm).finder.find(munnarQuery(needs: {AccessibilityNeed.wheelchair}));

      final lake = byName(r, 'Lakeview Lodge');
      expect(lake.nightlyInr, 2400);
      expect(lake.priceIsEstimated, isTrue);
      final s = lake.access[AccessibilityNeed.wheelchair]!;
      expect(s.level, SupportLevel.partial, reason: 'an unverified “yes” is capped at “partly”');
      expect(s.provenance.isEstimated, isTrue);
      expect(s.detail, contains('not verified'));
      expect(byName(r, 'Pine Rest House').access[AccessibilityNeed.wheelchair]!.level, SupportLevel.no);
      expect(r.sources, contains('AI or regional estimate'));
    });

    test('an unusable AI reply falls back to regional defaults and unknown access', () async {
      final world = HotelWorld(xoteloDown: true, overpassPlaces: [osmNode(31, 'Lakeview Lodge', 0.005, 0.005)]);
      final llm = ScriptedLlm(['total nonsense']);
      final r = await FinderRig(world, llm: llm).finder.find(munnarQuery(needs: {AccessibilityNeed.wheelchair}));
      final lake = byName(r, 'Lakeview Lodge');
      expect(lake.nightlyInr, 3000, reason: 'the mid-tier regional default');
      expect(lake.priceIsEstimated, isTrue);
      expect(lake.access[AccessibilityNeed.wheelchair]!.level, SupportLevel.unknown);
    });

    test('nothing real is ever overwritten by the model', () async {
      final llm = ScriptedLlm(['{"items":{"g100001-d1":{"nightlyInr":99999,"access_wheelchair":"no"}}}']);
      final rig = FinderRig(HotelWorld(geoapifyPlaces: [geoPlace('gp1', 'Sunrise Heritage Home Stay', 0.0021, 0.0011, tags: {'wheelchair': 'yes'})]), llm: llm);
      final r = await rig.finder.find(munnarQuery(needs: {AccessibilityNeed.wheelchair}));
      final s = byName(r, 'Sunrise Heritage Homestay');
      expect(s.nightlyInr, 3200);
      expect(s.access[AccessibilityNeed.wheelchair]!.level, SupportLevel.yes);
    });
  });

  group('query', () {
    test('nights are calendar nights, never below one', () {
      expect(munnarQuery(nights: 3).nights, 3);
      expect(HotelQuery(destination: 'x', center: munnarCenter, checkIn: DateTime(2026, 10, 10, 9), checkOut: DateTime(2026, 10, 10, 18)).nights, 1);
    });

    test('copyWith changes what it is asked to and keeps the rest', () {
      final q = munnarQuery(cap: 1000, needs: {AccessibilityNeed.visual});
      final higher = q.copyWith(nightlyCapInr: 1800, radiusKm: 20);
      expect((higher.nightlyCapInr, higher.radiusKm, higher.needs, higher.destination), (1800, 20.0, q.needs, 'Munnar'));
      expect(q.copyWith(clearCap: true).nightlyCapInr, isNull);
    });
  });
}
