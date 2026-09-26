import '../runtime/agent_kind.dart';
import '../runtime/report.dart';

/// What a tool hands back. [text] is what a language model sees; [data] is the
/// typed result for deterministic code; [sources] say where it came from.
class ToolOutput {
  const ToolOutput({
    required this.ok,
    this.text = '',
    this.data,
    this.sources = const [],
    this.error,
  });

  factory ToolOutput.failure(String error) => ToolOutput(ok: false, error: error, text: 'Error: $error');

  final bool ok;
  final String text;
  final Object? data;
  final List<Provenance> sources;
  final String? error;
}

/// Something an agent can call by name with JSON-like arguments. Tools never
/// throw: a failure is an [ToolOutput] with `ok == false`.
abstract class AgentTool {
  String get name;

  /// One line for the model: what it does and when to use it.
  String get description;

  /// The arguments it takes, for the model's prompt.
  String get argsHelp;

  Future<ToolOutput> run(Map<String, Object?> args, {AgentKind? caller});
}

class ToolRegistry {
  final Map<String, AgentTool> _tools = {};

  void register(AgentTool tool) => _tools[tool.name] = tool;

  AgentTool? operator [](String name) => _tools[name];

  Iterable<String> get names => _tools.keys;

  bool has(String name) => _tools.containsKey(name);

  /// The tool list as it appears in an agent prompt.
  String describe(Iterable<String> allowed) => [
    for (final n in allowed)
      if (_tools[n] case final t?) '- ${t.name}(${t.argsHelp}): ${t.description}',
  ].join('\n');
}

/// A hard cap on paid or rate-limited lookups for one plan, so the free
/// tiers last. Shared by every agent through the same instance.
class ToolBudget {
  ToolBudget({this.maxSearches = 8, this.maxFetches = 8, this.maxLlmSearches = 3, this.maxReviewSearches = 6});

  final int maxSearches;
  final int maxFetches;

  /// Searches made by a Groq model itself cost a model call each; keep them rare.
  final int maxLlmSearches;

  /// Khoji's own model searches for reviews, kept apart so the other agents'
  /// searches can never use them up.
  final int maxReviewSearches;

  int _searches = 0;
  int _fetches = 0;
  int _llmSearches = 0;
  int _reviewSearches = 0;

  int get searchesUsed => _searches;
  int get fetchesUsed => _fetches;

  bool trySpendSearch() {
    if (_searches >= maxSearches) return false;
    _searches++;
    return true;
  }

  bool trySpendFetch() {
    if (_fetches >= maxFetches) return false;
    _fetches++;
    return true;
  }

  bool trySpendLlmSearch() {
    if (_llmSearches >= maxLlmSearches) return false;
    _llmSearches++;
    return true;
  }

  bool trySpendReviewSearch() {
    if (_reviewSearches >= maxReviewSearches) return false;
    _reviewSearches++;
    return true;
  }

  /// Returns a spent unit when a lookup was answered from cache after all.
  void refundSearch() {
    if (_searches > 0) _searches--;
  }

  void refundFetch() {
    if (_fetches > 0) _fetches--;
  }
}
