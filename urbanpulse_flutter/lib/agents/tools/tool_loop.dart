import 'dart:convert';

import '../../services/groq_api_client.dart';
import '../runtime/agent_kind.dart';
import '../runtime/lenient_json.dart';
import '../runtime/llm_pool.dart';
import 'agent_tool.dart';

class ToolCallRecord {
  const ToolCallRecord({
    required this.tool,
    required this.args,
    required this.output,
    this.viaFallback = false,
  });

  final String tool;
  final Map<String, Object?> args;
  final ToolOutput output;

  /// True for calls made by the deterministic fallback rather than the model.
  final bool viaFallback;

  bool get ok => output.ok;
}

class ToolLoopResult {
  const ToolLoopResult({
    required this.calls,
    this.finalJson,
    this.usedFallback = false,
    this.error,
  });

  /// Every tool call made, in order.
  final List<ToolCallRecord> calls;

  /// The model's final structured answer, if it produced one.
  final Map<String, dynamic>? finalJson;

  /// The model's own tool use failed, so the deterministic queries ran.
  final bool usedFallback;
  final String? error;

  bool get hasAnswer => finalJson != null;

  /// All successful tool data of type [T] (e.g. every `SearchResult` list).
  Iterable<T> dataOf<T>() sync* {
    for (final c in calls) {
      if (c.ok && c.output.data is T) yield c.output.data as T;
    }
  }
}

/// A bounded LLM tool-use loop, the way agents call `web_search` "accordingly":
/// the model looks at the task context and either asks for one tool call or
/// gives its final answer. It is guarded on every side:
///  - only allow-listed tools, with schema-checked arguments;
///  - at most [maxCalls] tool calls, then it must answer;
///  - tool results are truncated before the model sees them;
///  - if the model misbehaves or the call fails, [fallbackQueries] run instead,
///    so the agent still gets data.
class ToolLoop {
  ToolLoop({
    required this.llm,
    required this.tools,
    this.maxCalls = 3,
    this.maxObservationChars = 3500,
  });

  final AgentLlm llm;
  final ToolRegistry tools;
  final int maxCalls;
  final int maxObservationChars;

  static const protocol = '''
You can call tools. On every turn reply with ONE JSON object and nothing else:
  {"tool": "<name>", "args": { ... }}      to call a tool, or
  {"final": { ... }}                        when you have what you need.
Call a tool only when it will improve your answer. Never invent tool names.''';

  Future<ToolLoopResult> run({
    required AgentKind agent,
    required String system,
    required String context,
    required List<String> allowedTools,
    List<Map<String, Object?>> fallbackCalls = const [],
    LlmTier tier = LlmTier.light,
    Duration? timeout,
  }) async {
    final calls = <ToolCallRecord>[];
    final history = <GroqMessage>[
      GroqMessage(
        'system',
        '$system\n\n$protocol\n\nTools:\n${tools.describe(allowedTools)}\n'
            'You may make at most $maxCalls tool calls.',
      ),
      GroqMessage('user', context),
    ];

    var invalid = 0;
    for (var turn = 0; turn <= maxCalls + 1; turn++) {
      final callsLeft = maxCalls - calls.length;
      if (callsLeft <= 0 && turn > 0) {
        history.add(const GroqMessage(
          'user',
          'No tool calls left. Reply now with {"final": {...}} using what you have.',
        ));
      }

      final r = await llm.ask(
        agent,
        history,
        tier: tier,
        json: true,
        maxTokens: 1800,
        timeout: timeout,
      );
      if (r is! GroqSuccess) return _fallback(agent, calls, fallbackCalls, allowedTools, r is GroqFailure ? 'model: ${r.kind.name}' : null, system, context, tier, timeout);

      final json = parseLenientObject(r.content);
      history.add(GroqMessage('assistant', r.content));

      if (json != null && json['final'] is Map<String, dynamic>) {
        return ToolLoopResult(calls: calls, finalJson: json['final'] as Map<String, dynamic>);
      }

      final toolName = json?['tool'];
      final args = json?['args'];
      final valid =
          toolName is String &&
          allowedTools.contains(toolName) &&
          tools.has(toolName) &&
          (args == null || args is Map<String, dynamic>) &&
          callsLeft > 0;

      if (!valid) {
        invalid++;
        if (invalid >= 2 || callsLeft <= 0) {
          return _fallback(agent, calls, fallbackCalls, allowedTools, 'invalid tool call', system, context, tier, timeout);
        }
        history.add(const GroqMessage(
          'user',
          'That was not a valid reply. Use an allowed tool with an "args" object, or reply {"final": {...}}.',
        ));
        continue;
      }

      final callArgs = Map<String, Object?>.from((args as Map<String, dynamic>?) ?? const {});
      final out = await tools[toolName]!.run(callArgs, caller: agent);
      calls.add(ToolCallRecord(tool: toolName, args: callArgs, output: out));
      history.add(GroqMessage('user', 'TOOL RESULT ($toolName): ${_truncate(out.text, maxObservationChars)}'));
    }

    return _fallback(agent, calls, fallbackCalls, allowedTools, 'too many turns', system, context, tier, timeout);
  }

  /// The model could not drive the tools: run the deterministic calls, then ask
  /// once for a final answer from what they returned. If that also fails the
  /// caller still has the raw tool data.
  Future<ToolLoopResult> _fallback(
    AgentKind agent,
    List<ToolCallRecord> calls,
    List<Map<String, Object?>> fallbackCalls,
    List<String> allowedTools,
    String? reason,
    String system,
    String context,
    LlmTier tier,
    Duration? timeout,
  ) async {
    for (final spec in fallbackCalls) {
      final name = spec['tool'] as String?;
      final args = (spec['args'] as Map?)?.cast<String, Object?>() ?? const {};
      if (name == null || !allowedTools.contains(name) || !tools.has(name)) continue;
      final out = await tools[name]!.run(Map.of(args), caller: agent);
      calls.add(ToolCallRecord(tool: name, args: Map.of(args), output: out, viaFallback: true));
    }

    final observations = [
      for (final c in calls)
        if (c.ok) 'TOOL RESULT (${c.tool}): ${_truncate(c.output.text, maxObservationChars)}',
    ];
    if (observations.isEmpty) {
      return ToolLoopResult(calls: calls, usedFallback: true, error: reason ?? 'no tool data');
    }

    final r = await llm.ask(
      agent,
      [
        GroqMessage('system', '$system\n\nReply with ONE JSON object: {"final": { ... }}.'),
        GroqMessage('user', '$context\n\n${observations.join('\n\n')}'),
      ],
      tier: tier,
      json: true,
      maxTokens: 1800,
      timeout: timeout,
    );
    Map<String, dynamic>? finalJson;
    if (r is GroqSuccess) {
      final j = parseLenientObject(r.content);
      finalJson = j?['final'] is Map<String, dynamic> ? j!['final'] as Map<String, dynamic> : j;
    }
    return ToolLoopResult(calls: calls, finalJson: finalJson, usedFallback: true, error: reason);
  }

  static String _truncate(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}…';

  /// A compact JSON string for prompts.
  static String compact(Object? v) => jsonEncode(v);
}
