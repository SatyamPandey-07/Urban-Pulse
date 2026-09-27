import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'sos_models.dart';

/// Live updates from the backend; [close] ends them.
abstract class SosSubscription {
  Future<void> close();
}

/// Where SOS events live. The Supabase implementation relies on row level
/// security: other users' SOS events come back only when this user's own
/// recent presence is within their alert radius of them.
abstract class SosBackend {
  /// The signed-in user, or null.
  String? get userId;

  /// Raises an SOS. When one is already active for this user (a duplicate
  /// trigger, or a retry after a lost reply) that one is returned instead.
  Future<SosEvent> raise({required String name, required SosCategory category, required SosSource source, SosPoint? at});

  /// This user's active SOS, if any.
  Future<SosEvent?> myActive();

  /// Location heartbeat for an active SOS (also refreshes it, so it is not stale).
  Future<void> move(String id, SosPoint? at);

  Future<void> close(String id, {bool cancelled = false});

  /// Where this user is, so SOS events near them become visible.
  Future<void> presence(SosPoint at, double radiusKm);

  /// Other users' SOS events visible to this user (active, or just closed).
  Future<List<SosEvent>> nearby();

  /// How many people said they are on their way to [id].
  Future<int> responders(String id);

  Future<void> respond(String id, String name);

  /// Changes to visible SOS events and to responses; [onHealth] reports
  /// whether the live connection is up.
  SosSubscription listen({
    required void Function(SosEvent e) onEvent,
    required void Function(String sosId) onResponse,
    required void Function(bool ok) onHealth,
  });
}

class SupabaseSosBackend implements SosBackend {
  SupabaseSosBackend(this._c);

  final SupabaseClient _c;

  static const _timeout = Duration(seconds: 12);

  @override
  String? get userId => _c.auth.currentUser?.id;

  @override
  Future<SosEvent> raise({required String name, required SosCategory category, required SosSource source, SosPoint? at}) async {
    try {
      final row = await _c
          .from('sos_events')
          .insert({
            'display_name': name,
            'category': category.name,
            'source': source.wire,
            'lat': at?.lat,
            'lng': at?.lng,
            'accuracy_m': at?.accuracyM,
          })
          .select()
          .single()
          .timeout(_timeout);
      return SosEvent.fromRow(row);
    } on PostgrestException catch (e) {
      // 23505: one is already active (a duplicate trigger); use that one.
      if (e.code == '23505') {
        final existing = await myActive();
        if (existing != null) return existing;
      }
      rethrow;
    }
  }

  @override
  Future<SosEvent?> myActive() async {
    final uid = userId;
    if (uid == null) return null;
    final row = await _c.from('sos_events').select().eq('user_id', uid).eq('status', 'active').maybeSingle().timeout(_timeout);
    return row == null ? null : SosEvent.fromRow(row);
  }

  @override
  Future<void> move(String id, SosPoint? at) async {
    // 'status' is always sent (unchanged) so a heartbeat without a new fix still
    // refreshes updated_at; a closed SOS is never touched.
    await _c
        .from('sos_events')
        .update({if (at != null) ...{'lat': at.lat, 'lng': at.lng, 'accuracy_m': at.accuracyM}, 'status': 'active'})
        .eq('id', id)
        .eq('status', 'active')
        .timeout(_timeout);
  }

  @override
  Future<void> close(String id, {bool cancelled = false}) async {
    await _c.from('sos_events').update({'status': cancelled ? 'cancelled' : 'resolved'}).eq('id', id).eq('status', 'active').timeout(_timeout);
  }

  @override
  Future<void> presence(SosPoint at, double radiusKm) async {
    final uid = userId;
    if (uid == null) return;
    await _c
        .from('sos_presence')
        .upsert({'user_id': uid, 'lat': at.lat, 'lng': at.lng, 'radius_km': radiusKm, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .timeout(_timeout);
  }

  @override
  Future<List<SosEvent>> nearby() async {
    final uid = userId;
    if (uid == null) return const [];
    final rows = await _c.from('sos_events').select().neq('user_id', uid).order('updated_at', ascending: false).limit(50).timeout(_timeout);
    return [for (final r in rows) SosEvent.fromRow(r)];
  }

  @override
  Future<int> responders(String id) async {
    final rows = await _c.from('sos_responses').select('responder_id').eq('sos_id', id).timeout(_timeout);
    return rows.length;
  }

  @override
  Future<void> respond(String id, String name) async {
    await _c.from('sos_responses').upsert({'sos_id': id, 'responder_name': name}, onConflict: 'sos_id,responder_id').timeout(_timeout);
  }

  @override
  SosSubscription listen({
    required void Function(SosEvent e) onEvent,
    required void Function(String sosId) onResponse,
    required void Function(bool ok) onHealth,
  }) {
    final channel = _c
        .channel('sos-live-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sos_events',
          callback: (p) {
            if (p.newRecord.isNotEmpty) onEvent(SosEvent.fromRow(p.newRecord));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'sos_responses',
          callback: (p) {
            final id = p.newRecord['sos_id'] ?? p.oldRecord['sos_id'];
            if (id != null) onResponse('$id');
          },
        );
    channel.subscribe((status, [error]) {
      onHealth(status == RealtimeSubscribeStatus.subscribed);
    });
    return _Sub(_c, channel);
  }
}

class _Sub implements SosSubscription {
  _Sub(this._c, this._ch);

  final SupabaseClient _c;
  final RealtimeChannel _ch;

  @override
  Future<void> close() async {
    try {
      await _c.removeChannel(_ch);
    } catch (_) {
      // already gone
    }
  }
}
