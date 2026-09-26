import 'dart:async';
import 'dart:collection';

import '../../core/config.dart';
import '../../services/groq_api_client.dart';
import 'agent_kind.dart';
import 'lenient_json.dart';

/// How much model each job needs.
enum LlmTier {
  /// Yatri's decisions: quality matters, calls are few.
  heavy,

  /// Worker tasks: extraction, ranking, estimates. Fast and cheap.
  light,

  /// `groq/compound`: the model with built-in web search.
  search,
}

typedef GroqChatFn =
    Future<GroqResult> Function({
      required String model,
      required List<GroqMessage> messages,
      double temperature,
      int maxTokens,
      bool jsonMode,
      String? reasoningEffort,
      Duration? requestTimeout,
      String? apiKeyOverride,
      Map<String, Object?>? extraBody,
    });

/// What agents call to reach a language model. Tests script it; the app uses
/// [LlmPool].
abstract interface class AgentLlm {
  /// Whether at least one real key is available.
  bool get isConfigured;

  Future<GroqResult> ask(
    AgentKind agent,
    List<GroqMessage> messages, {
    LlmTier tier,
    bool json,
    double temperature,
    int maxTokens,
    Duration? timeout,
    Map<String, Object?>? extraBody,
  });
}

/// Convenience over [AgentLlm.ask] for the common "reply with JSON" case.
extension AgentLlmJson on AgentLlm {
  /// Asks for JSON and parses it leniently. [value] is null when the call
  /// failed or the reply held nothing usable; [failure] says why in the first
  /// case.
  Future<JsonReply> askJson(
    AgentKind agent, {
    required String system,
    required String user,
    List<GroqMessage> history = const [],
    LlmTier tier = LlmTier.light,
    double temperature = 0.2,
    int maxTokens = 1400,
    Duration? timeout,
  }) async {
    final result = await ask(
      agent,
      [GroqMessage('system', system), ...history, GroqMessage('user', user)],
      tier: tier,
      json: true,
      temperature: temperature,
      maxTokens: maxTokens,
      timeout: timeout,
    );
    switch (result) {
      case GroqSuccess(:final content):
        return JsonReply(parseLenientJson(content), content, null);
      case GroqFailure():
        return JsonReply(null, '', result);
    }
  }
}

class JsonReply {
  const JsonReply(this.value, this.raw, this.failure);

  final Object? value;
  final String raw;
  final GroqFailure? failure;

  bool get ok => value != null;

  Map<String, dynamic>? get map => value is Map<String, dynamic> ? value as Map<String, dynamic> : null;

  List<dynamic>? get list => value is List<dynamic> ? value as List<dynamic> : null;
}

/// Groq keys, with agents spread across them (2-3 agents per key). When there
/// are fewer keys than slots the slot wraps, so a single key is simply shared.
/// A key that is rate limited cools down and a key that is rejected is retired
/// for the session, with its agents failing over to the others.
class KeyRing {
  KeyRing(List<String> keys, {DateTime Function()? now})
    : _keys = List.unmodifiable(keys),
      _now = now ?? DateTime.now;

  factory KeyRing.fromConfig() => KeyRing(AppConfig.groqKeys);

  final List<String> _keys;
  final DateTime Function() _now;
  final Map<int, DateTime> _coolUntil = {};
  final Set<int> _dead = {};

  int get length => _keys.length;

  bool get isEmpty => _keys.isEmpty;

  /// Keys still usable (not rejected).
  int get usable => _keys.length - _dead.length;

  String key(int slot) => _keys[slot];

  int preferredSlot(AgentKind a) => _keys.isEmpty ? -1 : a.keySlot % _keys.length;

  void coolDown(int slot, Duration d) {
    _coolUntil[slot] = _now().add(d);
  }

  void retire(int slot) => _dead.add(slot);

  Duration cooldownLeft(int slot) {
    final until = _coolUntil[slot];
    if (until == null) return Duration.zero;
    final left = until.difference(_now());
    return left.isNegative ? Duration.zero : left;
  }

  bool isAvailable(int slot) => !_dead.contains(slot) && cooldownLeft(slot) == Duration.zero;

