import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../agents/runtime/agent_toolkit.dart';
import '../core/formatting.dart';
import '../models/itinerary/itinerary.dart';
import '../models/trip_brief.dart';
import '../services/itinerary_pdf.dart';
import '../state/itinerary_edit_controller.dart';
import '../widgets/itinerary/access_audit_view.dart';
import '../widgets/itinerary/budget_breakdown.dart';
import '../widgets/itinerary/day_view.dart';
import '../widgets/itinerary/edit_chat_panel.dart';
import '../widgets/itinerary/slot_actions_sheet.dart';
import '../widgets/itinerary/green_view.dart';
import '../widgets/itinerary/trip_overview.dart';
import 'weather_twin_screen.dart';

/// The finished plan from the multi-agent planner: a map and timeline for each
/// day, the budget line by line, and the trip overview with its sources.
class PlanItineraryScreen extends StatefulWidget {
  const PlanItineraryScreen({
    required this.itinerary,
    this.onSave,
    this.saved = false,
    this.tileLayer,
    this.toolkit,
    this.onChanged,
    super.key,
  });

  final Itinerary itinerary;

  /// The agents' tools. When given (and the plan has its trip details) the plan
  /// can be edited with Yatri; without it the screen is read-only.
  final AgentToolkit? toolkit;

  /// Called with the new plan after every accepted edit (or undo), to keep the
  /// saved copy in step.
  final Future<void> Function(Itinerary)? onChanged;

  /// Saves the trip to My Trips. Null hides the button.
  final Future<void> Function()? onSave;
  final bool saved;

  /// Replaces the OpenStreetMap tiles (tests only).
  final Widget? tileLayer;

  @override
  State<PlanItineraryScreen> createState() => _PlanItineraryScreenState();
}

class _PlanItineraryScreenState extends State<PlanItineraryScreen> {
  late bool _saved = widget.saved;
  bool _saving = false;
  bool _pdfBusy = false;
  bool _panelOpen = false;
  ItineraryEditController? _edit;

  /// The plan as it is now (after any edits).
  Itinerary get it => _edit?.current ?? widget.itinerary;

  @override
  void initState() {
    super.initState();
    final tk = widget.toolkit;
    if (tk != null && widget.itinerary.brief != null && widget.itinerary.days.isNotEmpty) {
      _edit = ItineraryEditController(toolkit: tk, itinerary: widget.itinerary, onChanged: widget.onChanged)..addListener(_editChanged);
    }
  }

  @override
  void dispose() {
    _edit?.removeListener(_editChanged);
    _edit?.dispose();
    super.dispose();
  }

  void _editChanged() {
    if (!mounted) return;
    setState(() {});
    // A question from an agent (e.g. which hotel) must reach the traveller even
    // if the panel was closed after starting a change from a stop.
    if (_edit!.pending != null && !_panelOpen) _openPanel();
  }

  Future<void> _openPanel() async {
    final c = _edit;
    if (c == null || _panelOpen) return;
    _panelOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(height: MediaQuery.of(ctx).size.height * 0.88, child: EditChatPanel(controller: c, onClose: () => Navigator.of(ctx).pop())),
      ),
    );
    _panelOpen = false;
  }

  void _slotTapped(ItinerarySlot slot, int day) {
    final c = _edit;
    if (c == null || c.busy || slot.refId == null) return;
    showSlotActions(context, controller: c, slot: slot, day: day, onRunStarted: _openPanel);
  }

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

  Future<void> _sharePdf() async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final bytes = await ItineraryPdf.build(it);
      final name = '${it.destination.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_itinerary.pdf';
      await Printing.sharePdf(bytes: bytes, filename: name);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create the PDF. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = <(String, IconData, Widget)>[
      (
        'Days',
        Icons.calendar_month_rounded,
        _DaysTab(
          itinerary: it,
          tileLayer: widget.tileLayer,
          onSlotTap: _edit == null ? null : _slotTapped,
          locked: it.snapshot?.pins ?? const {},
        ),
      ),
      ('Budget', Icons.account_balance_wallet_outlined, _Padded(child: BudgetBreakdown(budget: it.budget))),
      if (it.audit != null && it.audit!.items.isNotEmpty)
        (
          'Access',
          Icons.accessible_forward_rounded,
          _Padded(
            child: AccessAuditView(
              audit: it.audit!,
              needs: {for (final n in it.brief?.accessibilityNeeds ?? const <AccessibilityNeed>{}) if (n != AccessibilityNeed.none) n},
            ),
          ),
        ),
      if (it.green != null) ('Green', Icons.eco_outlined, _Padded(child: GreenView(green: it.green!))),
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
            if (_edit != null && (_edit!.canUndo || _edit!.canRedo)) ...[
              IconButton(tooltip: 'Undo the last change', onPressed: _edit!.canUndo ? _edit!.undo : null, icon: const Icon(Icons.undo_rounded)),
              if (_edit!.canRedo) IconButton(tooltip: 'Redo', onPressed: _edit!.redo, icon: const Icon(Icons.redo_rounded)),
            ],
            IconButton(
              tooltip: 'Weather what-if (digital twin)',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WeatherTwinScreen(itinerary: it))),
              icon: const Icon(Icons.thunderstorm_outlined),
            ),
            IconButton(
              tooltip: 'Share or print as PDF',
              onPressed: _pdfBusy ? null : _sharePdf,
              icon: _pdfBusy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined),
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
        floatingActionButton: _edit == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _openPanel,
                icon: Icon(_edit!.busy ? Icons.hourglass_top_rounded : Icons.auto_fix_high_rounded),
                label: Text(_edit!.busy ? 'Yatri is working…' : 'Edit with Yatri'),
              ),
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
  const _DaysTab({required this.itinerary, this.tileLayer, this.onSlotTap, this.locked = const {}});

  final Itinerary itinerary;
  final Widget? tileLayer;
  final void Function(ItinerarySlot slot, int day)? onSlotTap;
  final Set<String> locked;

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
                        width: 96,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary : scheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('Day ${d.number}', style: theme.textTheme.labelLarge?.copyWith(color: selected ? scheme.onPrimary : scheme.onSurface, fontWeight: FontWeight.w800)),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(shortDate(d.date), style: theme.textTheme.labelSmall?.copyWith(color: selected ? scheme.onPrimary : scheme.onSurfaceVariant)),
                            ),
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
                child: DayView(
                  day: day,
                  hotel: it.hotel,
                  needs: needs,
                  tileLayer: widget.tileLayer,
                  locked: widget.locked,
                  onSlotTap: widget.onSlotTap == null ? null : (slot) => widget.onSlotTap!(slot, day.number),
                ),
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
