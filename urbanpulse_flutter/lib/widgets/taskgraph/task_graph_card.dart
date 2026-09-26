import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../agents/runtime/agent_kind.dart';
import '../../agents/runtime/plan_clock.dart';
import '../../agents/runtime/task_graph.dart';
import '../../core/app_colors.dart';
import 'agent_feed.dart';
import 'graph_layout.dart';
import 'task_graph_view.dart';

String _elapsedLabel(Duration d) {
  final s = d.inSeconds;
  return s < 60 ? '${s}s' : '${s ~/ 60}m ${s % 60}s';
}

/// A one-line summary of where the plan is.
String planStatusLine(TaskGraph graph) {
  final nodes = graph.nodes;
  if (nodes.isEmpty) return 'Getting started';
  if (graph.hasWaitingUser) return 'Waiting for your answer';
  final done = nodes.where((n) => n.status.isFinished).length;
  if (graph.isFinished) {
    final failed = nodes.where((n) => n.status == TaskStatus.failed).length;
    return failed == 0
        ? 'All $done tasks finished'
        : '${done - failed} of ${nodes.length} tasks finished, $failed could not complete';
  }
  final running = nodes.where((n) => n.status == TaskStatus.running).length;
  return '$done of ${nodes.length} tasks done${running > 0 ? ' · $running working' : ''}';
}

/// The inline card in the chat: a compact live graph, the latest feed lines
/// and a stopwatch. Tap it to open the full-screen view.
class TaskGraphCard extends StatefulWidget {
  const TaskGraphCard({required this.graph, this.clock, this.title = 'Planning your trip', super.key});

  final TaskGraph graph;

  /// Drives the stopwatch (which excludes time spent waiting on the user).
  final PlanClock? clock;
  final String title;

  @override
  State<TaskGraphCard> createState() => _TaskGraphCardState();
}

class _TaskGraphCardState extends State<TaskGraphCard> {
  final _scroll = ScrollController();
  Timer? _tick;
  int _lastColumns = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !widget.graph.isFinished) setState(() {});
    });
    widget.graph.addListener(_followGraph);
  }

  @override
  void dispose() {
    widget.graph.removeListener(_followGraph);
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Keep the newest column in view as the graph grows to the right.
  void _followGraph() {
    final cols = GraphLayout.compute(widget.graph.nodes, metrics: GraphMetrics.compact).columns;
    if (cols == _lastColumns) return;
    _lastColumns = cols;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _expand() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => TaskGraphPage(graph: widget.graph, clock: widget.clock, title: widget.title),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final graph = widget.graph;
    final dark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceDark : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: dark ? AppColors.surfaceBorder : scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            onTap: _expand,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
              child: ListenableBuilder(
                listenable: graph,
                builder: (context, _) => Row(
                  children: [
                    Icon(Icons.hub_rounded, size: 20, color: AgentKind.yatri.color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          Text(
                            planStatusLine(graph),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: graph.hasWaitingUser ? AppColors.solidWarning : scheme.onSurfaceVariant,
                              fontWeight: graph.hasWaitingUser ? FontWeight.w700 : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.clock != null && widget.clock!.started)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          _elapsedLabel(widget.clock!.elapsed),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    IconButton(
                      tooltip: 'Open full view',
                      onPressed: _expand,
                      icon: const Icon(Icons.open_in_full_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: 176,
            child: ListenableBuilder(
              listenable: graph,
              builder: (context, _) {
                final layout = GraphLayout.compute(graph.nodes, metrics: GraphMetrics.compact);
                return SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(vertical: math.max(0, (176 - layout.size.height) / 2)),
                  child: TaskGraphView(graph: graph, metrics: GraphMetrics.compact),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 12),
            child: AgentFeed(graph: graph, maxEvents: 4),
          ),
        ],
      ),
    );
  }
}

/// The full-screen “mission control”: the whole graph (pan and zoom), the
/// complete feed and an agent legend. Side by side on wide screens.
class TaskGraphPage extends StatefulWidget {
  const TaskGraphPage({required this.graph, this.clock, this.title = 'Planning your trip', super.key});

  final TaskGraph graph;
  final PlanClock? clock;
  final String title;

  @override
  State<TaskGraphPage> createState() => _TaskGraphPageState();
}

class _TaskGraphPageState extends State<TaskGraphPage> {
  final _feedScroll = ScrollController();
  final _transform = TransformationController();
  Timer? _tick;
  int _lastEvents = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !widget.graph.isFinished) setState(() {});
    });
    widget.graph.addListener(_followFeed);
  }

  @override
  void dispose() {
    widget.graph.removeListener(_followFeed);
    _tick?.cancel();
    _feedScroll.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _followFeed() {
    final n = widget.graph.events.length;
    if (n == _lastEvents) return;
    _lastEvents = n;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_feedScroll.hasClients) return;
      _feedScroll.animateTo(
        _feedScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _showNode(TaskNode n) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [AgentChip(agent: n.agent), const SizedBox(width: 10), Text(statusLabel(n.status), style: theme.textTheme.labelLarge)]),
              const SizedBox(height: 12),
              Text(n.spec.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              if (n.summary != null) ...[const SizedBox(height: 6), Text(n.summary!, style: theme.textTheme.bodyMedium)],
              if ((n.why ?? n.spec.why) != null) ...[
                const SizedBox(height: 10),
                Text('Why', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text((n.why ?? n.spec.why)!, style: theme.textTheme.bodyMedium),
              ],
              if (n.elapsed != null) ...[
                const SizedBox(height: 10),
                Text('Took ${_elapsedLabel(n.elapsed!)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final graph = widget.graph;

    Widget graphPane(BoxConstraints c) {
      final layout = GraphLayout.compute(graph.nodes);
      final fit = layout.size.width == 0 ? 1.0 : (c.maxWidth / layout.size.width).clamp(0.45, 1.0);
      return InteractiveViewer(
        transformationController: _transform,
        constrained: false,
        minScale: 0.4,
        maxScale: 2.2,
        boundaryMargin: const EdgeInsets.all(120),
        child: Transform.scale(
          alignment: Alignment.topLeft,
          scale: fit,
          child: TaskGraphView(graph: graph, onNodeTap: _showNode),
        ),
      );
    }

    final feed = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('What the agents are doing', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ),
        Expanded(
          child: AgentFeed(graph: graph, controller: _feedScroll, padding: const EdgeInsets.fromLTRB(16, 4, 12, 16)),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Close', onPressed: () => Navigator.of(context).pop()),
        actions: [
          if (widget.clock != null && widget.clock!.started)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text(_elapsedLabel(widget.clock!.elapsed), style: theme.textTheme.labelLarge)),
            ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: graph,
          builder: (context, _) => LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= 900;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(planStatusLine(graph), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final a in AgentKind.values)
                          Padding(padding: const EdgeInsets.only(right: 8), child: AgentChip(agent: a)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: wide
                        ? Row(
                            children: [
                              Expanded(child: LayoutBuilder(builder: (context, gc) => graphPane(gc))),
                              const VerticalDivider(width: 1),
                              SizedBox(width: 380, child: feed),
                            ],
                          )
                        : Column(
                            children: [
                              Expanded(flex: 5, child: LayoutBuilder(builder: (context, gc) => graphPane(gc))),
                              const Divider(height: 1),
                              Expanded(flex: 4, child: feed),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
