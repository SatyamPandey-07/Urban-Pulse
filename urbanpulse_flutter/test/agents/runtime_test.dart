import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:urbanpulse/agents/runtime/agent_kind.dart';
import 'package:urbanpulse/agents/runtime/lenient_json.dart';
import 'package:urbanpulse/agents/runtime/llm_pool.dart';
import 'package:urbanpulse/agents/runtime/plan_clock.dart';
import 'package:urbanpulse/agents/runtime/report.dart';
import 'package:urbanpulse/agents/runtime/task_board.dart';
import 'package:urbanpulse/agents/runtime/task_graph.dart';
import 'package:urbanpulse/services/groq_api_client.dart';

AgentReport ok(AgentKind a, String s) =>
    AgentReport(agent: a, status: ReportStatus.done, summary: s);

TaskSpec spec(
  String id,
  AgentKind a, {
  List<String> parents = const [],
  bool optional = false,
  Duration timeout = const Duration(seconds: 5),
}) => TaskSpec(id: id, agent: a, title: id, parents: parents, optional: optional, timeout: timeout);

void main() {
  group('lenient JSON', () {
    test('plain, fenced and prose-wrapped JSON', () {
      expect(parseLenientObject('{"a": 1}'), {'a': 1});
      expect(parseLenientObject('```json\n{"a": [1, 2]}\n```'), {'a': [1, 2]});
      expect(parseLenientObject('Sure! Here it is:\n{"a": "b"}\nHope that helps.'), {'a': 'b'});
    });

    test('trailing commas, smart quotes and comments', () {
      expect(parseLenientObject('{"a": 1, "b": [1, 2,],}'), {'a': 1, 'b': [1, 2]});
      expect(parseLenientObject('{“a”: “x”}'), {'a': 'x'});
      expect(parseLenientObject('{"a": 1, // note\n "b": 2}'), {'a': 1, 'b': 2});
    });

    test('a reply cut off mid-object is closed', () {
      expect(parseLenientObject('{"hotels": [{"name": "A"}, {"name": "B"'), {
        'hotels': [
          {'name': 'A'},
          {'name': 'B'},
        ],
      });
      expect(parseLenientObject('{"a": "unterminated'), {'a': 'unterminated'});
    });

    test('braces inside strings do not confuse it', () {
      expect(parseLenientObject('x {"a": "}{", "b": 2} y'), {'a': '}{', 'b': 2});
    });

    test('lists and garbage', () {
      expect(parseLenientList('["a", "b"]'), ['a', 'b']);
      expect(parseLenientJson('no json here'), isNull);
      expect(parseLenientJson(''), isNull);
      expect(parseLenientObject('[1,2]'), isNull);
    });
  });

  group('plan clock', () {
    test('waiting on the user does not count', () {
      var now = DateTime(2026, 1, 1, 12);
      final clock = PlanClock(now: () => now, degradeAfter: const Duration(seconds: 10), deadline: const Duration(seconds: 20));
      clock.start();
      now = now.add(const Duration(seconds: 6));
      expect(clock.elapsed, const Duration(seconds: 6));
      expect(clock.degraded, isFalse);

      clock.pause();
      now = now.add(const Duration(minutes: 5));
      expect(clock.elapsed, const Duration(seconds: 6));
      clock.resume();

      now = now.add(const Duration(seconds: 5));
      expect(clock.elapsed, const Duration(seconds: 11));
      expect(clock.degraded, isTrue);
      expect(clock.expired, isFalse);
      now = now.add(const Duration(seconds: 10));
      expect(clock.expired, isTrue);
      expect(clock.remaining, Duration.zero);
    });

    test('pauses are re-entrant', () {
      var now = DateTime(2026, 1, 1);
      final clock = PlanClock(now: () => now)..start();
      clock.pause();
      clock.pause();
      now = now.add(const Duration(seconds: 4));
      clock.resume();
      now = now.add(const Duration(seconds: 4));
      expect(clock.isPaused, isTrue, reason: 'one question is still open');
      clock.resume();
      expect(clock.elapsed, Duration.zero);
    });
  });

  group('task board', () {
    late TaskGraph graph;
    late TaskBoard board;

    setUp(() {
      graph = TaskGraph();
      board = TaskBoard(graph: graph, maxConcurrent: 3);
    });

    test('a child waits for its parent', () async {
      final order = <String>[];
      final child = board.submit(spec('child', AgentKind.khoji, parents: ['parent']), (c) async {
        order.add('child');
        return ok(AgentKind.khoji, 'c');
      });
      final parent = board.submit(spec('parent', AgentKind.atithi), (c) async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        order.add('parent');
        return ok(AgentKind.atithi, 'p');
      });
      await Future.wait([child, parent]);
      expect(order, ['parent', 'child']);
      expect(graph.node('child')!.parentIds, ['parent']);
      expect(graph.isFinished, isTrue);
    });

    test('never runs more than the concurrency cap at once', () async {
      var running = 0;
      var peak = 0;
      final futures = [
        for (var i = 0; i < 8; i++)
          board.submit(spec('t$i', AgentKind.values[i % 9]), (c) async {
            running++;
            peak = peak < running ? running : peak;
            await Future<void>.delayed(const Duration(milliseconds: 30));
            running--;
            return ok(AgentKind.values[i % 9], 'done');
          }),
      ];
      await Future.wait(futures);
      expect(peak, 3);
    });

    test('a failing or throwing task never takes the others down', () async {
      final bad = board.submit(spec('bad', AgentKind.bhatkanti), (c) async => throw StateError('boom'));
      final good = board.submit(spec('good', AgentKind.atithi), (c) async => ok(AgentKind.atithi, 'fine'));
      final results = await Future.wait([bad, good]);
      expect(results[0].status, ReportStatus.failed);
      expect(results[0].summary, contains('boom'));
      expect(results[1].status, ReportStatus.done);
      expect(graph.node('bad')!.status, TaskStatus.failed);
      expect(graph.node('bad')!.error, isNotNull);
      expect(graph.node('good')!.status, TaskStatus.done);
    });

    test('a task that never finishes times out and is abandoned', () async {
      final never = Completer<AgentReport>();
      final r = await board.submit(
        spec('slow', AgentKind.khoji, timeout: const Duration(milliseconds: 200)),
        (c) => never.future,
      );
      expect(r.status, ReportStatus.failed);
      expect(r.summary, contains('timed out'));
      // A late result is ignored.
      never.complete(ok(AgentKind.khoji, 'late'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(graph.node('slow')!.status, TaskStatus.failed);
    });

    test('optional work is skipped once the plan is running long', () async {
      final late = TaskBoard(
        graph: graph,
        clock: PlanClock(degradeAfter: Duration.zero),
      );
      late.clock.start();
      var ran = false;
      final r = await late.submit(spec('extra', AgentKind.khoji, optional: true), (c) async {
        ran = true;
        return ok(AgentKind.khoji, 'x');
      });
      expect(ran, isFalse);
      expect(graph.node('extra')!.status, TaskStatus.skipped);
      expect(r.summary, contains('Skipped'));
      // Non-optional work still runs.
      final must = await late.submit(spec('must', AgentKind.atithi), (c) async => ok(AgentKind.atithi, 'y'));
      expect(must.status, ReportStatus.done);
    });

    test('delegating never deadlocks, even with a single slot', () async {
      final one = TaskBoard(graph: graph, maxConcurrent: 1);
      final r = await one.submit(spec('atithi', AgentKind.atithi), (c) async {
        final v = await c.delegate(
          spec('khoji', AgentKind.khoji),
          (cc) async => ok(AgentKind.khoji, 'verified'),
          say: 'Asked Khoji to verify',
        );
        return ok(AgentKind.atithi, 'got ${v.summary}');
      });
      expect(r.summary, 'got verified');
      expect(graph.node('khoji')!.delegatedBy, 'atithi');
      expect(graph.node('khoji')!.parentIds, ['atithi']);
      expect(graph.events.any((e) => e.kind == FeedKind.delegate), isTrue);
    });

    test('several delegating parents cannot starve their children', () async {
      final two = TaskBoard(graph: graph, maxConcurrent: 2);
      final futures = [
        for (var i = 0; i < 4; i++)
          two.submit(spec('p$i', AgentKind.atithi), (c) async {
            final v = await c.delegate(spec('c$i', AgentKind.khoji), (cc) async => ok(AgentKind.khoji, 'v$i'));
            return ok(AgentKind.atithi, v.summary);
          }),
      ];
      final results = await Future.wait(futures).timeout(const Duration(seconds: 5));
      expect(results.map((r) => r.summary), ['v0', 'v1', 'v2', 'v3']);
    });

    test('waiting for the user pauses the clock and never times the task out', () async {
      final r = await board.submit(
        spec('ask', AgentKind.yatri, timeout: const Duration(milliseconds: 250)),
        (c) async {
          final answer = await c.waitForUser(() async {
            expect(graph.node('ask')!.status, TaskStatus.waitingUser);
            expect(c.clock.isPaused, isTrue);
            await Future<void>.delayed(const Duration(milliseconds: 600));
            return 'yes';
          });
          return ok(AgentKind.yatri, 'user said $answer');
        },
      );
      expect(r.status, ReportStatus.done);
      expect(r.summary, 'user said yes');
      expect(board.clock.isPaused, isFalse);
    });

    test('regression: a task that times out while waiting on a child does not leak its slot', () async {
      final one = TaskBoard(graph: graph, maxConcurrent: 1);
      final hang = Completer<AgentReport>();
      final parent = one.submit(
        spec('parent', AgentKind.atithi, timeout: const Duration(milliseconds: 120)),
        (c) async {
          // The child outlives the parent's timeout.
          final r = await c.delegate(spec('child', AgentKind.khoji), (cc) => hang.future);
          return ok(AgentKind.atithi, 'never gets here ${r.summary}');
        },
      );
      final pr = await parent;
      expect(pr.status, ReportStatus.failed);
      expect(pr.summary, contains('timed out'));

      // Now the abandoned worker resumes, as it would when its child finishes late.
      hang.complete(ok(AgentKind.khoji, 'late'));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // The single slot is still usable, and not held by the abandoned worker.
      expect(one.debugRunning, 0);
      final next = await one
          .submit(spec('next', AgentKind.raah), (c) async => ok(AgentKind.raah, 'ran'))
          .timeout(const Duration(seconds: 2));
      expect(next.summary, 'ran');
    });

    test('regression: a hung task can still time out while another waits for the user', () async {
      final one = TaskBoard(graph: graph, maxConcurrent: 1);
      final asked = Completer<String>();
      final waiting = one.submit(spec('waiting', AgentKind.yatri, timeout: const Duration(seconds: 5)), (c) async {
        final a = await c.waitForUser(() => asked.future);
        return ok(AgentKind.yatri, 'answered $a');
      });
      // A worker that takes the only slot while the first one waits, then hangs.
      final hung = one.submit(
        spec('hung', AgentKind.khoji, timeout: const Duration(milliseconds: 150)),
        (c) => Completer<AgentReport>().future,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // The user answers: the clock resumes at once, so the hung task can expire
      // even though the waiting task now needs the slot it holds.
      asked.complete('yes');
      final results = await Future.wait([waiting, hung]).timeout(const Duration(seconds: 3));
      expect(results[0].summary, 'answered yes');
      expect(results[1].status, ReportStatus.failed);
      expect(one.clock.isPaused, isFalse);
    });

    test('regression: when a task times out its running children are stopped, not left spinning', () async {
      final hang = Completer<AgentReport>();
      final r = await board.submit(
        spec('parent', AgentKind.atithi, timeout: const Duration(milliseconds: 100)),
        (c) async {
          await c.delegate(spec('child', AgentKind.khoji), (cc) => hang.future);
          return ok(AgentKind.atithi, 'x');
        },
      );
      expect(r.status, ReportStatus.failed);
      expect(graph.node('child')!.status, TaskStatus.skipped);
      expect(graph.node('child')!.summary, contains('timed out'));
      expect(graph.isFinished, isTrue);
      // The child finishing later does not resurrect it.
      hang.complete(ok(AgentKind.khoji, 'late'));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(graph.node('child')!.status, TaskStatus.skipped);
    });

    test('the same task id is only ever run once', () async {
      var runs = 0;
      Future<AgentReport> run(TaskContext c) async {
        runs++;
        return ok(AgentKind.hisab, 'x');
      }

      await Future.wait([board.submit(spec('dup', AgentKind.hisab), run), board.submit(spec('dup', AgentKind.hisab), run)]);
      expect(runs, 1);
      expect(graph.nodes.where((n) => n.id == 'dup'), hasLength(1));
    });

    test('the feed narrates completions with their why', () async {
      await board.submit(
        const TaskSpec(id: 'a', agent: AgentKind.atithi, title: 'Find hotels', why: 'You need somewhere to sleep'),
        (c) async => ok(AgentKind.atithi, 'Found 4 hotels'),
      );
      final e = graph.events.single;
      expect((e.agent, e.text, e.why), (AgentKind.atithi, 'Found 4 hotels', 'You need somewhere to sleep'));
    });
  });

  group('key ring', () {
    test('agents spread across keys, and the slot wraps with fewer keys', () {
      final four = KeyRing(['k0', 'k1', 'k2', 'k3']);
      expect(four.preferredSlot(AgentKind.yatri), 0);
      expect(four.preferredSlot(AgentKind.hisab), 0);
      expect(four.preferredSlot(AgentKind.atithi), 1);
      expect(four.preferredSlot(AgentKind.raah), 1);
      expect(four.preferredSlot(AgentKind.bhatkanti), 2);
      expect(four.preferredSlot(AgentKind.khoji), 3);

      final two = KeyRing(['k0', 'k1']);
      expect(two.preferredSlot(AgentKind.khoji), 1);
      expect(two.preferredSlot(AgentKind.bhatkanti), 0);

      final one = KeyRing(['only']);
      for (final a in AgentKind.values) {
        expect(one.preferredSlot(a), 0);
      }
      expect(KeyRing(const []).preferredSlot(AgentKind.yatri), -1);
    });

    test('cooling and retired keys drop to the back or out', () {
      var now = DateTime(2026);
      final ring = KeyRing(['k0', 'k1', 'k2'], now: () => now);
      expect(ring.tryOrder(AgentKind.atithi).first, 1);
      ring.coolDown(1, const Duration(seconds: 5));
      expect(ring.tryOrder(AgentKind.atithi).last, 1);
      now = now.add(const Duration(seconds: 6));
      expect(ring.tryOrder(AgentKind.atithi).first, 1);
      ring.retire(1);
      expect(ring.tryOrder(AgentKind.atithi), isNot(contains(1)));
      expect(ring.usable, 2);
    });
  });

  group('llm pool', () {
    final msgs = [const GroqMessage('user', 'hi')];

    /// A scripted chat function that records what it was asked.
    (GroqChatFn, List<({String model, String key, bool json})>) scripted(
      GroqResult Function(String model, String key, bool json, int callNo) reply, {
      Duration latency = Duration.zero,
    }) {
      final calls = <({String model, String key, bool json})>[];
      Future<GroqResult> fn({
        required String model,
        required List<GroqMessage> messages,
        double temperature = 0.2,
        int maxTokens = 1024,
        bool jsonMode = false,
        String? reasoningEffort,
        Duration? requestTimeout,
        String? apiKeyOverride,
        Map<String, Object?>? extraBody,
      }) async {
        calls.add((model: model, key: apiKeyOverride!, json: jsonMode));
        if (latency > Duration.zero) await Future<void>.delayed(latency);
        return reply(model, apiKeyOverride, jsonMode, calls.length);
      }

      return (fn, calls);
    }

    test('an agent uses its own slot’s key', () async {
      final (fn, calls) = scripted((m, k, j, n) => GroqSuccess('ok', m));
      final pool = LlmPool(ring: KeyRing(['k0', 'k1', 'k2', 'k3']), chat: fn);
      await pool.ask(AgentKind.yatri, msgs);
      await pool.ask(AgentKind.atithi, msgs);
      await pool.ask(AgentKind.khoji, msgs);
      expect(calls.map((c) => c.key), ['k0', 'k1', 'k3']);
    });

    test('tiers pick the right model', () async {
      final (fn, calls) = scripted((m, k, j, n) => GroqSuccess('ok', m));
      final pool = LlmPool(ring: KeyRing(['k']), chat: fn);
      await pool.ask(AgentKind.yatri, msgs, tier: LlmTier.heavy);
      await pool.ask(AgentKind.atithi, msgs);
      await pool.ask(AgentKind.khoji, msgs, tier: LlmTier.search);
      expect(calls.map((c) => c.model), ['openai/gpt-oss-120b', 'openai/gpt-oss-20b', 'groq/compound']);
    });

    test('a rate-limited key fails over to another and then cools down', () async {
      final (fn, calls) = scripted(
        (m, k, j, n) => k == 'k1'
            ? const GroqFailure(GroqErrorKind.rateLimited, retryAfter: Duration(seconds: 30))
            : GroqSuccess('served by $k', m),
      );
      final pool = LlmPool(ring: KeyRing(['k0', 'k1']), chat: fn);

      final r = await pool.ask(AgentKind.atithi, msgs) as GroqSuccess;
      expect(r.content, 'served by k0');
      expect(calls.map((c) => c.key), ['k1', 'k0']);

      // k1 is now cooling: the next call goes straight to k0.
      calls.clear();
      await pool.ask(AgentKind.atithi, msgs);
      expect(calls.map((c) => c.key), ['k0']);
    });

    test('a rejected key is retired for good', () async {
      final (fn, calls) = scripted(
        (m, k, j, n) => k == 'bad' ? const GroqFailure(GroqErrorKind.unauthorized) : GroqSuccess('ok', m),
      );
      final pool = LlmPool(ring: KeyRing(['good', 'bad']), chat: fn);
      await pool.ask(AgentKind.atithi, msgs);
      expect(pool.ring.usable, 1);
      calls.clear();
      await pool.ask(AgentKind.atithi, msgs);
      expect(calls.map((c) => c.key), ['good']);
    });

    test('when every key is rate limited it waits once, then succeeds', () async {
      var t = DateTime(2026);
      final waits = <Duration>[];
      var failuresLeft = 2;
      final (fn, _) = scripted((m, k, j, n) {
        if (failuresLeft > 0) {
          failuresLeft--;
          return const GroqFailure(GroqErrorKind.rateLimited, retryAfter: Duration(seconds: 1));
        }
        return GroqSuccess('finally', m);
      });
      final pool = LlmPool(
        ring: KeyRing(['k0', 'k1'], now: () => t),
        chat: fn,
        delay: (d) async {
          waits.add(d);
          t = t.add(d);
        },
      );
      final r = await pool.ask(AgentKind.yatri, msgs);
      expect(r, isA<GroqSuccess>());
      expect(waits, isNotEmpty);
    });

    test('a hopeless rate limit gives up instead of waiting forever', () async {
      final (fn, _) = scripted((m, k, j, n) => const GroqFailure(GroqErrorKind.rateLimited, retryAfter: Duration(seconds: 60)));
      final pool = LlmPool(ring: KeyRing(['k0']), chat: fn, delay: (_) async {});
      final r = await pool.ask(AgentKind.yatri, msgs);
      expect(r, isA<GroqFailure>());
      expect((r as GroqFailure).kind, GroqErrorKind.rateLimited);
    });

    test('a JSON-mode rejection is retried as plain text', () async {
      final (fn, calls) = scripted(
        (m, k, j, n) => j ? const GroqFailure(GroqErrorKind.badRequest) : GroqSuccess('{"a":1}', m),
      );
      final pool = LlmPool(ring: KeyRing(['k']), chat: fn);
      final r = await pool.ask(AgentKind.atithi, msgs, json: true);
      expect(r, isA<GroqSuccess>());
      expect(calls.map((c) => c.json), [true, false]);
    });

    test('a failing model falls back to the next model in the tier', () async {
      final (fn, calls) = scripted(
        (m, k, j, n) => m == 'openai/gpt-oss-120b' ? const GroqFailure(GroqErrorKind.badRequest) : GroqSuccess('from $m', m),
      );
      final pool = LlmPool(ring: KeyRing(['k']), chat: fn);
      final r = await pool.ask(AgentKind.yatri, msgs, tier: LlmTier.heavy) as GroqSuccess;
      expect(r.content, 'from openai/gpt-oss-20b');
      expect(calls.first.model, 'openai/gpt-oss-120b');
    });

    test('no keys means a clean noKey failure, never an exception', () async {
      final pool = LlmPool(ring: KeyRing(const []), chat: scripted((m, k, j, n) => GroqSuccess('x', m)).$1);
      expect(pool.isConfigured, isFalse);
      final r = await pool.ask(AgentKind.yatri, msgs) as GroqFailure;
      expect(r.kind, GroqErrorKind.noKey);
    });

    test('a throwing transport becomes a failure result', () async {
      Future<GroqResult> boom({
        required String model,
        required List<GroqMessage> messages,
        double temperature = 0.2,
        int maxTokens = 1024,
        bool jsonMode = false,
        String? reasoningEffort,
        Duration? requestTimeout,
        String? apiKeyOverride,
        Map<String, Object?>? extraBody,
      }) async => throw StateError('socket exploded');
      final pool = LlmPool(ring: KeyRing(['k']), chat: boom);
      final r = await pool.ask(AgentKind.yatri, msgs);
      expect(r, isA<GroqFailure>());
    });

    test('per-key concurrency is capped, but different keys run in parallel', () async {
      var running = <String, int>{};
      var peakPerKey = <String, int>{};
      var peakTotal = 0;
      Future<GroqResult> fn({
        required String model,
        required List<GroqMessage> messages,
        double temperature = 0.2,
        int maxTokens = 1024,
        bool jsonMode = false,
        String? reasoningEffort,
        Duration? requestTimeout,
        String? apiKeyOverride,
        Map<String, Object?>? extraBody,
      }) async {
        final k = apiKeyOverride!;
        running[k] = (running[k] ?? 0) + 1;
        peakPerKey[k] = (peakPerKey[k] ?? 0) < running[k]! ? running[k]! : peakPerKey[k] ?? 0;
        final total = running.values.fold(0, (a, b) => a + b);
        peakTotal = peakTotal < total ? total : peakTotal;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        running[k] = running[k]! - 1;
        return GroqSuccess('ok', model);
      }

      final pool = LlmPool(ring: KeyRing(['k0', 'k1']), chat: fn, perKeyConcurrency: 2);
      await Future.wait([
        for (var i = 0; i < 5; i++) pool.ask(AgentKind.yatri, msgs), // slot 0
        for (var i = 0; i < 5; i++) pool.ask(AgentKind.atithi, msgs), // slot 1
      ]);
      expect(peakPerKey['k0'], lessThanOrEqualTo(2));
      expect(peakPerKey['k1'], lessThanOrEqualTo(2));
      expect(peakTotal, greaterThan(2), reason: 'both keys were busy at once');
    });

    test('calls are recorded for the latency report', () async {
      final (fn, _) = scripted((m, k, j, n) => GroqSuccess('ok', m));
      final pool = LlmPool(ring: KeyRing(['k']), chat: fn);
      await pool.ask(AgentKind.hisab, msgs);
      final rec = pool.calls.single;
      expect((rec.agent, rec.ok, rec.slot), (AgentKind.hisab, true, 0));
    });

    test('askJson parses a messy reply leniently', () async {
      final (fn, _) = scripted((m, k, j, n) => GroqSuccess('Here you go:\n```json\n{"a": 1,}\n```', m));
      final pool = LlmPool(ring: KeyRing(['k']), chat: fn);
      final r = await pool.askJson(AgentKind.atithi, system: 's', user: 'u');
      expect(r.map, {'a': 1});
      expect(r.ok, isTrue);
    });
  });
}
