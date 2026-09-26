import 'package:flutter/material.dart';

import '../../agents/editor/itinerary_diff.dart';
import '../../agents/runtime/agent_kind.dart';
import '../../core/app_colors.dart';
import '../../state/itinerary_edit_controller.dart';
import '../taskgraph/task_graph_card.dart';
import '../yatri/answer_view.dart';
import '../yatri/chat_bubbles.dart';

/// "Edit with Yatri": a small chat about the finished plan. Quick chips, free
/// text, the open question when an agent needs a decision, a live view of the
/// agents working, and a diff of every change with Undo.
class EditChatPanel extends StatefulWidget {
  const EditChatPanel({required this.controller, this.onClose, super.key});

  final ItineraryEditController controller;
  final VoidCallback? onClose;

  @override
  State<EditChatPanel> createState() => _EditChatPanelState();
}

class _EditChatPanelState extends State<EditChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _seen = 0;

  ItineraryEditController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (c.messages.length != _seen || c.pending != null || c.busy) {
      _seen = c.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
        }
      });
    }
  }

  void _send() {
    final t = _input.text;
    if (t.trim().isEmpty || c.busy) return;
    _input.clear();
    c.send(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final yatri = AgentKind.yatri;
    final canChip = !c.busy && c.pending == null;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Icon(yatri.icon, color: yatri.color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Edit with Yatri', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          c.current.version == 1 ? 'Your plan, as first made' : 'Version ${c.current.version} · ${c.current.edits.length} change${c.current.edits.length == 1 ? '' : 's'}',
                          style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(tooltip: 'Undo the last change', onPressed: c.canUndo ? c.undo : null, icon: const Icon(Icons.undo_rounded)),
                  IconButton(tooltip: 'Redo', onPressed: c.canRedo ? c.redo : null, icon: const Icon(Icons.redo_rounded)),
                  if (widget.onClose != null) IconButton(tooltip: 'Close', onPressed: widget.onClose, icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  if (c.messages.isEmpty)
                    const AgentBubble(
                      text: 'Tell me what to change. I can lighten a day, move, replace, add or remove a place, find a different hotel, change how you travel, add or remove a day, or make the trip greener or cheaper. You can also tap any stop in the plan.',
                      agent: AgentKind.yatri,
                    ),
                  for (final m in c.messages) ...[_message(context, m), const SizedBox(height: 12)],
                  if (c.busy && c.graph != null) ...[
                    TaskGraphCard(graph: c.graph!, clock: c.clock, title: 'Updating your plan', onStop: c.stop),
                    const SizedBox(height: 12),
                  ],
                  if (c.pending != null) _question(context),
                ],
              ),
            ),
            if (canChip && c.chips.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: c.chips.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final chip = c.chips[i];
                    return ActionChip(
                      avatar: Icon(chip.icon, size: 16),
                      label: Text(chip.label),
                      onPressed: () => c.run(chip.ops, label: chip.label),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !c.busy && c.pending == null,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 400,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: c.busy ? 'Working on it…' : (c.pending != null ? 'Answer the question above' : 'e.g. “More rest on day 2” or “swap the museum for something outdoors”'),
                        hintMaxLines: 2,
                        counterText: '',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  c.busy
                      ? IconButton.filledTonal(tooltip: 'Stop', onPressed: c.stop, icon: const Icon(Icons.stop_rounded))
                      : IconButton.filled(tooltip: 'Send', onPressed: c.pending == null ? _send : null, icon: const Icon(Icons.arrow_upward_rounded)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(BuildContext context, EditMessage m) {
    if (m.fromUser) return UserBubble(text: m.text);
    return AgentBubble(
      text: m.text,
      agent: AgentKind.yatri,
      child: m.diff == null || m.diff!.isEmpty ? null : DiffCard(diff: m.diff!, onUndo: c.canUndo ? c.undo : null),
    );
  }

  Widget _question(BuildContext context) {
    final q = c.pending!;
    final scheme = Theme.of(context).colorScheme;
    return AgentBubble(
      text: q.displayText,
      agent: AgentKind.yatri,
      why: q.why,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(20), border: Border.all(color: scheme.outlineVariant)),
        child: buildAnswerView(q, onSubmit: c.answer, key: ValueKey(q.id)),
      ),
    );
  }
}

/// What an edit changed, in plain lines, with Undo.
class DiffCard extends StatelessWidget {
  const DiffCard({required this.diff, this.onUndo, super.key});

  final ItineraryDiff diff;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = diff.lines();
    if (lines.isEmpty) return const SizedBox.shrink();

    (IconData, Color) style(String line) {
      if (line.startsWith('Added')) return (Icons.add_circle_outline_rounded, AppColors.primaryGreenDark);
      if (line.startsWith('Removed')) return (Icons.remove_circle_outline_rounded, scheme.error);
      if (line.startsWith('Moved')) return (Icons.swap_horiz_rounded, AgentKind.raah.color);
      if (line.startsWith('Stay')) return (Icons.hotel_rounded, AgentKind.atithi.color);
      if (line.startsWith('Journey')) return (Icons.directions_transit_rounded, AgentKind.safar.color);
      if (line.startsWith('Cost')) return (Icons.account_balance_wallet_outlined, AgentKind.hisab.color);
      if (line.startsWith('CO')) return (Icons.eco_rounded, AgentKind.hariyali.color);
      if (line.startsWith('Access')) return (Icons.accessible_forward_rounded, AgentKind.saksham.color);
      return (Icons.event_rounded, scheme.primary);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16), border: Border.all(color: scheme.outlineVariant)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What changed', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final l in lines.take(12))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(style(l).$1, size: 15, color: style(l).$2),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
          if (lines.length > 12) Text('…and ${lines.length - 12} more', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          if (onUndo != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(onPressed: onUndo, icon: const Icon(Icons.undo_rounded, size: 16), label: const Text('Undo')),
            ),
        ],
      ),
    );
  }
}
