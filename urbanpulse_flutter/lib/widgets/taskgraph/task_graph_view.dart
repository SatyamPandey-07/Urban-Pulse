import 'package:flutter/material.dart';

import '../../agents/runtime/agent_kind.dart';
import '../../agents/runtime/task_graph.dart';
import '../../core/app_colors.dart';
import 'graph_layout.dart';

/// An agent's colour, darkened on light backgrounds so coloured text stays
/// readable (the palette was designed for the dark theme).
Color agentTextColor(BuildContext context, AgentKind agent) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark ? agent.color : Color.lerp(agent.color, Colors.black, 0.42)!;
}

/// The "?" that explains why the app is doing or asking something.
class WhyButton extends StatelessWidget {
  const WhyButton({required this.agent, required this.title, required this.why, this.size = 16, super.key});

  final AgentKind agent;
  final String title;
  final String why;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Why: $title',
    child: InkResponse(
      radius: size,
      onTap: () => showWhy(context, agent: agent, title: title, why: why),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Icon(Icons.help_outline_rounded, size: size, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

/// The bottom sheet behind a "?".
Future<void> showWhy(
  BuildContext context, {
  required AgentKind agent,
  required String title,
  required String why,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(agent.icon, color: agentTextColor(context, agent)),
                const SizedBox(width: 10),
                Text(
                  agent.displayName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: agentTextColor(context, agent),
                  ),
                ),
                const SizedBox(width: 8),
                Text(agent.role, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 14),
            Text('Why is this happening?', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(why, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    ),
  );
}

/// Glyph and colour for a task status.
({IconData icon, Color color, bool spinner}) statusStyle(BuildContext context, TaskStatus status, AgentKind agent) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    TaskStatus.queued => (icon: Icons.schedule_rounded, color: scheme.outline, spinner: false),
    TaskStatus.running => (icon: Icons.sync_rounded, color: agentTextColor(context, agent), spinner: true),
    TaskStatus.waitingUser => (icon: Icons.hourglass_top_rounded, color: AppColors.solidWarning, spinner: false),
    TaskStatus.done => (icon: Icons.check_circle_rounded, color: agentTextColor(context, agent), spinner: false),
    TaskStatus.degraded => (icon: Icons.warning_amber_rounded, color: AppColors.solidWarning, spinner: false),
    TaskStatus.failed => (icon: Icons.error_outline_rounded, color: AppColors.solidError, spinner: false),
    TaskStatus.skipped => (icon: Icons.remove_circle_outline_rounded, color: scheme.outline, spinner: false),
  };
}

String statusLabel(TaskStatus s) => switch (s) {
  TaskStatus.queued => 'Waiting',
  TaskStatus.running => 'Working',
  TaskStatus.waitingUser => 'Needs your answer',
  TaskStatus.done => 'Done',
  TaskStatus.degraded => 'Done, partly estimated',
  TaskStatus.failed => 'Could not finish',
  TaskStatus.skipped => 'Skipped',
};

/// The live task graph: one pill per task in its agent's colour, joined by
/// curves. Edges pulse while a task runs. It rebuilds itself as the
/// [TaskGraph] changes, and nodes glide to their new place when the layout
/// shifts.
class TaskGraphView extends StatefulWidget {
  const TaskGraphView({
    required this.graph,
    this.metrics = const GraphMetrics(),
    this.onNodeTap,
    super.key,
  });

  final TaskGraph graph;
  final GraphMetrics metrics;
  final ValueChanged<TaskNode>? onNodeTap;

  @override
  State<TaskGraphView> createState() => _TaskGraphViewState();
}

class _TaskGraphViewState extends State<TaskGraphView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  @override
  void initState() {
    super.initState();
    widget.graph.addListener(_syncPulse);
    _syncPulse();
  }

  @override
  void didUpdateWidget(TaskGraphView old) {
    super.didUpdateWidget(old);
    if (old.graph != widget.graph) {
      old.graph.removeListener(_syncPulse);
      widget.graph.addListener(_syncPulse);
      _syncPulse();
    }
  }

