import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_brief.dart';

/// Confirmed Yatri trip briefs, newest first, persisted as JSON. Phase-2
/// agents read the latest brief as their input.
class TripBriefRepository {
  TripBriefRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'yatri.trip_briefs_json';
  static const _maxKept = 20;

  List<TripBrief> getBriefs() {
    final json = _prefs.getString(_key);
    if (json == null) return const [];
    try {
      return [
        for (final b in jsonDecode(json) as List<dynamic>)
          TripBrief.fromJson(b as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  TripBrief? latest() => getBriefs().firstOrNull;

  Future<void> save(TripBrief brief) async {
    final list = [
      brief,
      ...getBriefs().where((b) => b.id != brief.id),
    ].take(_maxKept);
    await _prefs.setString(_key, jsonEncode([for (final b in list) b.toJson()]));
  }
}
