import '../../domain/access/access_rules.dart';
import '../../models/itinerary/itinerary.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../services/data/ai_estimator.dart';
import '../runtime/agent_kind.dart';
import '../runtime/report.dart';
import '../runtime/task_board.dart';
import 'audit_engine.dart';

/// Saksham, the accessibility auditor. It reads every step of the trip against
/// every need in the group: rules first (tags, listings, mode profiles, and what
/// Khoji found), then, for places nothing could speak to, one cautious model
/// reading, labelled as an estimate and never stronger than "partly".
class SakshamAgent {
  SakshamAgent({this.estimator});

  final AiEstimator? estimator;

  Future<AgentReport> run(TaskContext ctx, AuditInput input) async {
    final needs = AccessRules.relevant(input.needs);
    if (needs.isEmpty) {
      return AgentReport(
        agent: ctx.agent,
        status: ReportStatus.done,
        summary: 'no access needs to audit',
        payload: const AuditResult(audit: AccessibilityAudit(items: [])),
        why: 'The group did not report any access needs.',
      );
    }
    ctx.say(
      'is auditing every step for ${needs.length} access need${needs.length == 1 ? '' : 's'}',
      why: 'A trip is only accessible if the stay, the journey, each place and each transfer all are.',
    );

    var result = AuditEngine.run(input);

    // Gaps: one careful model reading for places nothing could speak to.
    final est = estimator;
    if (est != null && result.unknownPlaces.isNotEmpty && !ctx.degraded && !ctx.cancelled) {
      final inferred = await _infer(est, result.unknownPlaces, needs);
      if (inferred.isNotEmpty) {
        result = AuditEngine.run(
          AuditInput(
            needs: input.needs,
            days: input.days,
            spots: {
              for (final e in input.spots.entries)
                e.key: inferred.containsKey(e.key) ? _withInferred(e.value, inferred[e.key]!) : e.value,
            },
            hotel: input.hotel,
            outbound: input.outbound,
            inbound: input.inbound,
          ),
        );
      }
    }

    final audit = result.audit;
    final fails = result.failures.length;
    final open = audit.items.where((i) => i.overall != SupportLevel.yes).length;
    return AgentReport(
      agent: ctx.agent,
      status: fails > 0 || open > 0 ? ReportStatus.degraded : ReportStatus.done,
      summary: fails > 0
          ? 'found $fails step${fails == 1 ? '' : 's'} that ${fails == 1 ? 'does' : 'do'} not suit the group'
          : open > 0
          ? 'audited ${audit.items.length} steps: $open to confirm'
          : 'audited ${audit.items.length} steps: all suit the group',
      payload: result,
      why: 'Readings come from map tags, listings, reviews found by Khoji and how each way of travelling works. Estimates are labelled.',
    );
  }

  Future<Map<String, Map<AccessibilityNeed, NeedSupport>>> _infer(AiEstimator est, List<Hotspot> places, Set<AccessibilityNeed> needs) async {
    final items = <String, Map<String, Object?>>{};
    for (final h in places.take(20)) {
      items[h.id] = {'name': h.name, 'kind': h.kind.name, 'outdoor': h.isOutdoor, 'about': h.why};
    }
    final fields = {
      for (final n in needs)
        'access_${n.name}': 'does a place like this realistically suit "${n.label}"? one of yes, partial, no, unknown; say unknown unless you have a real basis',
    };
    try {
      final filled = await est.fillMany(agent: AgentKind.saksham, subject: 'places to visit on a trip', items: items, fields: fields);
      if (filled == null) return const {};
      final out = <String, Map<AccessibilityNeed, NeedSupport>>{};
      for (final e in filled.entries) {
        final m = <AccessibilityNeed, NeedSupport>{};
        for (final n in needs) {
          final raw = e.value['access_${n.name}']?.value;
          if (raw is! String) continue;
          var level = switch (raw.toLowerCase().trim()) {
            'yes' => SupportLevel.yes,
            'partial' => SupportLevel.partial,
            'no' => SupportLevel.no,
            _ => SupportLevel.unknown,
          };
          if (level == SupportLevel.unknown) continue;
          // A model's "yes" without evidence is never presented as confirmed.
          if (level == SupportLevel.yes) level = SupportLevel.partial;
          m[n] = NeedSupport(
            need: n,
            level: level,
            detail: 'Estimated from the type of place; not verified. Confirm with the venue before you go.',
            provenance: Provenance.aiEstimate,
          );
        }
        if (m.isNotEmpty) out[e.key] = m;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// A place with model readings added only where nothing real spoke.
  static Hotspot _withInferred(Hotspot h, Map<AccessibilityNeed, NeedSupport> inferred) {
    final access = {...h.access};
    for (final e in inferred.entries) {
      final cur = access[e.key];
      if (cur == null || cur.level == SupportLevel.unknown) access[e.key] = e.value;
    }
    return h.copyWith(access: access);
  }
}