  /// The slots to try for [a], best first: its own slot, then the others that
  /// are not cooling down, then cooling ones by soonest recovery.
  List<int> tryOrder(AgentKind a) {
    if (isEmpty) return const [];
    final own = preferredSlot(a);
    final all = [for (var i = 0; i < _keys.length; i++) i]..removeWhere(_dead.contains);
    all.sort((x, y) {
      int rank(int s) => s == own ? 0 : 1;
      final byAvail = (isAvailable(x) ? 0 : 1).compareTo(isAvailable(y) ? 0 : 1);
      if (byAvail != 0) return byAvail;
      final byOwn = rank(x).compareTo(rank(y));
      if (byOwn != 0) return byOwn;
      return cooldownLeft(x).compareTo(cooldownLeft(y));
    });
    return all;
  }
}

/// One record per model call, for the latency report.
class LlmCallRecord {
  const LlmCallRecord({
    required this.agent,
    required this.model,
    required this.slot,
    required this.duration,
    required this.ok,
    this.failure,
  });

  final AgentKind agent;
  final String model;
  final int slot;
  final Duration duration;
  final bool ok;
  final GroqErrorKind? failure;
}

class _Semaphore {
  _Semaphore(this.max);

  final int max;
  int _held = 0;
  final Queue<Completer<void>> _queue = Queue();

  Future<void> acquire() {
    if (_held < max) {
      _held++;
      return Future.value();
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      _queue.removeFirst().complete();
    } else {
      _held--;
    }
  }
}

/// The shared door to Groq for every agent. It owns the parallelism: a cap of
/// concurrent calls per key, cool-downs and failover on rate limits, model
/// fallback, and one retry for the usual transient failures. It never throws.
class LlmPool implements AgentLlm {
  LlmPool({
    required this.ring,
    GroqChatFn? chat,
    this.perKeyConcurrency = 3,
    this.maxRateLimitWait = const Duration(seconds: 6),
    Future<void> Function(Duration)? delay,
  }) : _chat = chat ?? _defaultChat,
       _delay = delay ?? Future<void>.delayed;

  factory LlmPool.fromConfig() => LlmPool(ring: KeyRing.fromConfig());

  final KeyRing ring;
  final int perKeyConcurrency;

  /// The longest we will sit out a rate limit before giving up on a call.
  final Duration maxRateLimitWait;
  final GroqChatFn _chat;
  final Future<void> Function(Duration) _delay;

  final Map<int, _Semaphore> _gates = {};
  final List<LlmCallRecord> _calls = [];

  static const models = <LlmTier, List<String>>{
    LlmTier.heavy: ['openai/gpt-oss-120b', 'openai/gpt-oss-20b', 'qwen/qwen3.8-27b'],
    LlmTier.light: ['openai/gpt-oss-20b', 'qwen/qwen3.8-27b', 'openai/gpt-oss-120b'],
    LlmTier.search: ['groq/compound', 'openai/gpt-oss-20b', 'qwen/qwen3.8-27b'],
  };

  List<LlmCallRecord> get calls => List.unmodifiable(_calls);

  @override
  bool get isConfigured => !ring.isEmpty && ring.usable > 0;

  static Future<GroqResult> _defaultChat({
    required String model,
    required List<GroqMessage> messages,
    double temperature = 0.2,
    int maxTokens = 1024,
    bool jsonMode = false,
    String? reasoningEffort,
    Duration? requestTimeout,
    String? apiKeyOverride,
    Map<String, Object?>? extraBody,
  }) => GroqApiClient.chat(
    model: model,
    messages: messages,
    temperature: temperature,
    maxTokens: maxTokens,
    jsonMode: jsonMode,
    reasoningEffort: reasoningEffort,
    requestTimeout: requestTimeout,
    apiKeyOverride: apiKeyOverride,
    extraBody: extraBody,
  );

  @override
  Future<GroqResult> ask(
    AgentKind agent,
    List<GroqMessage> messages, {
    LlmTier tier = LlmTier.light,
    bool json = false,
    double temperature = 0.2,
    int maxTokens = 1400,
    Duration? timeout,
    Map<String, Object?>? extraBody,
  }) async {
    if (ring.isEmpty || ring.usable == 0) {
      return const GroqFailure(GroqErrorKind.noKey);
    }

    GroqFailure last = const GroqFailure(GroqErrorKind.network);
    for (final model in models[tier]!) {
      final r = await _tryModel(
        agent,
        model,
        messages,
        tier: tier,
        json: json,
        temperature: temperature,
        maxTokens: maxTokens,
        timeout: timeout,
        extraBody: extraBody,
      );
      if (r is GroqSuccess) return r;
      last = r as GroqFailure;
      // Nothing more to try if every key was rejected.
      if (last.kind == GroqErrorKind.noKey || last.kind == GroqErrorKind.unauthorized) {
        if (ring.usable == 0) return last;
      }
    }
    return last;
  }

