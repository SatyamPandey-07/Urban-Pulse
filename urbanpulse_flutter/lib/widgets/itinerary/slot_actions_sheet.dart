import 'package:flutter/material.dart';

import '../../agents/editor/edit_ops.dart';
import '../../core/formatting.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../state/itinerary_edit_controller.dart';

/// What can be done with one stop of the plan: why it is there, replace it,
/// move it to another day, remove it or lock it where it is. Each choice goes
/// through the same edit agent as typing the request.
Future<void> showSlotActions(
  BuildContext context, {
  required ItineraryEditController controller,
  required ItinerarySlot slot,
  required int day,
  required VoidCallback onRunStarted,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (context) => _SlotActions(controller: controller, slot: slot, day: day, onRunStarted: onRunStarted),
  );
}

class _SlotActions extends StatefulWidget {
  const _SlotActions({required this.controller, required this.slot, required this.day, required this.onRunStarted});

  final ItineraryEditController controller;
  final ItinerarySlot slot;
  final int day;
  final VoidCallback onRunStarted;

  @override
  State<_SlotActions> createState() => _SlotActionsState();
}

enum _Mode { menu, why, replace, move }

class _SlotActionsState extends State<_SlotActions> {
  _Mode _mode = _Mode.menu;

  ItinerarySlot get slot => widget.slot;
  String get id => slot.refId!;
  ItineraryEditController get c => widget.controller;
  bool get locked => c.current.snapshot?.pins.contains(id) ?? false;
  Hotspot? get place => c.current.snapshot?.pool.where((h) => h.id == id).firstOrNull;

  void _run(List<EditOp> ops, String label) {
    Navigator.of(context).pop();
    widget.onRunStarted();
    c.run(ops, label: label);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = slot.title;

    Widget tile(IconData icon, String text, VoidCallback onTap, {String? sub, Color? color}) => ListTile(
      leading: Icon(icon, color: color ?? scheme.primary),
      title: Text(text),
      subtitle: sub == null ? null : Text(sub),
      onTap: onTap,
    );

    final body = switch (_mode) {
      _Mode.menu => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tile(Icons.help_outline_rounded, 'Why is this here?', () => setState(() => _mode = _Mode.why)),
          tile(Icons.swap_horiz_rounded, 'Replace with something else', () => setState(() => _mode = _Mode.replace)),
          tile(Icons.event_repeat_rounded, 'Move to another day', () => setState(() => _mode = _Mode.move)),
          tile(locked ? Icons.lock_open_rounded : Icons.lock_rounded, locked ? 'Unlock' : 'Lock it where it is', () => _run([LockStopOp(id, lock: !locked)], locked ? 'Unlock $title' : 'Lock $title'),
              sub: locked ? null : 'Later changes will not move it'),
          tile(Icons.delete_outline_rounded, 'Remove from the plan', () => _run([RemoveStopOp(id)], 'Remove $title'), color: scheme.error),
        ],
      ),
      _Mode.why => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_whyText(), style: theme.textTheme.bodyMedium),
            if (place?.access.isNotEmpty ?? false) ...[
              const SizedBox(height: 12),
              for (final e in place!.access.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('${e.key.label}: ${e.value.level.label}${e.value.detail.isEmpty ? '' : ' — ${e.value.detail}'}', style: theme.textTheme.bodySmall),
                ),
            ],
            TextButton(onPressed: () => setState(() => _mode = _Mode.menu), child: const Text('Back')),
          ],
        ),
      ),
      _Mode.replace => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Replace it with…', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, wish) in const [
                  ('Anything nearby', ''),
                  ('Something indoors', 'something indoors'),
                  ('Something outdoors', 'something outdoors'),
                  ('Something cheaper', 'something cheaper or free'),
                  ('A viewpoint', 'a viewpoint'),
                  ('Heritage', 'heritage or history'),
                  ('Nature', 'nature'),
                  ('Local food', 'local food'),
                ])
                  ActionChip(label: Text(label), onPressed: () => _run([SwapStopOp(id, wish: wish.isEmpty ? null : wish)], 'Replace $title${wish.isEmpty ? '' : ' with $wish'}')),
              ],
            ),
            TextButton(onPressed: () => setState(() => _mode = _Mode.menu), child: const Text('Back')),
          ],
        ),
      ),
      _Mode.move => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Move to which day?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in c.current.days)
                  if (d.number != widget.day) ActionChip(label: Text('Day ${d.number} · ${shortDate(d.date)}'), onPressed: () => _run([MoveStopOp(id, d.number)], 'Move $title to day ${d.number}')),
              ],
            ),
            TextButton(onPressed: () => setState(() => _mode = _Mode.menu), child: const Text('Back')),
          ],
        ),
      ),
    };

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Day ${widget.day} · ${clock12(slot.start)}', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
          body,
        ],
      ),
    );
  }

  String _whyText() {
    final h = place;
    final why = (h?.why.isNotEmpty ?? false) ? h!.why : (slot.note ?? '');
    final bits = <String>[
      if (why.isNotEmpty) why else 'It was chosen as one of the best fits for your trip.',
      if (h != null) 'Importance for this trip: ${(h.score * 100).round()} of 100.',
      if (h?.openingHours != null) 'Opening hours: ${h!.openingHours}.',
      if (h != null && h.provenance.source.isNotEmpty) 'Found via ${h.provenance.source}.',
    ];
    return bits.join(' ');
  }
}
