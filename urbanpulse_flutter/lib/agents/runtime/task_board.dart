import 'dart:async';
import 'dart:collection';

import 'agent_kind.dart';
import 'plan_clock.dart';
import 'report.dart';
import 'task_graph.dart';

typedef TaskRunner = Future<AgentReport> Function(TaskContext ctx);

/// What a worker sees while it runs: its task, the clock, and the ways to talk
/// to the user-facing graph.
class TaskContext {
  TaskContext._(this.spec, this.node, this._board);

  final TaskSpec spec;
  final TaskNode node;
  final TaskBoard _board;

  /// Whether this task currently occupies one of the board's concurrency slots.
  bool _holdsSlot = false;

  AgentKind get agent => spec.agent;
  PlanClock get clock => _board.clock;

  /// True once the traveller has stopped the plan. The only reason a worker
  /// cuts its work short: time never is.
  bool get cancelled => _board._cancelled;

  /// Narrates something into the feed under the graph.
  void say(String text, {String? why, FeedKind kind = FeedKind.info}) {
    _board.graph.addEvent(
      FeedEvent(agent: agent, text: text, why: why, kind: kind, nodeId: node.id),
    );
  }

  /// Hands a sub-task to another agent (Atithi → Khoji). The child becomes a
  /// node in the graph with an edge from this task.
  Future<AgentReport> delegate(TaskSpec child, TaskRunner run, {String? say}) {
    if (say != null) {
      this.say(say, why: child.why, kind: FeedKind.delegate);
    }
    // Give the slot up while waiting, or a few delegating parents could fill
    // every slot and starve the children they are waiting for.
    return _board._withoutSlot(
      this,
      () => _board.submit(child, run, delegatedBy: spec.id),
    );
  }

  /// Marks this task as waiting for the user while [ask] runs, and pauses the
  /// plan clock so the wait is not counted as the system's own time.
  Future<T> waitForUser<T>(Future<T> Function() ask) async {
    _board.graph.update(node.id, (n) => n.status = TaskStatus.waitingUser);
    _board.clock.pause();
    try {
      return await _board._withoutSlot(this, () async {
        try {
          return await ask();
        } finally {
          _board.clock.resume();
        }
      });
    } finally {
      _board.graph.update(node.id, (n) {
        if (n.status == TaskStatus.waitingUser) n.status = TaskStatus.running;
      });
    }
  }
}

/// Schedules tasks as a dependency graph: waits for parents, limits how many
/// run at once and turns every failure into an [AgentReport.failed] instead of
/// an exception, so one bad worker can never take the plan down. There are no
/// time limits: a task ends when its worker returns (every network call has
/// its own I/O timeout) or when the traveller stops the plan.
class TaskBoard {
  TaskBoard({
    required this.graph,
    PlanClock? clock,
    this.maxConcurrent = 6,
  }) : clock = clock ?? PlanClock();

  final TaskGraph graph;
  final PlanClock clock;
  final int maxConcurrent;

  final Map<String, Future<AgentReport>> _futures = {};
  final Map<String, AgentReport> _reports = {};

  final Queue<Completer<void>> _waiters = Queue();
  int _running = 0;
  bool _cancelled = false;

  /// How many slots are in use, for diagnostics and tests.
  int get debugRunning => _running;

  /// Finished reports by task id.
  Map<String, AgentReport> get reports => Map.unmodifiable(_reports);

  AgentReport? report(String id) => _reports[id];

  /// Stops scheduling new work; running tasks see [TaskContext.cancelled].
  void cancel() => _cancelled = true;

  /// Registers [spec] in the graph immediately (so the user sees it queued) and
  /// returns its eventual report. Never throws.
  Future<AgentReport> submit(
    TaskSpec spec,
    TaskRunner run, {
    String? delegatedBy,
  }) {
    final existing = _futures[spec.id];
    if (existing != null) return existing;

    final node = TaskNode(spec, delegatedBy: delegatedBy);
    graph.addNode(node);
    final future = _execute(node, run);
    _futures[spec.id] = future;
    return future;
  }

  Future<AgentReport> _execute(TaskNode node, TaskRunner run) async {
    final spec = node.spec;

    // Wait for the tasks this one depends on. One turn of the event loop first,
    // so parents submitted in the same breath as their children are known.
    // (A parent that never appears counts as done rather than blocking forever.)
    if (spec.parents.isNotEmpty) await Future<void>.delayed(Duration.zero);
    for (final p in spec.parents) {
      final f = _futures[p];
      if (f != null) await f;
    }

    if (_cancelled) {
      return _finish(
        node,
        AgentReport(agent: spec.agent, status: ReportStatus.done, summary: 'Cancelled'),
        status: TaskStatus.skipped,
      );
    }

    final ctx = TaskContext._(spec, node, this);
    await _acquire();
    ctx._holdsSlot = true;
    try {
      clock.start();
      graph.update(node.id, (n) {
        n.status = TaskStatus.running;
        n.startedAt = DateTime.now();
      });

      AgentReport report;
      try {
        report = await run(ctx);
      } catch (e) {
        report = AgentReport.failed(spec.agent, '${spec.title} failed: $e');
      }
      return _finish(node, report);
    } finally {
      // Release only if the task still holds its slot.
      if (ctx._holdsSlot) {
        ctx._holdsSlot = false;
        _release();
      }
    }
  }

  AgentReport _finish(TaskNode node, AgentReport report, {TaskStatus? status}) {
    _reports[node.id] = report;
    final resolved =
        status ??
        switch (report.status) {
          ReportStatus.done => TaskStatus.done,
          ReportStatus.degraded => TaskStatus.degraded,
          ReportStatus.needsUser => TaskStatus.waitingUser,
          ReportStatus.failed => TaskStatus.failed,
        };
    graph.update(node.id, (n) {
      n.status = resolved;
      n.endedAt = DateTime.now();
      n.summary = report.summary;
      n.why = report.why ?? n.spec.why;
      if (report.status == ReportStatus.failed) n.error = report.summary;
    });
    if (resolved != TaskStatus.skipped) {
      graph.addEvent(
        FeedEvent(
          agent: report.agent,
          text: report.summary,
          why: report.why ?? node.spec.why,
          kind: report.status == ReportStatus.failed ? FeedKind.warn : FeedKind.found,
          nodeId: node.id,
        ),
      );
    }
    return report;
  }

  /// Runs [wait] with this task's concurrency slot released, then takes a slot
  /// again. For tasks blocked on something other than CPU/network work.
  Future<T> _withoutSlot<T>(TaskContext ctx, Future<T> Function() wait) async {
    if (!ctx._holdsSlot) return wait();
    ctx._holdsSlot = false;
    _release();
    try {
      return await wait();
    } finally {
      await _acquire();
      ctx._holdsSlot = true;
    }
  }

  Future<void> _acquire() {
    if (_running < maxConcurrent) {
      _running++;
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      // Hand the slot straight to the next waiter.
      _waiters.removeFirst().complete();
    } else {
      _running--;
    }
  }
}
