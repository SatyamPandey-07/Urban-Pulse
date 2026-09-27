import 'package:urbanpulse/agents/runtime/agent_kind.dart';
import 'package:urbanpulse/agents/runtime/llm_pool.dart';
import 'package:urbanpulse/agents/tools/agent_tool.dart';
import 'package:urbanpulse/agents/tools/web_search_tool.dart';
import 'package:urbanpulse/services/groq_api_client.dart';

/// An [AgentLlm] that plays back a script of replies and records what it was
/// asked. A reply may be a string (success) or a [GroqFailure].
class ScriptedLlm implements AgentLlm {
  ScriptedLlm([List<Object> replies = const []]) : _replies = List.of(replies);

  final List<Object> _replies;
  final List<({AgentKind agent, List<GroqMessage> messages, LlmTier tier, bool json})> asked = [];

  /// Used when the script runs out. Null means "fail with a network error".
  String? fallback;

  bool configured = true;

  void add(Object reply) => _replies.add(reply);

  @override
  bool get isConfigured => configured;

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
    // A copy: callers keep appending to their history after the call.
    asked.add((agent: agent, messages: List.of(messages), tier: tier, json: json));
    final Object? next = _replies.isNotEmpty ? _replies.removeAt(0) : fallback;
    if (next == null) return const GroqFailure(GroqErrorKind.network);
    if (next is GroqFailure) return next;
    return GroqSuccess(next as String, 'scripted');
  }
}

/// A search provider with a canned answer and a call counter.
class ScriptedSearchProvider implements SearchProvider {
  ScriptedSearchProvider(this.name, {this.results, this.available = true});

  @override
  final String name;

  @override
  bool available;

  List<SearchResult>? results;
  int calls = 0;
  final List<String> queries = [];

  @override
  Future<List<SearchResult>?> search(String query, {int maxResults = 6}) async {
    calls++;
    queries.add(query);
    return results;
  }
}

SearchResult result(String title, String url, [String snippet = '']) =>
    SearchResult(title: title, url: url, snippet: snippet, provider: 'scripted');

/// A tool that records its calls and returns a fixed output.
class ScriptedTool extends AgentTool {
  ScriptedTool(this.name, this.output);

  @override
  final String name;

  ToolOutput output;
  final List<Map<String, Object?>> calls = [];

  @override
  String get description => 'scripted $name';

  @override
  String get argsHelp => 'query: string';

  @override
  Future<ToolOutput> run(Map<String, Object?> args, {AgentKind? caller}) async {
    calls.add(args);
    return output;
  }
}
