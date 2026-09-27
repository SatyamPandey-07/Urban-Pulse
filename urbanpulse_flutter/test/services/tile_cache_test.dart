import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:urbanpulse/services/tile_cache.dart';

void main() {
  final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);

  test('a tile is fetched once, then served from the store', () async {
    var calls = 0;
    final store = MemoryTileStore();
    final loader = TileLoader(
      store: store,
      client: MockClient((req) async {
        calls++;
        return http.Response.bytes(png, 200);
      }),
    );
    expect(await loader.load('https://t/1/2/3.png'), png);
    expect(await loader.load('https://t/1/2/3.png'), png);
    expect(calls, 1);
    expect(await store.has('https://t/1/2/3.png'), isTrue);
  });

  test('offline, a tile seen before still draws, and one never seen is simply missing', () async {
    final store = MemoryTileStore();
    await store.put('https://t/seen.png', png);
    final offline = TileLoader(store: store, client: MockClient((_) async => throw Exception('no signal')));
    expect(await offline.load('https://t/seen.png'), png);
    expect(await offline.load('https://t/never.png'), isNull);
  });

  test('errors and empty answers are not stored', () async {
    final store = MemoryTileStore();
    final loader = TileLoader(store: store, client: MockClient((_) async => http.Response('', 404)));
    expect(await loader.load('https://t/x.png'), isNull);
    expect(await store.has('https://t/x.png'), isFalse);
    final empty = TileLoader(store: store, client: MockClient((_) async => http.Response.bytes(Uint8List(0), 200)));
    expect(await empty.load('https://t/y.png'), isNull);
  });

  test('simultaneous requests for one tile share a fetch', () async {
    var calls = 0;
    final loader = TileLoader(
      store: MemoryTileStore(),
      client: MockClient((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response.bytes(png, 200);
      }),
    );
    await Future.wait([loader.load('https://t/z.png'), loader.load('https://t/z.png'), loader.load('https://t/z.png')]);
    expect(calls, 1);
  });

  group('which tiles cover a trip', () {
    test('a city block at three zooms is a handful of tiles', () {
      final t = TileCache.tilesCovering(const [LatLng(26.9124, 75.7873), LatLng(26.9239, 75.8267)]);
      expect(t.map((e) => e.$1).toSet(), {13, 14, 15});
      expect(t.length, inInclusiveRange(6, 120));
      expect(t.every((e) => e.$2 >= 0 && e.$3 >= 0 && e.$2 < (1 << e.$1)), isTrue);
    });

    test('the tile of a known point is the right one', () {
      // Jaipur (26.9124, 75.7873) at zoom 13: x = (75.7873 + 180) / 360 * 8192 = 5820.6, and y from the
      // Mercator formula = 3459.
      final t = TileCache.tilesCovering(const [LatLng(26.9124, 75.7873)], zooms: const [13], marginDeg: 0);
      expect(t, [(13, 5820, 3459)]);
    });

    test('nothing, or nonsense, covers nothing', () {
      expect(TileCache.tilesCovering(const []), isEmpty);
      expect(TileCache.tilesCovering(const [LatLng(double.nan, 1)]), isEmpty);
    });
  });
}
