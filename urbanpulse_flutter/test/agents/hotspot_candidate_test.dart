import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/agents/bhatkanti/hotspot_candidate.dart';

HotspotCandidate at(String name, double lat, double lng, {String source = 'osm'}) => HotspotCandidate(name: name, location: LatLng(lat, lng), source: source);

void main() {
  group('one place found by different sources is one place', () {
    test('a distinctive name a few km apart (a point and a centre) is merged', () {
      // about 5 km apart
      expect(HotspotCandidates.sameSpot(at('Amber Fort', 26.9855, 75.8513), at('Amber Fort', 27.0200, 75.8700, source: 'wikipedia')), isTrue);
    });

    test('merging keeps one entry and both sources', () {
      final out = HotspotCandidates.merge([at('Amber Fort', 26.9855, 75.8513), at('Amber Fort', 27.0200, 75.8700, source: 'wikipedia')]);
      expect(out.length, 1);
      expect(out.single.sourceNames, {'osm', 'wikipedia'});
    });

    test('the same distinctive name in another town is a different place', () {
      // more than 100 km apart
      expect(HotspotCandidates.sameSpot(at('Lake View Point', 10.09, 77.06), at('Lake View Point', 11.4, 76.7)), isFalse);
    });

    test('a generic one-word name is only merged when very close', () {
      expect(HotspotCandidates.sameSpot(at('Viewpoint', 10.09, 77.06), at('Viewpoint', 10.09, 77.09)), isFalse);
      expect(HotspotCandidates.sameSpot(at('Viewpoint', 10.09, 77.06), at('Viewpoint', 10.091, 77.061)), isTrue);
    });

    test('names that differ are not merged just for being near', () {
      expect(HotspotCandidates.sameSpot(at('Tea Museum', 10.09, 77.06), at('Rose Garden', 10.091, 77.061)), isFalse);
    });
  });
}
