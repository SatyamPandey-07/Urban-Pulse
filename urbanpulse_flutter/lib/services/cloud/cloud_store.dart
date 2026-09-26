import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/itinerary/itinerary.dart';
import '../../models/trip_brief.dart';
import '../../models/trip_models.dart';

/// Everything the signed-in traveller's account holds, as read back from the
/// database after sign-in.
class CloudSnapshot {
  const CloudSnapshot({
    required this.briefs,
    required this.itineraries,
    required this.trips,
    this.settings,
    this.progress,
    this.profile,
  });

  /// `TripBrief.toJson()` maps, newest first.
  final List<Map<String, dynamic>> briefs;

  /// `Itinerary.toJson()` maps of the saved itineraries, newest first.
  final List<Map<String, dynamic>> itineraries;

  /// `TripPlan.toJson()` maps, newest first.
  final List<Map<String, dynamic>> trips;
  final Map<String, dynamic>? settings;
  final Map<String, dynamic>? progress;
  final Map<String, dynamic>? profile;
}

/// The traveller's data in Supabase (schema in `supabase/migrations`).
///
/// Every write goes into an outbox kept in shared preferences and is sent at
/// once when possible; what cannot be sent (offline, session expired) stays
/// queued and is retried on the next write, start or sign-in, so nothing is
/// lost. Each queued write belongs to the traveller who made it and is only
/// ever sent under their session. Reads come from the device cache the
/// repositories keep, which `UserSync` fills from [pull] after sign-in.
///
/// With no client (Supabase not configured) every call does nothing.
class CloudStore {
  CloudStore(this._prefs, this._client);

  final SharedPreferences _prefs;
  final SupabaseClient? _client;

  static const _outboxKey = 'cloud.outbox.v1';
  static const _failedKey = 'cloud.failed.v1';
  static const maxQueued = 500;

  bool get enabled => _client != null;

  String? get userId => _client?.auth.currentUser?.id;

  /// Writes waiting to be sent, for diagnostics.
  int get pending => _outbox().length;

  bool _flushing = false;
  int _seq = 0;

  // --- what the app writes -----------------------------------------------------

  /// A confirmed trip brief; its access and food answers also become the
  /// traveller's remembered preferences.
  Future<void> saveBrief(TripBrief b) => _enqueue('brief', {
    'row': {
      'client_id': b.id,
      'destination': b.destination,
      'origin_city': b.originCity,
      'start_at': b.start?.toUtc().toIso8601String(),
      'end_at': b.end?.toUtc().toIso8601String(),
      'traveller_count': b.travellerCount,
      'budget_min_inr': b.budgetMinInr,
      'budget_max_inr': b.budgetMaxInr,
      'accessibility_needs': [for (final n in b.accessibilityNeeds) n.name],
      'brief': b.toJson(),
    },
    'settings': {
      'accessibility_needs': [for (final n in b.accessibilityNeeds) if (n != AccessibilityNeed.none) n.name],
      'accessibility_details': {for (final e in b.accessibilityDetails.entries) e.key: e.value.toList()},
      'dietary': [for (final d in b.dietary) d.name],
    },
  });

  /// An itinerary the agents built. [saved] marks it as kept in My Trips;
  /// false leaves an earlier "saved" untouched.
  Future<void> saveItinerary(Itinerary it, {required bool saved, String? briefClientId, bool partial = false}) {
    final visits = it.days.fold<int>(0, (s, d) => s + d.slots.where((x) => x.kind == SlotKind.visit).length);
    return _enqueue('itinerary', {
      'briefClientId': briefClientId ?? it.brief?.id,
      'row': {
        'client_id': it.id,
        'destination': it.destination,
        'origin': it.origin,
        'start_at': it.start.toUtc().toIso8601String(),
        'end_at': it.end.toUtc().toIso8601String(),
        'day_count': it.days.length,
        'visit_count': visits,
        'total_inr': it.budget.totalInr,
        'budget_max_inr': it.budget.budgetMaxInr,
        'hotel_name': it.hotel?.name,
        'status': partial ? 'partial' : 'planned',
        'caveats': it.assumptions,
        'itinerary': it.toJson(),
        if (saved) 'saved': true,
      },
    });
  }

