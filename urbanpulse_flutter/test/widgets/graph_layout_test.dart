import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/runtime/agent_kind.dart';
import 'package:urbanpulse/agents/runtime/task_graph.dart';
import 'package:urbanpulse/widgets/taskgraph/graph_layout.dart';

TaskNode node(String id, AgentKind a, {List<String> parents = const [], String? delegatedBy}) =>
    TaskNode(TaskSpec(id: id, agent: a, title: id, parents: parents), delegatedBy: delegatedBy);

void main() {
  const m = GraphMetrics();

  test('an empty graph has no size', () {
    final l = GraphLayout.compute(const []);
    expect(l.positions, isEmpty);
    expect(l.size.isEmpty, isTrue);
    expect(l.columns, 0);
  });

  test('a node sits one column right of its deepest parent', () {
    final nodes = [
      node('yatri', AgentKind.yatri),
      node('atithi', AgentKind.atithi, parents: ['yatri']),
      node('bhatkanti', AgentKind.bhatkanti, parents: ['yatri']),
      node('khoji', AgentKind.khoji, delegatedBy: 'atithi'),
      node('hisab', AgentKind.hisab, parents: ['atithi', 'bhatkanti']),
    ];
    final l = GraphLayout.compute(nodes);
    expect(l.depth, {'yatri': 0, 'atithi': 1, 'bhatkanti': 1, 'khoji': 2, 'hisab': 2});
    expect(l.columns, 3);
    final xs = {for (final e in l.positions.entries) e.key: e.value.dx};
    expect(xs['yatri'], m.padding);
    expect(xs['atithi']! - xs['yatri']!, m.nodeWidth + m.columnGap);
    expect(xs['khoji'], xs['hisab']);
  });

  test('nodes in a column never overlap and stay inside the reported size', () {
    final nodes = [
      node('y', AgentKind.yatri),
      for (var i = 0; i < 6; i++) node('w$i', AgentKind.values[1 + i], parents: ['y']),
    ];
    final l = GraphLayout.compute(nodes);
    final col = [for (var i = 0; i < 6; i++) l.positions['w$i']!]..sort((a, b) => a.dy.compareTo(b.dy));
    for (var i = 1; i < col.length; i++) {
      expect(col[i].dy - col[i - 1].dy, greaterThanOrEqualTo(m.nodeHeight + m.rowGap));
    }
    for (final p in l.positions.values) {
      expect(p.dx + m.nodeWidth, lessThanOrEqualTo(l.size.width));
      expect(p.dy + m.nodeHeight, lessThanOrEqualTo(l.size.height));
      expect(p.dx, greaterThanOrEqualTo(0));
      expect(p.dy, greaterThanOrEqualTo(0));
    }
  });

  test('a short column is centred against the tallest one', () {
    final nodes = [
      node('y', AgentKind.yatri),
      for (var i = 0; i < 3; i++) node('w$i', AgentKind.values[1 + i], parents: ['y']),
    ];
    final l = GraphLayout.compute(nodes);
    final yMid = l.positions['y']!.dy + m.nodeHeight / 2;
    final ws = [for (var i = 0; i < 3; i++) l.positions['w$i']!.dy];
    final wMid = (ws.first + ws.last + m.nodeHeight) / 2;
    expect(yMid, closeTo(wMid, 0.001));
  });

  test('children are ordered under their parents to keep edges from crossing', () {
    final nodes = [
      node('a', AgentKind.atithi),
      node('b', AgentKind.bhatkanti),
      // Declared in the opposite order to their parents.
      node('bChild', AgentKind.raah, parents: ['b']),
      node('aChild', AgentKind.khoji, parents: ['a']),
    ];
    final l = GraphLayout.compute(nodes);
    expect(l.positions['aChild']!.dy, lessThan(l.positions['bChild']!.dy));
  });

  test('layout is stable: adding a later node does not move existing ones sideways', () {
    final base = [node('y', AgentKind.yatri), node('a', AgentKind.atithi, parents: ['y'])];
    final before = GraphLayout.compute(base).positions;
    final after = GraphLayout.compute([...base, node('k', AgentKind.khoji, delegatedBy: 'a')]).positions;
    expect(after['y']!.dx, before['y']!.dx);
    expect(after['a']!.dx, before['a']!.dx);
  });

  test('unknown parents are ignored and cycles cannot hang it', () {
    final l = GraphLayout.compute([node('a', AgentKind.atithi, parents: ['ghost'])]);
    expect(l.depth['a'], 0);

    final cyc = GraphLayout.compute([
      node('x', AgentKind.atithi, parents: ['y']),
      node('y', AgentKind.raah, parents: ['x']),
    ]);
    expect(cyc.positions.keys, unorderedEquals(['x', 'y']));
    expect(cyc.size.width.isFinite, isTrue);
  });

  test('edges run from the parent’s right side to the child’s left side', () {
    final nodes = [node('y', AgentKind.yatri), node('a', AgentKind.atithi, parents: ['y'])];
    final l = GraphLayout.compute(nodes);
    final b = l.edge('y', 'a').getBounds();
    final p = l.positions['y']!;
    final c = l.positions['a']!;
    expect(b.left, closeTo(p.dx + m.nodeWidth, 0.5));
    expect(b.right, closeTo(c.dx, 0.5));
    expect(l.edge('y', 'nope').getBounds().isEmpty, isTrue);
  });

  test('the compact metrics are smaller than the default', () {
    expect(GraphMetrics.compact.nodeWidth, lessThan(m.nodeWidth));
    expect(GraphMetrics.compact.nodeHeight, lessThan(m.nodeHeight));
  });
}
