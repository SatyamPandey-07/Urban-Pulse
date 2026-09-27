import 'dart:async';

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
  const TaskGraphCard({required this.graph, this.clock, this.title = 'Planning your trip', this.onStop, super.key});

  final TaskGraph graph;

  /// Stops the plan and shows what is ready. The agents otherwise keep going
  /// until the whole trip is planned, however long that takes.
  final VoidCallback? onStop;

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


  void _expand() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => TaskGraphPage(
          graph: widget.graph,
          clock: widget.clock,
          title: widget.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final graph = widget.graph;
    final dark = theme.brightness == Brightness.dark;
    final screenH = MediaQuery.of(context).size.height;
    final targetHeight = (screenH * 0.54).clamp(350.0, 540.0);

    return Container(
      height: targetHeight,
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dark ? AppColors.surfaceBorder : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
            child: ListenableBuilder(
              listenable: graph,
              builder: (context, _) => Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AgentKind.yatri.color.withValues(alpha: dark ? 0.2 : 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.hub_rounded, size: 18, color: AgentKind.yatri.color),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: _expand,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              planStatusLine(graph),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: graph.hasWaitingUser ? AppColors.solidWarning : scheme.onSurfaceVariant,
                                fontWeight: graph.hasWaitingUser ? FontWeight.w700 : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (widget.clock != null && widget.clock!.started) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: dark ? AppColors.surfaceElevated : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _elapsedLabel(widget.clock!.elapsed),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (widget.onStop != null && !graph.isFinished)
                    IconButton(
                      tooltip: 'Stop and show what is ready',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: const EdgeInsets.all(4),
                      onPressed: widget.onStop,
                      icon: const Icon(Icons.stop_circle_outlined, size: 19),
                    ),
                  IconButton(
                    tooltip: 'Full screen mission control',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: const EdgeInsets.all(4),
                    onPressed: _expand,
                    icon: const Icon(Icons.open_in_full_rounded, size: 19),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListenableBuilder(
              listenable: graph,
              builder: (context, _) {
                return SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: TaskGraphView(graph: graph, metrics: GraphMetrics.compact),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 6),
            child: AgentFeed(graph: graph, maxEvents: 3),
          ),
          InkWell(
            onTap: _expand,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.03),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_full_rounded, size: 13, color: AgentKind.yatri.color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Mission Control (Full screen pan & zoom)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AgentKind.yatri.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AgentChip(agent: n.agent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      statusLabel(n.status),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                n.spec.title,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (n.summary != null) ...[
                const SizedBox(height: 6),
                Text(n.summary!, style: theme.textTheme.bodyMedium),
              ],
              if ((n.why ?? n.spec.why) != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Why',
                  style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                Text((n.why ?? n.spec.why)!, style: theme.textTheme.bodyMedium),
              ],
              if (n.elapsed != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Took ${_elapsedLabel(n.elapsed!)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            'What the agents are doing',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Expanded(
          child: AgentFeed(graph: graph, controller: _feedScroll, padding: const EdgeInsets.fromLTRB(16, 4, 12, 16)),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Close', onPressed: () => Navigator.of(context).pop()),
        actions: [
          if (widget.clock != null && widget.clock!.started)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.surfaceElevated
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _elapsedLabel(widget.clock!.elapsed),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
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
                          child: Text(
                            planStatusLine(graph),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: graph.hasWaitingUser ? AppColors.solidWarning : theme.colorScheme.onSurfaceVariant,
                              fontWeight: graph.hasWaitingUser ? FontWeight.w700 : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 36,
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
