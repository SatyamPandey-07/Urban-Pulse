import '../../services/groq_api_client.dart';

/// The outcome of one agent run. Agents never throw for expected failures
/// (bad key, timeout, malformed output) — they return an [AgentErr] the
/// orchestrator can turn into a retry card.
sealed class AgentResult<T> {
  const AgentResult();
}

final class AgentOk<T> extends AgentResult<T> {
  const AgentOk(this.value);

  final T value;
}

final class AgentErr<T> extends AgentResult<T> {
  const AgentErr(this.kind, [this.message]);

  final GroqErrorKind kind;
  final String? message;

  /// The key is missing or was rejected — retrying will not help.
  bool get isKeyProblem =>
      kind == GroqErrorKind.noKey || kind == GroqErrorKind.unauthorized;
}

/// A Yatri agent turns an input into an output. Phase 1 has the receptionist
/// (free text -> structured brief updates) and a thin planner hand-off; phase 2
/// adds hotel, hotspot and itinerary agents that take the confirmed
/// [TripBrief] as input.
abstract interface class YatriAgent<I, O> {
  String get name;

  Future<AgentResult<O>> run(I input);
}