  /// A trip saved to My Trips.
  Future<void> saveTrip(TripPlan plan, {String? itineraryClientId}) => _enqueue('trip', {
    'itineraryClientId': itineraryClientId,
    'row': {'client_id': plan.id, 'destination': plan.destination, 'plan': plan.toJson()},
  });

  /// Some of the traveller's settings (only the fields given change).
  Future<void> saveSettings(Map<String, Object?> fields) => _enqueue('settings', {'row': fields});

  /// Some of the traveller's progress (only the fields given change).
  Future<void> saveProgress(Map<String, Object?> fields) => _enqueue('progress', {'row': fields});

  /// A planning run, its task graph and every decision the traveller made in it.
  Future<void> saveRun({
    required Map<String, Object?> run,
    required List<Map<String, Object?>> decisions,
    String? briefClientId,
    String? itineraryClientId,
  }) => _enqueue('run', {'briefClientId': briefClientId, 'itineraryClientId': itineraryClientId, 'row': run, 'decisions': decisions});

  // --- the outbox ----------------------------------------------------------------

  Future<void> _enqueue(String kind, Map<String, Object?> data) async {
    final uid = userId;
    if (!enabled || uid == null) return;
    final box = _outbox();
    // Settings and progress: the queued change is merged into any still waiting.
    final waiting = kind == 'settings' || kind == 'progress' ? box.indexWhere((e) => e['kind'] == kind && e['user'] == uid) : -1;
    if (waiting >= 0) {
      final prev = Map<String, dynamic>.from(box[waiting]['data'] as Map);
      prev['row'] = {...(prev['row'] as Map), ...(data['row']! as Map)};
      box[waiting] = {...box[waiting], 'data': prev};
    } else {
      box.add({'id': '${DateTime.now().microsecondsSinceEpoch}-${_seq++}', 'kind': kind, 'user': uid, 'data': data});
    }
    if (box.length > maxQueued) box.removeRange(0, box.length - maxQueued);
    await _save(box);
    unawaited(flush());
  }

  /// Sends the signed-in traveller's queued writes, oldest first. Stops at the
  /// first one that cannot be sent right now, to keep their order.
  Future<void> flush() async {
    final c = _client;
    final uid = userId;
    if (c == null || uid == null || _flushing) return;
    _flushing = true;
    try {
      while (true) {
        final next = _outbox().where((e) => e['user'] == uid).firstOrNull;
        if (next == null) break;
        try {
          await _send(c, uid, next['kind'] as String, Map<String, dynamic>.from(next['data'] as Map));
        } on PostgrestException catch (e) {
          // The database refused it (a constraint or policy): retrying cannot
          // help, so it is set aside with the reason, never retried forever.
          await _setAside(next, '${e.code}: ${e.message}');
        } catch (_) {
          break; // offline or the session lapsed: try again later
        }
        await _save(_outbox()..removeWhere((e) => e['id'] == next['id']));
      }
    } finally {
      _flushing = false;
    }
  }

