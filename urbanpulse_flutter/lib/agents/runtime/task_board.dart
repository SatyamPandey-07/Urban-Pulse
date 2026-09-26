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

  /// Set when the task timed out: the board has moved on, so this worker must
  /// never take a slot again (it would leak one nothing releases).
  bool _abandoned = false;

  AgentKind get agent => spec.agent;
  PlanClock get clock => _board.clock;

  /// True once the plan is running long: skip nice-to-haves.
  bool get degraded => _board.clock.degraded;

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

  /// Marks this task as waiting for the user while [ask] runs, and stops the
  /// plan clock so the wait does not count against the time budget.
  Future<T> waitForUser<T>(Future<T> Function() ask) async {
    _board.graph.update(node.id, (n) => n.status = TaskStatus.waitingUser);
    _board.clock.pause();
    try {
      return await _board._withoutSlot(this, () async {
        try {
          return await ask();
        } finally {
          // Resume the moment the user answers, NOT after this task wins a
          // slot back: a hung task holding that slot can only time out while
          // the clock runs, so resuming later would deadlock.
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
/// run at once, enforces per-task timeouts and turns every failure into a
/// [AgentReport.failed] instead of an exception, so one bad worker can never
/// take the plan down.
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

  /// Tasks that timed out, and the tasks stopped because an ancestor did. A
  /// stopped task's late result is ignored so the graph never shows work that
  /// nobody is waiting for.
  final Set<String> _abandonedIds = {};
  final Set<String> _stopped = {};
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

    // A child whose delegating task has already timed out is not needed.
    if (node.delegatedBy != null && _abandonedIds.contains(node.delegatedBy)) {
      _stopped.add(node.id);
      graph.update(node.id, (n) {
        n.status = TaskStatus.skipped;
        n.endedAt = DateTime.now();
        n.summary = 'Stopped: the task that asked for this timed out';
      });
      return _reports[node.id] = AgentReport(
        agent: spec.agent,
        status: ReportStatus.done,
        summary: 'Stopped: the task that asked for this timed out',
      );
    }

    if (_cancelled || (spec.optional && clock.degraded)) {
      return _finish(
        node,
        AgentReport(
          agent: spec.agent,
          status: ReportStatus.done,
          summary: _cancelled ? 'Cancelled' : 'Skipped to save time',
        ),
        status: TaskStatus.skipped,
      );
    }

    final ctx = TaskContext._(spec, node, this);
    await _acquire();
    ctx._holdsSlot = true;
    // Stopped while waiting for a slot (its delegating task timed out): do not
    // start it, and do not overwrite the "stopped" status.
    if (_stopped.contains(node.id)) {
      ctx._holdsSlot = false;
      _release();
      return _reports[node.id]!;
    }
    try {
      clock.start();
      graph.update(node.id, (n) {
        n.status = TaskStatus.running;
        n.startedAt = DateTime.now();
      });

      AgentReport report;
      try {
        report = await _withActiveTimeout(
          spec,
          () => run(ctx),
          onTimeout: () {
            ctx._abandoned = true;
            _abandonedIds.add(node.id);
            _stopDescendants(node.id, 'Stopped: ${spec.title} timed out');
          },
        );
      } catch (e) {
        report = AgentReport.failed(spec.agent, '${spec.title} failed: $e');
      }
      return _finish(node, report);
    } finally {
      // Release only if the task still holds its slot: a worker that timed
      // out while waiting on a child or the user already gave it up.
      if (ctx._holdsSlot) {
        ctx._holdsSlot = false;
        _release();
      }
    }
  }

  /// A timeout that only counts time on the plan clock, so waiting for the
  /// user (which pauses the clock) never times a task out. A worker that
  /// overruns is abandoned: its late result is ignored.
  Future<AgentReport> _withActiveTimeout(
    TaskSpec spec,
    Future<AgentReport> Function() body, {
    void Function()? onTimeout,
  }) {
    final done = Completer<AgentReport>();
    final startedAt = clock.elapsed;

    Future.sync(body).then(
      (r) {
        if (!done.isCompleted) done.complete(r);
      },
      onError: (Object e, StackTrace _) {
        if (!done.isCompleted) {
          done.complete(AgentReport.failed(spec.agent, '${spec.title} failed: $e'));
        }
      },
    );

    final tick = Duration(
      milliseconds: (spec.timeout.inMilliseconds ~/ 4).clamp(20, 250),
    );
    Timer.periodic(tick, (timer) {
      if (done.isCompleted) {
        timer.cancel();
        return;
      }
      if (clock.elapsed - startedAt >= spec.timeout) {
        timer.cancel();
        onTimeout?.call();
        done.complete(
          AgentReport.failed(
            spec.agent,
            '${spec.title} timed out after ${spec.timeout.inSeconds}s',
          ),
        );
      }
    });
    return done.future;
  }

  /// Marks every unfinished task delegated (directly or indirectly) by [id] as
  /// stopped. They may still be running in the background, but nothing waits
  /// for them any more.
  void _stopDescendants(String id, String reason) {
    for (final child in graph.nodes.where((n) => n.delegatedBy == id).toList()) {
      if (child.status.isFinished && !_stopped.contains(child.id)) continue;
      if (_stopped.add(child.id)) {
        _reports[child.id] = AgentReport(
          agent: child.agent,
          status: ReportStatus.done,
          summary: reason,
        );
        graph.update(child.id, (n) {
          n.status = TaskStatus.skipped;
          n.endedAt = DateTime.now();
          n.summary = reason;
        });
      }
      _stopDescendants(child.id, reason);
    }
  }

  AgentReport _finish(TaskNode node, AgentReport report, {TaskStatus? status}) {
    // Already stopped because an ancestor timed out: ignore the late result.
    if (_stopped.contains(node.id)) return _reports[node.id]!;
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
    // An abandoned worker holds no slot and must not take one.
    if (ctx._abandoned || !ctx._holdsSlot) return wait();
    ctx._holdsSlot = false;
    _release();
    try {
      return await wait();
    } finally {
      if (!ctx._abandoned) {
        await _acquire();
        if (ctx._abandoned) {
          // Timed out while queued for the slot: hand it straight back.
          _release();
        } else {
          ctx._holdsSlot = true;
        }
      }
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
