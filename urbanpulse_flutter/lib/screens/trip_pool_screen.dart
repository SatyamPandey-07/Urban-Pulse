import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../services/trip_pool/trip_pool_service.dart';
import '../state/app_scope.dart';
import '../widgets/common.dart';

/// Settings → Trip-pool: requests to join your trips (approve or decline),
/// your requests to join others', and your trips open to pooling. Approving
/// switches both travellers' itineraries to the shared ride.
class TripPoolScreen extends StatefulWidget {
  const TripPoolScreen({super.key});

  @override
  State<TripPoolScreen> createState() => _TripPoolScreenState();
}

class _TripPoolScreenState extends State<TripPoolScreen> {
  TripPoolService? _pool;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pool != null) return;
    _pool = AppScope.of(context).tripPool;
    unawaited(_pool!.refresh());
  }

  Future<void> _respond(PoolRequest r, bool approve) async {
    final ok = await _pool!.respond(r, approve: approve);
    if (!mounted) return;
    showToast(
      context,
      !ok
          ? 'Could not update the request. Check your connection.'
          : approve
          ? 'Trip-pool approved: your itinerary now shares the ride with ${r.fromName}.'
          : 'Request declined.',
    );
  }

  Future<void> _cancel(PoolRequest r) async {
    final ok = await _pool!.cancel(r);
    if (!mounted) return;
    showToast(context, ok ? 'Done: your itinerary is back to travelling on your own.' : 'Could not update the request.');
  }

  @override
  Widget build(BuildContext context) {
    final pool = _pool!;
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: pool,
      builder: (context, _) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Trip-pool'),
            actions: [
              IconButton(tooltip: 'Refresh', onPressed: pool.loading ? null : pool.refresh, icon: const Icon(Icons.refresh_rounded)),
            ],
            bottom: TabBar(
              tabs: [
                Tab(text: pool.pendingForMe > 0 ? 'To you (${pool.pendingForMe})' : 'To you'),
                const Tab(text: 'Your requests'),
                const Tab(text: 'Your trips'),
              ],
            ),
          ),
          body: !pool.available
              ? const EmptyState(
                  icon: Icons.lock_outline_rounded,
                  message: 'Sign in to Trip-pool: it matches you with other UrbanPulse travellers, so it needs an account.',
                )
              : Column(
                  children: [
                    if (pool.loading) const LinearProgressIndicator(minHeight: 2),
                    if (pool.error != null)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(pool.error!, style: TextStyle(color: theme.colorScheme.error)),
                      ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _list(
                            pool.incoming,
                            empty: 'No requests yet. When you open a trip to Trip-pooling, travellers going there that day can ask to join you.',
                            build: (r) => _RequestCard(
                              title: '${r.fromName}${r.fromOrigin == null ? '' : ' from ${r.fromOrigin}'} · ${r.fromTravellers} ${r.fromTravellers == 1 ? 'person' : 'people'}',
                              trip: r.listing,
                              status: r.status,
                              message: r.message,
                              actions: r.status == PoolRequestStatus.pending
                                  ? [
                                      OutlinedButton(onPressed: () => _respond(r, false), child: const Text('Decline')),
                                      FilledButton(onPressed: () => _respond(r, true), child: const Text('Approve')),
                                    ]
                                  : const [],
                            ),
                          ),
                          _list(
                            pool.outgoing,
                            empty: 'You have not asked to join anyone yet. Say yes to Trip-pool in the trip form and Yatri finds travellers going your way.',
                            build: (r) => _RequestCard(
                              title: 'With ${r.listing?.name ?? 'a traveller'}${r.listing?.origin == null ? '' : ' from ${r.listing!.origin}'}',
                              trip: r.listing,
                              status: r.status,
                              actions: r.status == PoolRequestStatus.pending || r.status == PoolRequestStatus.approved
                                  ? [
                                      TextButton(
                                        onPressed: () => _cancel(r),
                                        child: Text(r.status == PoolRequestStatus.approved ? 'Leave the pool' : 'Withdraw'),
                                      ),
                                    ]
                                  : const [],
                            ),
                          ),
                          _list(
                            pool.mine,
                            empty: 'None of your trips is open to pooling. Say yes to Trip-pool when you review a trip with Yatri.',
                            build: (l) => _RequestCard(
                              title: '${l.destination} · ${l.travellers} ${l.travellers == 1 ? 'person' : 'people'}',
                              trip: l,
                              openNote: l.open ? 'Open to requests' : 'Closed to new requests',
                              actions: l.open ? [TextButton(onPressed: () => pool.close(l), child: const Text('Stop taking requests'))] : const [],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _list<T>(List<T> items, {required String empty, required Widget Function(T) build}) {
    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [Text(empty, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)],
      );
    }
    return RefreshIndicator(
      onRefresh: _pool!.refresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => build(items[i]),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.title, this.trip, this.status, this.message, this.openNote, this.actions = const []});

  final String title;
  final PoolListing? trip;
  final PoolRequestStatus? status;
  final String? message;
  final String? openNote;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = trip;
    final (label, color) = switch (status) {
      PoolRequestStatus.pending => ('Waiting', const Color(0xFFF59E0B)),
      PoolRequestStatus.approved => ('Approved: sharing the ride', const Color(0xFF10B981)),
      PoolRequestStatus.declined => ('Declined', const Color(0xFFEF4444)),
      PoolRequestStatus.cancelled => ('Cancelled', const Color(0xFF94A3B8)),
      null => (openNote ?? '', const Color(0xFF38BDF8)),
    };
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_car_filled_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            ],
          ),
          if (t != null) ...[
            const SizedBox(height: 6),
            Text(
              '${t.destination} · ${shortDate(t.start)}${t.end == null ? '' : ' – ${shortDate(t.end!)}'}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (message != null && message!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('“${message!.trim()}”', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          ],
          if (label.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}