  Future<void> _send(SupabaseClient c, String uid, String kind, Map<String, dynamic> data) async {
    final row = {...Map<String, dynamic>.from(data['row'] as Map), 'user_id': uid};
    Future<String?> idOf(String table, Object? clientId) async {
      if (clientId is! String) return null;
      final r = await c.from(table).select('id').eq('user_id', uid).eq('client_id', clientId).maybeSingle();
      return r?['id'] as String?;
    }

    switch (kind) {
      case 'brief':
        await c.from('trip_briefs').upsert(row, onConflict: 'user_id,client_id');
        final s = data['settings'];
        if (s is Map) await c.from('user_settings').upsert({...Map<String, dynamic>.from(s), 'user_id': uid}, onConflict: 'user_id');
      case 'itinerary':
        final briefId = await idOf('trip_briefs', data['briefClientId']);
        await c.from('itineraries').upsert({...row, 'brief_id': ?briefId}, onConflict: 'user_id,client_id');
      case 'trip':
        final itineraryId = await idOf('itineraries', data['itineraryClientId']);
        await c.from('saved_trips').upsert({...row, 'itinerary_id': ?itineraryId}, onConflict: 'user_id,client_id');
      case 'settings':
        await c.from('user_settings').upsert(row, onConflict: 'user_id');
      case 'progress':
        await c.from('user_progress').upsert(row, onConflict: 'user_id');
      case 'run':
        final briefId = await idOf('trip_briefs', data['briefClientId']);
        final itineraryId = await idOf('itineraries', data['itineraryClientId']);
        final saved = await c
            .from('plan_runs')
            .upsert({...row, 'brief_id': ?briefId, 'itinerary_id': ?itineraryId}, onConflict: 'user_id,client_id')
            .select('id')
            .single();
        final runId = saved['id'] as String;
        final decisions = [
          for (final d in (data['decisions'] as List? ?? const []))
            {...Map<String, dynamic>.from(d as Map), 'run_id': runId, 'user_id': uid},
        ];
        if (decisions.isNotEmpty) await c.from('plan_decisions').upsert(decisions, onConflict: 'run_id,seq');
    }
  }

  // --- reading the account back ------------------------------------------------------

  /// The signed-in traveller's data, or null when there is no session or no
  /// connection.
  Future<CloudSnapshot?> pull() async {
    final c = _client;
    final uid = userId;
    if (c == null || uid == null) return null;
    try {
      final r = await Future.wait<Object?>([
        c.from('trip_briefs').select('brief').eq('user_id', uid).order('created_at', ascending: false).limit(20),
        c.from('itineraries').select('itinerary').eq('user_id', uid).eq('saved', true).order('created_at', ascending: false).limit(30),
        c.from('saved_trips').select('plan').eq('user_id', uid).order('created_at', ascending: false),
        c.from('user_settings').select().eq('user_id', uid).maybeSingle(),
        c.from('user_progress').select().eq('user_id', uid).maybeSingle(),
        c.from('profiles').select().eq('id', uid).maybeSingle(),
      ]);
      List<Map<String, dynamic>> col(Object? rows, String key) => [
        for (final row in (rows as List? ?? const []))
          if (row is Map && row[key] is Map) Map<String, dynamic>.from(row[key] as Map),
      ];
      Map<String, dynamic>? one(Object? row) => row is Map ? Map<String, dynamic>.from(row) : null;
      return CloudSnapshot(
        briefs: col(r[0], 'brief'),
        itineraries: col(r[1], 'itinerary'),
        trips: col(r[2], 'plan'),
        settings: one(r[3]),
        progress: one(r[4]),
        profile: one(r[5]),
      );
    } catch (_) {
      return null;
    }
  }

  /// Updates the signed-in traveller's profile (name, home city).
  Future<void> updateProfile(Map<String, Object?> fields) async {
    final c = _client;
    final uid = userId;
    if (c == null || uid == null) return;
    try {
      await c.from('profiles').update(fields).eq('id', uid);
    } catch (_) {
      // the profile is also kept in the auth user's metadata
    }
  }

  // --- storage ---------------------------------------------------------------------

  List<Map<String, dynamic>> _outbox() {
    final raw = _prefs.getString(_outboxKey);
    if (raw == null) return [];
    try {
      return [for (final e in jsonDecode(raw) as List) if (e is Map) Map<String, dynamic>.from(e)];
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<Map<String, dynamic>> box) => _prefs.setString(_outboxKey, jsonEncode(box));

  Future<void> _setAside(Map<String, dynamic> entry, String reason) async {
    List<dynamic> failed;
    try {
      failed = jsonDecode(_prefs.getString(_failedKey) ?? '[]') as List;
    } catch (_) {
      failed = [];
    }
    failed.add({...entry, 'reason': reason});
    if (failed.length > 20) failed.removeRange(0, failed.length - 20);
    await _prefs.setString(_failedKey, jsonEncode(failed));
  }
}
