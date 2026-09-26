import 'package:flutter/material.dart';

import '../../agents/runtime/task_graph.dart';
import 'task_graph_view.dart';

/// The narrated log under the graph: “Yatri allocated tasks to Atithi,
/// Bhatkanti and Safar (?)”. Agent names carry their colour; the rest is
/// neutral grey. Each line can have a “?” explaining why.
class AgentFeed extends StatelessWidget {
  const AgentFeed({
    required this.graph,
    this.maxEvents,
    this.controller,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final TaskGraph graph;

  /// Show only the latest N lines (the compact card); null shows everything.
  final int? maxEvents;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: graph,
      builder: (context, _) {
        final all = graph.events;
        final shown = maxEvents == null || all.length <= maxEvents! ? all : all.sublist(all.length - maxEvents!);
        if (shown.isEmpty) return const SizedBox.shrink();

        if (maxEvents != null) {
          return Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final e in shown) FeedLine(event: e)],
            ),
          );
        }
        return ListView.builder(
          controller: controller,
          padding: padding,
          itemCount: shown.length,
          itemBuilder: (context, i) => FeedLine(event: shown[i]),
        );
      },
    );
  }
}

class FeedLine extends StatelessWidget {
  const FeedLine({required this.event, super.key});

  final FeedEvent event;

  IconData get _icon => switch (event.kind) {
    FeedKind.allocate => Icons.arrow_right_alt_rounded,
    FeedKind.found => Icons.check_rounded,
    FeedKind.delegate => Icons.subdirectory_arrow_right_rounded,
    FeedKind.ask => Icons.forum_outlined,
    FeedKind.negotiate => Icons.compare_arrows_rounded,
    FeedKind.verify => Icons.fact_check_outlined,
    FeedKind.decide => Icons.gavel_rounded,
    FeedKind.warn => Icons.warning_amber_rounded,
    FeedKind.info => Icons.circle,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final agentColor = agentTextColor(context, event.agent);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 6), child: child),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(
                _icon,
                size: event.kind == FeedKind.info ? 6 : 15,
                color: event.kind == FeedKind.warn ? theme.colorScheme.error : agentColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: event.agent.displayName,
                      style: TextStyle(fontWeight: FontWeight.w800, color: agentColor),
                    ),
                    TextSpan(text: ' ${event.text}', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
                style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
              ),
            ),
            if (event.why != null)
              WhyButton(agent: event.agent, title: event.text, why: event.why!, size: 15),
          ],
        ),
      ),
    );
  }
}
