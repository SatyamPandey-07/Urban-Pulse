import 'dart:convert';

import '../../agents/runtime/agent_kind.dart';
import '../../agents/runtime/llm_pool.dart';
import '../../agents/runtime/report.dart';

/// A value the model filled in because no real source had it.
class Estimated<T> {
  const Estimated(this.value, {this.provenance = Provenance.aiEstimate});

  final T value;

  /// Always `isEstimated`, so the UI can label it.
  final Provenance provenance;
}

/// Fills gaps in real data with a language model's general knowledge, and says
/// so. Real sources come first everywhere; this only runs for fields nothing
/// else could supply, and every value it returns is marked as an estimate.
/// It never throws and returns null when the model is unavailable, so callers
/// drop to deterministic defaults.
class AiEstimator {
  AiEstimator(this.llm);

  final AgentLlm llm;

  static const _system =
      'You estimate missing travel facts for a trip planner in India and abroad. '
      'Answer ONLY with one JSON object matching the requested shape. Use null '
      'for anything you genuinely do not know: do not guess, and never invent '
      'URLs, phone numbers or names. Prices are in Indian rupees (INR) unless '
      'asked otherwise. Be conservative: prefer the typical value over an extreme.';

  /// Asks for [fields] (name -> what it means) about [subject], given what is
  /// already [known]. Returns only the fields the model actually answered,
  /// each marked as an estimate, or null when the call failed.
  Future<Map<String, Estimated<Object>>?> fill({
    required AgentKind agent,
    required String subject,
    required Map<String, String> fields,
    Map<String, Object?> known = const {},
    LlmTier tier = LlmTier.light,
  }) async {
    final reply = await llm.askJson(
      agent,
      system: _system,
      user: jsonEncode({
        'subject': subject,
        'alreadyKnown': known,
        'estimate': fields,
      }),
      tier: tier,
      temperature: 0.2,
      maxTokens: 900,
      timeout: const Duration(seconds: 15),
    );
    final m = reply.map;
    if (m == null) return null;
    final out = <String, Estimated<Object>>{};
    for (final name in fields.keys) {
      final v = m[name];
      if (v != null && v is! Map) out[name] = Estimated<Object>(v);
    }
    return out;
  }

  /// One batched call for many items of the same kind (e.g. ten hotels), so a
  /// plan pays for one model call, not ten. Returns id -> fields, or null on
  /// failure. Items the model skipped are simply absent.
  Future<Map<String, Map<String, Estimated<Object>>>?> fillMany({
    required AgentKind agent,
    required String subject,
    required Map<String, Map<String, Object?>> items,
    required Map<String, String> fields,
    LlmTier tier = LlmTier.light,
  }) async {
    if (items.isEmpty) return const {};
    final reply = await llm.askJson(
      agent,
      system:
          '$_system\nThe input has an "items" object keyed by id. Reply with '
          '{"items": {"<id>": { ...requested fields... }}} covering every id.',
      user: jsonEncode({'subject': subject, 'items': items, 'estimate': fields}),
      tier: tier,
      temperature: 0.2,
      maxTokens: 2200,
      timeout: const Duration(seconds: 20),
    );
    final root = reply.map?['items'];
    if (root is! Map<String, dynamic>) return null;
    final out = <String, Map<String, Estimated<Object>>>{};
    for (final id in items.keys) {
      final row = root[id];
      if (row is! Map<String, dynamic>) continue;
      final filled = <String, Estimated<Object>>{};
      for (final name in fields.keys) {
        final v = row[name];
        if (v != null && v is! Map) filled[name] = Estimated<Object>(v);
      }
      if (filled.isNotEmpty) out[id] = filled;
    }
    return out;
  }

  /// A model number coerced into a sane range, or null if it is not a number.
  static int? intIn(Object? v, int min, int max) {
    final n = v is num ? v.round() : int.tryParse('$v');
    if (n == null) return null;
    return n.clamp(min, max);
  }
}