  /// Pulses only while something is running: a finished plan is still, and
  /// costs no frames.
  void _syncPulse() {
    final active = widget.graph.nodes.any(
      (n) => n.status == TaskStatus.running || n.status == TaskStatus.waitingUser,
    );
    if (active && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!active && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    widget.graph.removeListener(_syncPulse);
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.graph,
      builder: (context, _) {
        final nodes = widget.graph.nodes;
        final layout = GraphLayout.compute(nodes, metrics: widget.metrics);
        if (nodes.isEmpty) return const SizedBox.shrink();
        final m = widget.metrics;
        return SizedBox(
          width: layout.size.width,
          height: layout.size.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      painter: _EdgePainter(
                        layout: layout,
                        nodes: nodes,
                        pulse: _pulse.value,
                        neutral: Theme.of(context).colorScheme.outline,
                        dark: Theme.of(context).brightness == Brightness.dark,
                      ),
                    ),
                  ),
                ),
              ),
              for (final n in nodes)
                AnimatedPositioned(
                  key: ValueKey('node-${n.id}'),
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  left: layout.positions[n.id]!.dx,
                  top: layout.positions[n.id]!.dy,
                  width: m.nodeWidth,
                  height: m.nodeHeight,
                  child: _NodeAppear(
                    child: _TaskPill(
                      node: n,
                      compact: m.nodeHeight < 56,
                      onTap: widget.onNodeTap == null ? null : () => widget.onNodeTap!(n),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A node grows and fades in when it first appears.
class _NodeAppear extends StatelessWidget {
  const _NodeAppear({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutBack,
    builder: (context, t, child) => Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
    ),
    child: child,
  );
}

class _TaskPill extends StatelessWidget {
  const _TaskPill({required this.node, required this.compact, this.onTap});

  final TaskNode node;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final agent = node.agent;
    final style = statusStyle(context, node.status, agent);
    final active = node.status == TaskStatus.running || node.status == TaskStatus.waitingUser;
    final faded = node.status == TaskStatus.queued || node.status == TaskStatus.skipped;
    final failed = node.status == TaskStatus.failed;
    final why = node.why ?? node.spec.why;
    final borderColor = failed
        ? AppColors.solidError
        : node.status == TaskStatus.waitingUser
        ? AppColors.solidWarning
        : agent.color;

    return Semantics(
      label: '${agent.displayName}: ${node.spec.title}, ${statusLabel(node.status)}',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? AppColors.surfaceCard : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: borderColor.withValues(alpha: faded ? 0.28 : (active ? 1 : 0.6)),
                  width: active ? 2.0 : 1.0,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(compact ? 8 : 10, 6, compact ? 6 : 8, 6),
                    child: Row(
                      children: [
                        Container(
                          width: compact ? 26 : 30,
                          height: compact ? 26 : 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: agent.color.withValues(alpha: faded ? 0.08 : 0.18),
                          ),
                          child: Icon(agent.icon, size: compact ? 14 : 16, color: agentTextColor(context, agent).withValues(alpha: faded ? 0.5 : 1)),
                        ),
                        SizedBox(width: compact ? 6 : 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                agent.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: compact ? 11.5 : 12.5,
                                  color: agentTextColor(context, agent).withValues(alpha: faded ? 0.55 : 1),
                                ),
                              ),
                              Text(
                                node.spec.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: compact ? 10.5 : 11.5,
                                  color: scheme.onSurfaceVariant.withValues(alpha: faded ? 0.6 : 1),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: compact ? 3 : 4),
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: style.spinner
                              ? CircularProgressIndicator(strokeWidth: 2, color: style.color)
                              : Icon(style.icon, size: 18, color: style.color),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (why != null)
            Positioned(
              right: -5,
              top: -7,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.brightness == Brightness.dark ? AppColors.surfaceElevated : scheme.surface,
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: WhyButton(agent: agent, title: node.spec.title, why: why, size: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.layout,
    required this.nodes,
    required this.pulse,
    required this.neutral,
    required this.dark,
  });

  final GraphLayout layout;
  final List<TaskNode> nodes;
  final double pulse;
  final Color neutral;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (final n in nodes) n.id: n};
    for (final n in nodes) {
      for (final parentId in n.parentIds) {
        final parent = byId[parentId];
        if (parent == null) continue;
        final path = layout.edge(parentId, n.id);
        if (path.getBounds().isEmpty) continue;

        final running = n.status == TaskStatus.running || n.status == TaskStatus.waitingUser;
        final dashed = n.status == TaskStatus.queued || n.status == TaskStatus.failed || n.status == TaskStatus.skipped;
        final color = switch (n.status) {
          TaskStatus.failed => AppColors.solidError,
          TaskStatus.skipped || TaskStatus.queued => neutral,
          _ => n.agent.color,
        };
        final alpha = switch (n.status) {
          TaskStatus.queued => 0.35,
          TaskStatus.skipped => 0.25,
          TaskStatus.running || TaskStatus.waitingUser => 0.95,
          TaskStatus.failed => 0.7,
          _ => 0.6,
        };
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = running ? 2.6 : 1.8
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: alpha);

        if (dashed) {
          _drawDashed(canvas, path, paint);
        } else {
          canvas.drawPath(path, paint);
        }

        if (running) {
          final m = path.computeMetrics().first;
          final t = m.getTangentForOffset(m.length * pulse);
          if (t != null) {
            canvas.drawCircle(t.position, 7, Paint()..color = color.withValues(alpha: 0.25));
            canvas.drawCircle(t.position, 3.6, Paint()..color = color);
          }
        }
      }
    }
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + 6).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}

/// Convenience: a small legend chip for an agent.
class AgentChip extends StatelessWidget {
  const AgentChip({required this.agent, super.key});

  final AgentKind agent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: agent.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: agent.color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(agent.icon, size: 14, color: agentTextColor(context, agent)),
          const SizedBox(width: 5),
          Text(
            agent.displayName,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: agentTextColor(context, agent),
            ),
          ),
        ],
      ),
    );
  }
}
