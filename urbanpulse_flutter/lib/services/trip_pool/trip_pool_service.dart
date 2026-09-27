import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../agents/yatri/trip_pool_applier.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/trip_pool.dart';
import '../../models/trip_brief.dart';
import '../../repositories/itinerary_repository.dart';

/// A trip someone opened to Trip-pooling (another traveller's, or your own).
class PoolListing {
  const PoolListing({
    required this.id,
    required this.userId,
    required this.name,
    required this.destination,
    required this.start,
    required this.travellers,
    required this.seatsFree,
    required this.briefClientId,
    this.origin,
    this.end,
    this.mode,
    this.open = true,
  });

  final String id;
  final String userId;
  final String name;
  final String? origin;
  final String destination;
  final DateTime start;
  final DateTime? end;
  final int travellers;
  final int seatsFree;
  final String? mode;
  final String briefClientId;
  final bool open;

  static PoolListing fromRow(Map<String, dynamic> r) => PoolListing(
    id: '${r['id']}',
    userId: '${r['user_id']}',
    name: '${r['display_name'] ?? 'Traveller'}',
    origin: r['origin'] as String?,
    destination: '${r['destination'] ?? ''}',
    start: DateTime.tryParse('${r['start_date']}') ?? DateTime.now(),
    end: DateTime.tryParse('${r['end_date']}'),
    travellers: (r['travellers'] as num?)?.toInt() ?? 1,
    seatsFree: (r['seats_free'] as num?)?.toInt() ?? 0,
    mode: r['mode'] as String?,
    briefClientId: '${r['brief_client_id'] ?? ''}',
    open: r['status'] == 'open',
  );
}

enum PoolRequestStatus { pending, approved, declined, cancelled }

/// A request to join a pooled trip.
class PoolRequest {
  const PoolRequest({
    required this.id,
    required this.listingId,
    required this.fromUser,
    required this.toUser,
    required this.fromName,
    required this.fromTravellers,
    required this.fromBriefClientId,
    required this.status,
    required this.createdAt,
    this.fromOrigin,
    this.message,
    this.listing,
  });

  final String id;
  final String listingId;
  final String fromUser;
  final String toUser;
  final String fromName;
  final String? fromOrigin;
  final int fromTravellers;
  final String fromBriefClientId;
  final String? message;
  final PoolRequestStatus status;
  final DateTime createdAt;

  /// The trip asked about, when readable.
  final PoolListing? listing;

  PoolRequest withListing(PoolListing? l) => PoolRequest(
    id: id,
    listingId: listingId,
    fromUser: fromUser,
    toUser: toUser,
    fromName: fromName,
    fromOrigin: fromOrigin,
    fromTravellers: fromTravellers,
    fromBriefClientId: fromBriefClientId,
    message: message,
    status: status,
    createdAt: createdAt,
    listing: l,
  );

  static PoolRequest fromRow(Map<String, dynamic> r) => PoolRequest(
    id: '${r['id']}',
    listingId: '${r['listing_id']}',
    fromUser: '${r['from_user']}',
    toUser: '${r['to_user']}',
    fromName: '${r['from_name'] ?? 'Traveller'}',
    fromOrigin: r['from_origin'] as String?,
    fromTravellers: (r['from_travellers'] as num?)?.toInt() ?? 1,
    fromBriefClientId: '${r['from_brief_client_id'] ?? ''}',
    message: r['message'] as String?,
    status: PoolRequestStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => PoolRequestStatus.pending),
    createdAt: DateTime.tryParse('${r['created_at']}') ?? DateTime.now(),
  );
}

/// Trip-pooling: travellers going to the same place on the same day share the
/// ride. Needs accounts (Supabase); without them every call is a quiet no-op.
class TripPoolService extends ChangeNotifier {
  TripPoolService({SupabaseClient? client, required this.myName, this.itineraries}) : _client = client;

  final SupabaseClient? _client;

  /// The first name shown to other travellers.
  final String Function() myName;
  final ItineraryRepository? itineraries;

  List<PoolRequest> incoming = const [];
  List<PoolRequest> outgoing = const [];
  List<PoolListing> mine = const [];
  bool loading = false;
  String? error;

  String? get _me => _client?.auth.currentUser?.id;

  /// Signed in with an account: Trip-pooling is possible.
  bool get available => _me != null;

  int get pendingForMe => incoming.where((r) => r.status == PoolRequestStatus.pending).length;

  /// "Jaipur, Rajasthan" and " jaipur" are the same place.
  static String keyOf(String destination) => destination.split(',').first.trim().toLowerCase();

  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _first(String name) {
    final n = name.trim().split(RegExp(r'\s+')).first;
    return n.isEmpty ? 'Traveller' : (n.length > 40 ? n.substring(0, 40) : n);
  }

  /// Other travellers' open trips to the same place starting the same day.
  Future<List<PoolListing>> matches(TripBrief b) async {
    final c = _client;
    final me = _me;
    final dest = b.destination;
    final start = b.start;
    if (c == null || me == null || dest == null || dest.trim().isEmpty || start == null) return const [];
    try {
      final rows = await c
          .from('trip_pool_listings')
          .select()
          .eq('destination_key', keyOf(dest))
          .eq('start_date', _date(start))
          .eq('status', 'open')
          .neq('user_id', me)
          .order('created_at')
          .limit(10);
      return [for (final r in rows) PoolListing.fromRow(r)];
    } catch (_) {
      return const [];
    }
  }