  Future<GroqResult> _tryModel(
    AgentKind agent,
    String model,
    List<GroqMessage> messages, {
    required LlmTier tier,
    required bool json,
    required double temperature,
    required int maxTokens,
    Duration? timeout,
    Map<String, Object?>? extraBody,
  }) async {
    GroqFailure last = const GroqFailure(GroqErrorKind.network);
    var useJson = json;
    var waited = Duration.zero;

    // Bounded: each pass tries every usable key once.
    for (var pass = 0; pass < 3; pass++) {
      final order = ring.tryOrder(agent);
      if (order.isEmpty) return const GroqFailure(GroqErrorKind.noKey);

      var sawRateLimit = false;
      for (final slot in order) {
        if (!ring.isAvailable(slot) && pass == 0 && order.any(ring.isAvailable)) {
          continue;
        }
        final r = await _call(
          agent, model, slot, messages,
          json: useJson,
          temperature: temperature,
          maxTokens: maxTokens,
          timeout: timeout,
          extraBody: extraBody,
          heavyReasoning: tier == LlmTier.heavy,
        );
        if (r is GroqSuccess) return r;
        last = r as GroqFailure;

        switch (last.kind) {
          case GroqErrorKind.rateLimited:
            sawRateLimit = true;
            ring.coolDown(slot, last.retryAfter ?? const Duration(seconds: 2));
          case GroqErrorKind.unauthorized:
            ring.retire(slot);
          case GroqErrorKind.badRequest:
            // JSON mode fails hard when the model emits invalid JSON; a plain
            // reply can still be parsed leniently.
            if (useJson) {
              useJson = false;
            } else {
              // The model itself is the problem (or the request): next model.
              return last;
            }
          case GroqErrorKind.empty:
          case GroqErrorKind.timeout:
          case GroqErrorKind.network:
          case GroqErrorKind.server:
            // Transient: fail over to the next key.
            break;
          case GroqErrorKind.noKey:
            return last;
        }
      }

      if (!sawRateLimit) {
        if (pass >= 1) break;
        continue;
      }
      // Every key was rate limited: wait for the soonest to recover, once.
      final soonest = [
        for (final s in ring.tryOrder(agent)) ring.cooldownLeft(s),
      ].fold<Duration?>(null, (a, b) => a == null || b < a ? b : a);
      final wait = soonest ?? const Duration(seconds: 1);
      if (waited + wait > maxRateLimitWait) return last;
      waited += wait;
      await _delay(wait);
    }
    return last;
  }

  Future<GroqResult> _call(
    AgentKind agent,
    String model,
    int slot,
    List<GroqMessage> messages, {
    required bool json,
    required double temperature,
    required int maxTokens,
    Duration? timeout,
    Map<String, Object?>? extraBody,
    required bool heavyReasoning,
  }) async {
    final gate = _gates.putIfAbsent(slot, () => _Semaphore(perKeyConcurrency));
    await gate.acquire();
    final started = DateTime.now();
    try {
      final r = await _chat(
        model: model,
        messages: messages,
        temperature: temperature,
        maxTokens: maxTokens,
        jsonMode: json,
        // gpt-oss reasons before it answers; keep that short so the reply fits.
        reasoningEffort: model.startsWith('openai/gpt-oss') ? (heavyReasoning ? 'medium' : 'low') : null,
        requestTimeout: timeout,
        apiKeyOverride: ring.key(slot),
        extraBody: extraBody,
      );
      _calls.add(
        LlmCallRecord(
          agent: agent,
          model: model,
          slot: slot,
          duration: DateTime.now().difference(started),
          ok: r is GroqSuccess,
          failure: r is GroqFailure ? r.kind : null,
        ),
      );
      return r;
    } catch (_) {
      _calls.add(
        LlmCallRecord(
          agent: agent,
          model: model,
          slot: slot,
          duration: DateTime.now().difference(started),
          ok: false,
          failure: GroqErrorKind.network,
        ),
      );
      return const GroqFailure(GroqErrorKind.network);
    } finally {
      gate.release();
    }
  }
}
