import 'package:flutter/material.dart';

import '../core/formatting.dart';
import '../models/itinerary/itinerary.dart';
import '../models/trip_brief.dart';
import '../widgets/common.dart';
import '../widgets/itinerary/budget_breakdown.dart';
import '../widgets/itinerary/day_view.dart';
import '../widgets/itinerary/trip_overview.dart';

/// The finished plan from the multi-agent planner: a map and timeline for each
/// day, the budget line by line, and the trip overview with its sources.
class PlanItineraryScreen extends StatefulWidget {
  const PlanItineraryScreen({
    required this.itinerary,
    this.onSave,
    this.onSendToWatch,
    this.saved = false,
    this.tileLayer,
    super.key,
  });

  final Itinerary itinerary;

  /// Saves the trip to My Trips. Null hides the button.
  final Future<void> Function()? onSave;

  /// Re-publishes the plan to the paired Garmin watch. The planner already does
  /// this automatically when the agents finish; this is the retry for a send
  /// that happened while the server was unreachable. Null hides the button.
  final Future<bool> Function()? onSendToWatch;
  final bool saved;

  /// Replaces the OpenStreetMap tiles (tests only).
  final Widget? tileLayer;

  @override
  State<PlanItineraryScreen> createState() => _PlanItineraryScreenState();
}

class _PlanItineraryScreenState extends State<PlanItineraryScreen> {
  late bool _saved = widget.saved;
  bool _saving = false;
  bool _sendingToWatch = false;

  Itinerary get it => widget.itinerary;

  Future<void> _save() async {
    if (_saved || _saving || widget.onSave == null) return;
    setState(() => _saving = true);
    try {
      await widget.onSave!();
      if (mounted) setState(() => _saved = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendToWatch() async {
    if (_sendingToWatch || widget.onSendToWatch == null) return;
    setState(() => _sendingToWatch = true);
    try {
      final sent = await widget.onSendToWatch!();
      if (mounted) {
        showToast(
          context,
          sent ? 'Sent to your Garmin watch' : 'Could not reach the watch sync server',
        );
      }
    } finally {
      if (mounted) setState(() => _sendingToWatch = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = <(String, IconData, Widget)>[
      ('Days', Icons.calendar_month_rounded, _DaysTab(itinerary: it, tileLayer: widget.tileLayer)),
      ('Budget', Icons.account_balance_wallet_outlined, _Padded(child: BudgetBreakdown(budget: it.budget))),
      ('Trip', Icons.info_outline_rounded, _Padded(child: TripOverview(itinerary: it))),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${it.destination} · ${it.dayCount} day${it.dayCount == 1 ? '' : 's'}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(dateRangeLabel(it.start, it.end), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          actions: [
            if (widget.onSendToWatch != null)
              IconButton(
                tooltip: 'Send to Garmin watch',
                onPressed: _sendingToWatch ? null : _sendToWatch,
                icon: _sendingToWatch
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.watch_outlined),
              ),
            if (widget.onSave != null)
              IconButton(
                tooltip: _saved ? 'Saved to My Trips' : 'Save to My Trips',
                onPressed: _saved ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_saved ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined),
              ),
          ],
          bottom: TabBar(
            tabs: [for (final t in tabs) Tab(text: t.$1, icon: Icon(t.$2, size: 20))],
          ),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$3]),
      ),
    );
  }
}

class _Padded extends StatelessWidget {
  const _Padded({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [child]),
    ),
  );
}

class _DaysTab extends StatefulWidget {
  const _DaysTab({required this.itinerary, this.tileLayer});

  final Itinerary itinerary;
  final Widget? tileLayer;

  @override
  State<_DaysTab> createState() => _DaysTabState();
}

class _DaysTabState extends State<_DaysTab> with AutomaticKeepAliveClientMixin {
  int _day = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final it = widget.itinerary;
    final theme = Theme.of(context);
    final needs = {for (final n in it.brief?.accessibilityNeeds ?? const <AccessibilityNeed>{}) if (n != AccessibilityNeed.none) n};
    if (it.days.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('There are no days in this plan.')));
    }
    final day = it.days[_day.clamp(0, it.days.length - 1)];
    final visits = it.days.fold<int>(0, (s, d) => s + d.slots.where((x) => x.kind == SlotKind.visit).length);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _Stat(Icons.place_rounded, '$visits places'),
                _Stat(Icons.account_balance_wallet_outlined, rupees(it.budget.totalInr)),
                if (it.chosenTransport != null) _Stat(it.chosenTransport!.walking ? Icons.directions_walk_rounded : Icons.directions_transit_rounded, it.chosenTransport!.mode.label),
                if (it.green != null) _Stat(Icons.eco_rounded, '${fixed(it.green!.co2Kg, 0)} kg CO₂'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: it.days.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final d = it.days[i];
                  final selected = i == _day;
                  final scheme = theme.colorScheme;
                  return Semantics(
                    button: true,
                    selected: selected,
                    label: 'Day ${d.number}, ${shortDate(d.date)}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => setState(() => _day = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 78,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary : scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Day ${d.number}', style: theme.textTheme.labelLarge?.copyWith(color: selected ? scheme.onPrimary : scheme.onSurface, fontWeight: FontWeight.w800)),
                            Text(shortDate(d.date), style: theme.textTheme.labelSmall?.copyWith(color: selected ? scheme.onPrimary : scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey(day.number),
                child: DayView(day: day, hotel: it.hotel, needs: needs, tileLayer: widget.tileLayer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
