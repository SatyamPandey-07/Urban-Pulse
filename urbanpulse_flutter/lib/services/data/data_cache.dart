import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A small TTL cache for API responses. Free tiers are tight (Tavily 1,000
/// credits a month, Geoapify ~3,000 a day, Overpass has strict usage rules), so
/// every adapter caches by request. Failures are never cached.
abstract interface class DataCache {
  Future<String?> get(String key);

  Future<void> put(String key, String value, {Duration ttl});
}

class MemoryCache implements DataCache {
  MemoryCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, ({String value, DateTime expires})> _store = {};

  int get length => _store.length;

  @override
  Future<String?> get(String key) async {
    final e = _store[key];
    if (e == null) return null;
    if (_now().isAfter(e.expires)) {
      _store.remove(key);
      return null;
    }
    return e.value;
  }

  @override
  Future<void> put(String key, String value, {Duration ttl = const Duration(hours: 24)}) async {
    _store[key] = (value: value, expires: _now().add(ttl));
  }
}

/// Persists across launches in SharedPreferences (one JSON blob per entry,
/// capped so it cannot grow without bound).
class PrefsCache implements DataCache {
  PrefsCache(this._prefs, {DateTime Function()? now, this.maxEntries = 400})
    : _now = now ?? DateTime.now;

  static const _prefix = 'yatri.cache.';
  final SharedPreferences _prefs;
  final DateTime Function() _now;
  final int maxEntries;

  @override
  Future<String?> get(String key) async {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final expires = DateTime.fromMillisecondsSinceEpoch(m['e'] as int);
      if (_now().isAfter(expires)) {
        await _prefs.remove('$_prefix$key');
        return null;
      }
      return m['v'] as String;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> put(String key, String value, {Duration ttl = const Duration(hours: 24)}) async {
    await _prefs.setString(
      '$_prefix$key',
      jsonEncode({'v': value, 'e': _now().add(ttl).millisecondsSinceEpoch}),
    );
    await _evictIfNeeded();
  }

  Future<void> _evictIfNeeded() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    if (keys.length <= maxEntries) return;
    final entries = <(String, int)>[];
    for (final k in keys) {
      try {
        final m = jsonDecode(_prefs.getString(k)!) as Map<String, dynamic>;
        entries.add((k, m['e'] as int));
      } catch (_) {
        entries.add((k, 0));
      }
    }
    entries.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (k, _) in entries.take(keys.length - maxEntries)) {
      await _prefs.remove(k);
    }
  }
}

extension JsonCache on DataCache {
  /// Returns the cached JSON for [key], or fetches it with [fetch] and caches a
  /// non-null result. [fetch] returning null (a failure) is not cached.
  Future<Object?> rememberJson(
    String key,
    Future<Object?> Function() fetch, {
    Duration ttl = const Duration(hours: 24),
  }) async {
    final hit = await get(key);
    if (hit != null) {
      try {
        return jsonDecode(hit);
      } catch (_) {
        // corrupt entry: fall through and refetch
      }
    }
    final fresh = await fetch();
    if (fresh != null) await put(key, jsonEncode(fresh), ttl: ttl);
    return fresh;
  }
}
