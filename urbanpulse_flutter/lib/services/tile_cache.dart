import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

/// Where map tiles are kept between runs.
abstract class TileStore {
  Future<Uint8List?> get(String key);
  Future<void> put(String key, Uint8List bytes);
  Future<bool> has(String key);
}

/// Tiles held in memory (tests, or when the device store is unavailable).
class MemoryTileStore implements TileStore {
  final Map<String, Uint8List> _m = {};

  @override
  Future<Uint8List?> get(String key) async => _m[key];

  @override
  Future<void> put(String key, Uint8List bytes) async => _m[key] = bytes;

  @override
  Future<bool> has(String key) async => _m.containsKey(key);
}

/// Tiles kept in a small database on the device, trimmed to the newest
/// [maxBytes] so the map cannot grow without limit.
class SqliteTileStore implements TileStore {
  SqliteTileStore({this.maxBytes = 60 * 1024 * 1024});

  final int maxBytes;
  Future<Database?>? _opening;
  int _writes = 0;

  Future<Database?> _open() => _opening ??= () async {
    try {
      final path = '${await getDatabasesPath()}/map_tiles.db';
      return await openDatabase(
        path,
        version: 1,
        onCreate: (db, _) => db.execute('CREATE TABLE tiles (key TEXT PRIMARY KEY, bytes BLOB NOT NULL, at INTEGER NOT NULL)'),
      );
    } catch (_) {
      return null; // no store: tiles just come from the network
    }
  }();

  @override
  Future<Uint8List?> get(String key) async {
    final db = await _open();
    if (db == null) return null;
    try {
      final rows = await db.query('tiles', columns: ['bytes'], where: 'key = ?', whereArgs: [key], limit: 1);
      return rows.isEmpty ? null : rows.first['bytes'] as Uint8List;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> has(String key) async {
    final db = await _open();
    if (db == null) return false;
    try {
      return (await db.query('tiles', columns: ['key'], where: 'key = ?', whereArgs: [key], limit: 1)).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> put(String key, Uint8List bytes) async {
    final db = await _open();
    if (db == null) return;
    try {
      await db.insert('tiles', {'key': key, 'bytes': bytes, 'at': DateTime.now().millisecondsSinceEpoch}, conflictAlgorithm: ConflictAlgorithm.replace);
      if (++_writes % 50 == 0) await _trim(db);
    } catch (_) {}
  }

  /// Drops the oldest tiles until the store is under its limit.
  Future<void> _trim(Database db) async {
    try {
      var total = (await db.rawQuery('SELECT COALESCE(SUM(LENGTH(bytes)), 0) AS n FROM tiles')).first['n'] as int;
      while (total > maxBytes) {
        final old = await db.rawQuery('SELECT key, LENGTH(bytes) AS n FROM tiles ORDER BY at ASC LIMIT 100');
        if (old.isEmpty) break;
        for (final r in old) {
          await db.delete('tiles', where: 'key = ?', whereArgs: [r['key']]);
          total -= r['n'] as int;
        }
      }
    } catch (_) {}
  }
}

/// Fetches a tile, from the store if it is there and from the network (then
/// stored) if not. Null when it is in neither, for instance offline in an
/// area never viewed.
class TileLoader {
  TileLoader({required this.store, http.Client? client}) : _client = client ?? http.Client();

  final TileStore store;
  final http.Client _client;
  final Map<String, Future<Uint8List?>> _inFlight = {};

  static const userAgent = 'UrbanPulseApp/1.0';

  Future<Uint8List?> load(String url) {
    // Identical requests at once share one fetch.
    // (The block body matters: `remove` returns this very future, and an
    // expression body would make `whenComplete` wait on itself forever.)
    return _inFlight[url] ??= _load(url).whenComplete(() {
      _inFlight.remove(url);
    });
  }

  Future<Uint8List?> _load(String url) async {
    final cached = await store.get(url);
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final res = await _client.get(Uri.parse(url), headers: const {'User-Agent': userAgent}).timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300 || res.bodyBytes.isEmpty) return null;
      await store.put(url, res.bodyBytes);
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }
}

/// A tile provider that remembers what it has drawn.
class CachedTileProvider extends TileProvider {
  CachedTileProvider({required this.loader}) : super(headers: <String, String>{'User-Agent': TileLoader.userAgent});

  final TileLoader loader;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => _TileImage(getTileUrl(coordinates, options), loader);
}

class _TileImage extends ImageProvider<_TileImage> {
  const _TileImage(this.url, this.loader);

  final String url;
  final TileLoader loader;

  @override
  Future<_TileImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_TileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _codec(decode),
      scale: 1,
      debugLabel: url,
    );
  }

  Future<ui.Codec> _codec(ImageDecoderCallback decode) async {
    final bytes = await loader.load(url);
    if (bytes == null) throw StateError('tile not available');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is _TileImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// The app's one tile cache.
class TileCache {
  TileCache._();

  static final TileCache instance = TileCache._();

  final TileLoader loader = TileLoader(store: SqliteTileStore());

  late final CachedTileProvider provider = CachedTileProvider(loader: loader);

  /// The tiles that cover [points] (with a margin) at each of [zooms].
  static List<(int z, int x, int y)> tilesCovering(List<LatLng> points, {List<int> zooms = const [13, 14, 15], double marginDeg = 0.01}) {
    if (points.isEmpty) return const [];
    var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;
    for (final p in points) {
      if (!p.latitude.isFinite || !p.longitude.isFinite) continue;
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }
    if (minLat > maxLat) return const [];
    minLat = (minLat - marginDeg).clamp(-85.0, 85.0);
    maxLat = (maxLat + marginDeg).clamp(-85.0, 85.0);
    minLon = (minLon - marginDeg).clamp(-180.0, 180.0);
    maxLon = (maxLon + marginDeg).clamp(-180.0, 180.0);
    final out = <(int, int, int)>[];
    for (final z in zooms) {
      final n = 1 << z;
      int x(double lon) => ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
      int y(double lat) {
        final r = lat * math.pi / 180;
        return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n).floor().clamp(0, n - 1);
      }

      for (var tx = x(minLon); tx <= x(maxLon); tx++) {
        for (var ty = y(maxLat); ty <= y(minLat); ty++) {
          out.add((z, tx, ty));
        }
      }
    }
    return out;
  }

  /// Downloads the standard map for the area around [points] so it can be
  /// used without signal. Kept modest on purpose (at most [maxTiles]) out of
  /// respect for the tile servers. Returns how many tiles are now available.
  Future<int> saveArea(List<LatLng> points, {int maxTiles = 220, void Function(int done, int total)? onProgress}) async {
    var tiles = tilesCovering(points);
    if (tiles.length > maxTiles) tiles = tilesCovering(points, zooms: const [13, 14]);
    if (tiles.length > maxTiles) tiles = tiles.take(maxTiles).toList();
    var done = 0, available = 0;
    for (final t in tiles) {
      final url = 'https://tile.openstreetmap.org/${t.$1}/${t.$2}/${t.$3}.png';
      final had = await loader.store.has(url);
      final bytes = await loader.load(url);
      if (bytes != null) available++;
      onProgress?.call(++done, tiles.length);
      // A little gap between requests keeps this a light load on the servers.
      if (!had) await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    return available;
  }
}
