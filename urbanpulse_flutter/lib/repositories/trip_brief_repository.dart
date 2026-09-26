import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trip_brief.dart';
import '../services/cloud/cloud_store.dart';

/// Confirmed Yatri trip briefs, newest first, persisted as JSON. Phase-2
/// agents read the latest brief as their input.
class TripBriefRepository {
  TripBriefRepository(this._prefs, {this.cloud});

  final SharedPreferences _prefs;
  final CloudStore? cloud;

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

  /// Saves [brief] on the device and in the traveller's account.
  Future<void> save(TripBrief brief) async {
    await replaceAll([
      brief,
      ...getBriefs().where((b) => b.id != brief.id),
    ]);
    await cloud?.saveBrief(brief);
  }

  /// The device copy becomes [briefs] (the account's, after sign-in).
  Future<void> replaceAll(List<TripBrief> briefs) =>
      _prefs.setString(_key, jsonEncode([for (final b in briefs.take(_maxKept)) b.toJson()]));

  Future<void> clear() => _prefs.remove(_key);
}
