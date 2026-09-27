import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:urbanpulse/models/saved_place.dart';
import 'package:urbanpulse/repositories/saved_places_repository.dart';
import 'package:urbanpulse/services/location_service.dart';
import 'package:urbanpulse/services/place_suggestions.dart';
import 'package:urbanpulse/state/location_controller.dart';
import 'package:urbanpulse/state/place_search_controller.dart';

Future<SavedPlacesRepository> repo([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues(initial);
  return SavedPlacesRepository(await SharedPreferences.getInstance());
}

Future<SavedPlace> put(SavedPlacesRepository r, PlaceKind k, String label, {String city = 'Pune', double lat = 18.5, double lon = 73.8}) async =>
    (await r.save(kind: k, label: label, address: '$label street, $city', city: city, lat: lat, lon: lon))!;

void main() {
  group('saved addresses', () {
    test('Home and Work are one each; saving again replaces', () async {
      final r = await repo();
      await put(r, PlaceKind.home, 'x', city: 'Pune');
      await put(r, PlaceKind.home, 'y', city: 'Mumbai');
      expect(r.places.where((p) => p.kind == PlaceKind.home).length, 1);
      expect(r.home!.city, 'Mumbai');
      expect(r.home!.label, 'Home');
    });

    test('others can be many, and are named by the person', () async {
      final r = await repo();
      await put(r, PlaceKind.other, "Mom's flat");
      await put(r, PlaceKind.other, 'Gym');
      expect(r.others.map((p) => p.label), ['Gym', "Mom's flat"]);
    });

    test('they survive a restart, and the chosen one too', () async {
      final r = await repo();
      final w = await put(r, PlaceKind.work, 'Work', city: 'Bengaluru');
      await r.setActive(w);
      final again = SavedPlacesRepository(await SharedPreferences.getInstance());
      expect(again.work!.city, 'Bengaluru');
      expect(again.active!.id, w.id);
    });

    test('deleting the chosen address goes back to the current location', () async {
      final r = await repo();
      final h = await put(r, PlaceKind.home, 'Home');
      await r.setActive(h);
      await r.remove(h.id);
      expect(r.active, isNull);
    });

    test('there is a limit, and bad coordinates are refused', () async {
      final r = await repo();
      for (var i = 0; i < SavedPlacesRepository.maxPlaces; i++) {
        await put(r, PlaceKind.other, 'p$i');
      }
      expect(await r.save(kind: PlaceKind.other, label: 'one more', address: 'a', city: 'c', lat: 1, lon: 1), isNull);
      final s = await repo();
      expect(await s.save(kind: PlaceKind.home, label: 'h', address: 'a', city: 'c', lat: double.nan, lon: 1), isNull);
    });

    test('damaged stored data is ignored', () async {
      final r = await repo({'urbanpulse.saved_places': '[{"id":1},{"id":"a","label":"L","lat":999,"lon":1},"x",{"id":"ok","kind":"home","label":"Home","lat":18.5,"lon":73.8}]'});
      expect(r.places.map((p) => p.id), ['ok']);
      final broken = await repo({'urbanpulse.saved_places': 'not json'});
      expect(broken.places, isEmpty);
    });
  });

  group('the location the app works from', () {
    test('a chosen address replaces the device position everywhere', () async {
      final r = await repo();
      final c = LocationController(LocationService(), places: r);
      addTearDown(c.dispose);
      expect(c.hasFix, isFalse);
      final home = await put(r, PlaceKind.home, 'Home', city: 'Jaipur', lat: 26.9, lon: 75.8);
      await c.useSavedPlace(home);
      expect(c.hasFix, isTrue);
      expect(c.latitude, 26.9);
      expect(c.originCity, 'Jaipur');
      expect(c.displayTitle, 'Home');
      expect(c.displaySubtitle, contains('Jaipur'));
      expect(c.coordinatesOrDefault, (26.9, 75.8));
    });

    test('with none chosen it follows the device, and reports the change', () async {
      final r = await repo();
      final c = LocationController(LocationService(), places: r);
      addTearDown(c.dispose);
      var n = 0;
      c.addListener(() => n++);
      final w = await put(r, PlaceKind.work, 'Work');
      await c.useSavedPlace(w);
      await r.setActive(null);
      expect(c.usingSavedPlace, isFalse);
      expect(n, greaterThan(1));
    });
  });

  group('completions while typing', () {
    test('wait for a pause, ask once, and ignore stale answers', () async {
      final asked = <String>[];
      final s = PlaceSuggestions(
        suggest: (q, _, _) async {
          asked.add(q);
          if (q == 'ban') await Future<void>.delayed(const Duration(milliseconds: 80));
          return [PlaceSuggestion(title: q.toUpperCase(), subtitle: '', lat: 1, lon: 1)];
        },
      );
      final c = PlaceSearchController(s, delay: const Duration(milliseconds: 20));
      addTearDown(c.dispose);
      c.changed('b');
      c.changed('ba');
      c.changed('ban');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      c.changed('bang');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(asked, ['ban', 'bang']);
      expect(c.suggestions.single.title, 'BANG');
      expect(c.searching, isFalse);
    });

    test('one letter searches nothing; nothing found is said; failures are quiet', () async {
      final c = PlaceSearchController(PlaceSuggestions(suggest: (_, _, _) async => throw StateError('down')), delay: Duration.zero);
      addTearDown(c.dispose);
      c.changed('a');
      expect(c.suggestions, isEmpty);
      c.changed('abc');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.noMatches, isTrue);
      expect(c.searching, isFalse);
    });

    test('a city is worked out from a point, or is null', () async {
      final s = PlaceSuggestions(cityOf: (lat, lon) async => 'Pune');
      expect(await s.cityOf(18.5, 73.8), 'Pune');
    });
  });
}
