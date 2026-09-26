import 'package:flutter/foundation.dart';

import 'agent_kind.dart';

enum TaskStatus {
  queued,
  running,
  waitingUser,
  done,
  degraded,
  failed,
  skipped;

  bool get isFinished =>
      this == done || this == degraded || this == failed || this == skipped;
}

/// What one agent is asked to do.
class TaskSpec {
  const TaskSpec({
    required this.id,
    required this.agent,
    required this.title,
    this.goal = '',
    this.why,
    this.params = const {},
    this.parents = const [],
  });

  final String id;
  final AgentKind agent;

  /// Short label for the graph node, e.g. "Find hotels".
  final String title;

  /// The instruction handed to the worker.
  final String goal;

  /// Why this task exists, shown behind the “?”.
  final String? why;
  final Map<String, Object?> params;

  /// Task ids that must finish first (drawn as edges).
  final List<String> parents;
}

/// One node of the graph the user watches. Mutated only by the board.
class TaskNode {
  TaskNode(this.spec, {this.delegatedBy});

  final TaskSpec spec;

  /// The task that created this one (e.g. Atithi asking Khoji to verify).
  final String? delegatedBy;

  TaskStatus status = TaskStatus.queued;
  DateTime? startedAt;
  DateTime? endedAt;
  String? summary;
  String? why;
  String? error;

  String get id => spec.id;
  AgentKind get agent => spec.agent;

  Duration? get elapsed {
    final s = startedAt;
    if (s == null) return null;
    return (endedAt ?? DateTime.now()).difference(s);
  }

  /// Every task this node points back to: its declared parents plus the task
  /// that delegated it.
  List<String> get parentIds => [
    ...spec.parents,
    if (delegatedBy != null && !spec.parents.contains(delegatedBy)) delegatedBy!,
  ];
}

enum FeedKind { allocate, found, delegate, ask, negotiate, verify, decide, warn, info }

/// One line of the narrated feed under the graph.
class FeedEvent {
  FeedEvent({
    required this.agent,
    required this.text,
    this.why,
    this.kind = FeedKind.info,
    this.nodeId,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  final AgentKind agent;
  final String text;

  /// Behind the “?”.
  final String? why;
  final FeedKind kind;
  final String? nodeId;
  final DateTime time;
}

/// The live task graph plus the feed narrating it. This is the single model the
/// UI observes; the [TaskBoard] is the only writer.
class TaskGraph extends ChangeNotifier {
  final List<TaskNode> _nodes = [];
  final List<FeedEvent> _events = [];
  bool _disposed = false;

  List<TaskNode> get nodes => List.unmodifiable(_nodes);
  List<FeedEvent> get events => List.unmodifiable(_events);

  TaskNode? node(String id) {
    for (final n in _nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  bool get isFinished => _nodes.isNotEmpty && _nodes.every((n) => n.status.isFinished);

  bool get hasWaitingUser => _nodes.any((n) => n.status == TaskStatus.waitingUser);

  void addNode(TaskNode node) {
    _nodes.add(node);
    _notify();
  }

  void addEvent(FeedEvent event) {
    _events.add(event);
    _notify();
  }

  /// Applies [change] to a node and notifies listeners.
  void update(String id, void Function(TaskNode node) change) {
    final n = node(id);
    if (n == null) return;
    change(n);
    _notify();
  }

  void clear() {
    _nodes.clear();
    _events.clear();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