  /// Opens this trip to Trip-pooling so others going there that day can ask.
  Future<PoolListing?> publish(TripBrief b) async {
    final c = _client;
    final me = _me;
    if (c == null || me == null || b.destination == null || b.start == null) return null;
    final travellers = math.max(1, b.travellerCount ?? 1);
    try {
      final row = await c
          .from('trip_pool_listings')
          .upsert({
            'user_id': me,
            'brief_client_id': b.id,
            'display_name': _first(myName()),
            'origin': b.originCity,
            'destination': b.destination,
            'destination_key': keyOf(b.destination!),
            'start_date': _date(b.start!),
            'end_date': b.end == null ? null : _date(b.end!),
            'travellers': travellers,
            // Free seats in the last car of the group (cars seat four).
            'seats_free': (4 - travellers % 4) % 4,
            'mode': b.transportModes.isEmpty ? null : b.transportModes.first.name,
            'status': 'open',
          }, onConflict: 'user_id,brief_client_id')
          .select()
          .single();
      return PoolListing.fromRow(row);
    } catch (_) {
      return null;
    }
  }

  /// Stops new requests for a trip.
  Future<void> close(PoolListing l) async {
    final c = _client;
    if (c == null) return;
    try {
      await c.from('trip_pool_listings').update({'status': 'closed'}).eq('id', l.id);
    } catch (_) {
      // try again next time
    }
    await refresh();
  }

  /// Asks to share [l]'s ride on the trip in [mine].
  Future<bool> ask(PoolListing l, TripBrief mine, {String? message}) async {
    final c = _client;
    final me = _me;
    if (c == null || me == null) return false;
    try {
      await c.from('trip_pool_requests').upsert({
        'listing_id': l.id,
        'from_user': me,
        'to_user': l.userId,
        'from_name': _first(myName()),
        'from_origin': mine.originCity,
        'from_travellers': math.max(1, mine.travellerCount ?? 1),
        'from_brief_client_id': mine.id,
        'message': ?message,
      }, onConflict: 'listing_id,from_user');
      unawaited(refresh());
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads the requests to and from this traveller and their open trips, then
  /// brings their itineraries in line with the approved ones.
  Future<void> refresh() async {
    final c = _client;
    final me = _me;
    if (c == null || me == null) return;
    loading = true;
    notifyListeners();
    try {
      final rows = await c.from('trip_pool_requests').select().or('from_user.eq.$me,to_user.eq.$me').order('created_at', ascending: false).limit(100);
      final reqs = [for (final r in rows) PoolRequest.fromRow(r)];
      final ids = {for (final r in reqs) r.listingId};
      final listingRows = await c
          .from('trip_pool_listings')
          .select()
          .or(ids.isEmpty ? 'user_id.eq.$me' : 'user_id.eq.$me,id.in.(${ids.join(',')})')
          .limit(200);
      final listings = {for (final r in listingRows) '${r['id']}': PoolListing.fromRow(r)};
      incoming = [for (final r in reqs) if (r.toUser == me) r.withListing(listings[r.listingId])];
      outgoing = [for (final r in reqs) if (r.fromUser == me) r.withListing(listings[r.listingId])];
      mine = [for (final l in listings.values) if (l.userId == me) l];
      error = null;
      await syncItineraries();
    } catch (e) {
      error = 'Could not load Trip-pool requests. Check your connection.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Approves or declines a request to join your trip; approving updates your
  /// itinerary at once (theirs updates when their app next syncs).
  Future<bool> respond(PoolRequest r, {required bool approve}) async {
    final c = _client;
    if (c == null) return false;
    try {
      await c.from('trip_pool_requests').update({'status': approve ? 'approved' : 'declined'}).eq('id', r.id);
    } catch (_) {
      return false;
    }
    await refresh();
    return true;
  }

  /// Withdraws your request (or leaves an approved pool).
  Future<bool> cancel(PoolRequest r) async {
    final c = _client;
    if (c == null) return false;
    try {
      await c.from('trip_pool_requests').update({'status': 'cancelled'}).eq('id', r.id);
    } catch (_) {
      return false;
    }
    await refresh();
    return true;
  }

  /// Every approved pairing is on the matching itinerary (shared journey, split
  /// cost); a cancelled or declined one is taken off. Returns how many changed.
  Future<int> syncItineraries() async {
    final repo = itineraries;
    if (repo == null) return 0;
    var changed = 0;
    for (final it in repo.all()) {
      final briefId = it.brief?.id;
      if (briefId == null) continue;
      var next = it;
      for (final r in incoming) {
        if (r.listing?.briefClientId != briefId) continue;
        next = _reconcile(next, r, TripPoolMate(requestId: r.id, name: r.fromName, travellers: r.fromTravellers, origin: r.fromOrigin, hosting: true));
      }
      for (final r in outgoing) {
        if (r.fromBriefClientId != briefId) continue;
        final l = r.listing;
        next = _reconcile(next, r, TripPoolMate(requestId: r.id, name: l?.name ?? 'Traveller', travellers: l?.travellers ?? 1, origin: l?.origin));
      }
      if (!identical(next, it)) {
        await repo.save(next);
        changed++;
      }
    }
    return changed;
  }

  static Itinerary _reconcile(Itinerary it, PoolRequest r, TripPoolMate mate) {
    final has = it.pool?.mates.any((m) => m.requestId == r.id) ?? false;
    if (r.status == PoolRequestStatus.approved && !has) return TripPoolApplier.join(it, mate);
    if (r.status != PoolRequestStatus.approved && has) return TripPoolApplier.leave(it, r.id);
    return it;
  }
}
