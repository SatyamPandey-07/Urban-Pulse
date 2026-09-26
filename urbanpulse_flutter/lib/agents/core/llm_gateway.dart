import '../../core/config.dart';
import '../../services/groq_api_client.dart';

/// The only door agents use to reach a language model, so tests can script
/// replies and phase-2 agents can share one configured client.
abstract interface class LlmGateway {
  /// Whether a key is configured at all.
  bool get isConfigured;

  /// Asks for a JSON object. Implementations retry once without JSON mode when
  /// the provider rejects the response format.
  Future<GroqResult> chatJson(
    List<GroqMessage> messages, {
    double temperature,
    int maxTokens,
    Duration? timeout,
  });
}

/// Groq's GPT-OSS 120B.
class GroqLlmGateway implements LlmGateway {
  const GroqLlmGateway({this.model = 'openai/gpt-oss-120b'});

  final String model;

  @override
  bool get isConfigured => AppConfig.hasGroqKey;

  @override
  Future<GroqResult> chatJson(
    List<GroqMessage> messages, {
    double temperature = 0.1,
    int maxTokens = 1500,
    Duration? timeout,
  }) async {
    Future<GroqResult> call({required bool json}) => GroqApiClient.chat(
      model: model,
      messages: messages,
      temperature: temperature,
      maxTokens: maxTokens,
      jsonMode: json,
      // GPT-OSS spends output tokens reasoning first; keep that short so the
      // JSON reply isn't cut off.
      reasoningEffort: 'low',
      requestTimeout: timeout,
    );

    final first = await call(json: true);
    if (first is GroqFailure &&
        (first.kind == GroqErrorKind.badRequest ||
            first.kind == GroqErrorKind.empty)) {
      // JSON mode fails hard when the model emits invalid JSON; the tolerant
      // parser downstream can usually still recover a plain-text reply.
      return call(json: false);
    }
    return first;
  }
}
