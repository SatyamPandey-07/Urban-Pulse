import 'dart:ui';

import '../../agents/runtime/task_graph.dart';

class GraphMetrics {
  const GraphMetrics({
    this.nodeWidth = 156,
    this.nodeHeight = 58,
    this.columnGap = 46,
    this.rowGap = 14,
    this.padding = 14,
  });

  final double nodeWidth;
  final double nodeHeight;
  final double columnGap;
  final double rowGap;
  final double padding;

  static const compact = GraphMetrics(nodeWidth: 138, nodeHeight: 52, columnGap: 34, rowGap: 10, padding: 10);
}

/// Where each node of the task graph goes: a layered left-to-right layout in
/// which a node sits one column to the right of its deepest parent. Pure and
/// deterministic, so the graph does not jump around as tasks are added.
class GraphLayout {
  const GraphLayout({required this.positions, required this.depth, required this.size, required this.metrics});

  /// Top-left corner of every node, keyed by task id.
  final Map<String, Offset> positions;
  final Map<String, int> depth;
  final Size size;
  final GraphMetrics metrics;

  int get columns => depth.isEmpty ? 0 : depth.values.reduce((a, b) => a > b ? a : b) + 1;

  static GraphLayout compute(List<TaskNode> nodes, {GraphMetrics metrics = const GraphMetrics()}) {
    if (nodes.isEmpty) {
      return GraphLayout(positions: const {}, depth: const {}, size: Size.zero, metrics: metrics);
    }

    final byId = {for (final n in nodes) n.id: n};
    final depth = <String, int>{};

    // Depth = one more than the deepest known parent. The loop is bounded so a
    // malformed (cyclic) graph cannot hang the UI.
    for (var pass = 0; pass <= nodes.length; pass++) {
      var changed = false;
      for (final n in nodes) {
        final parents = [for (final p in n.parentIds) if (byId.containsKey(p)) p];
        final d = parents.isEmpty
            ? 0
            : 1 + parents.map((p) => depth[p] ?? 0).reduce((a, b) => a > b ? a : b);
        if (depth[n.id] != d) {
          depth[n.id] = d;
          changed = true;
        }
      }
      if (!changed) break;
    }
    // A cycle never settles; cap the depth so the drawing stays finite.
    for (final e in depth.entries.toList()) {
      if (e.value > nodes.length) depth[e.key] = nodes.length;
    }

    final columnCount = depth.values.reduce((a, b) => a > b ? a : b) + 1;
    final columns = List.generate(columnCount, (_) => <TaskNode>[]);
    for (final n in nodes) {
      columns[depth[n.id]!].add(n);
    }

    // One barycentre pass: order each column by the average row of its parents
    // so edges cross less.
    final row = <String, double>{};
    for (var c = 0; c < columnCount; c++) {
      final col = columns[c];
      if (c > 0) {
        double key(TaskNode n) {
          final ps = [for (final p in n.parentIds) if (row.containsKey(p)) row[p]!];
          return ps.isEmpty ? double.infinity : ps.reduce((a, b) => a + b) / ps.length;
        }

        final index = {for (var i = 0; i < col.length; i++) col[i].id: i};
        col.sort((a, b) {
          final byKey = key(a).compareTo(key(b));
          return byKey != 0 ? byKey : index[a.id]!.compareTo(index[b.id]!);
        });
      }
      for (var i = 0; i < col.length; i++) {
        row[col[i].id] = i.toDouble();
      }
    }

    final tallest = columns.map((c) => c.length).reduce((a, b) => a > b ? a : b);
    final step = metrics.nodeHeight + metrics.rowGap;
    final positions = <String, Offset>{};
    for (var c = 0; c < columnCount; c++) {
      final col = columns[c];
      final offset = (tallest - col.length) * step / 2;
      for (var i = 0; i < col.length; i++) {
        positions[col[i].id] = Offset(
          metrics.padding + c * (metrics.nodeWidth + metrics.columnGap),
          metrics.padding + offset + i * step,
        );
      }
    }

    final size = Size(
      metrics.padding * 2 + columnCount * metrics.nodeWidth + (columnCount - 1) * metrics.columnGap,
      metrics.padding * 2 + tallest * metrics.nodeHeight + (tallest - 1) * metrics.rowGap,
    );
    return GraphLayout(positions: positions, depth: depth, size: size, metrics: metrics);
  }

  /// The edge from [parent] to [child] as a smooth curve between their sides.
  Path edge(String parent, String child) {
    final p = positions[parent];
    final c = positions[child];
    final path = Path();
    if (p == null || c == null) return path;
    final start = Offset(p.dx + metrics.nodeWidth, p.dy + metrics.nodeHeight / 2);
    final end = Offset(c.dx, c.dy + metrics.nodeHeight / 2);
    final mid = (end.dx - start.dx) * 0.5;
    path
      ..moveTo(start.dx, start.dy)
      ..cubicTo(start.dx + mid, start.dy, end.dx - mid, end.dy, end.dx, end.dy);
    return path;
  }
}
