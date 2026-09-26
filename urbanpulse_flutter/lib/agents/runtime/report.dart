import 'agent_kind.dart';

/// Where a value came from, so nothing an agent tells the user is unexplained.
class Provenance {
  const Provenance({
    required this.source,
    this.url,
    this.isEstimated = false,
    this.confidence = 1,
  });

  /// Human-readable origin: "Xotelo", "OpenStreetMap", "Tavily search", "AI estimate"…
  final String source;
  final String? url;

  /// Filled in by a language model rather than read from a real source.
  final bool isEstimated;

  /// 0..1, how much to trust the value.
  final double confidence;

  static const aiEstimate = Provenance(
    source: 'AI estimate',
    isEstimated: true,
    confidence: 0.4,
  );

  Provenance copyWith({String? source, String? url, bool? isEstimated, double? confidence}) =>
      Provenance(
        source: source ?? this.source,
        url: url ?? this.url,
        isEstimated: isEstimated ?? this.isEstimated,
        confidence: confidence ?? this.confidence,
      );

  Map<String, dynamic> toJson() => {
    'source': source,
    'url': url,
    'isEstimated': isEstimated,
    'confidence': confidence,
  };

  static Provenance fromJson(Map<String, dynamic> j) => Provenance(
    source: j['source'] as String? ?? 'unknown',
    url: j['url'] as String?,
    isEstimated: j['isEstimated'] as bool? ?? false,
    confidence: (j['confidence'] as num?)?.toDouble() ?? 1,
  );
}

/// One claim an agent makes, and what backs it.
class Evidence {
  const Evidence(this.claim, this.provenance);

  final String claim;
  final Provenance provenance;
}

enum IssueSeverity {
  /// The plan cannot continue as it is (e.g. nothing fits the budget).
  blocking,

  /// The plan can continue but something is doubtful (e.g. an unverified claim).
  warning,

  /// Worth mentioning only.
  info,
}

/// One way to resolve an [Issue]. [effect] is opaque to the framework: Yatri's
/// resolver interprets it (e.g. `{'budgetMaxInr': 1500}` or `{'action': 'drop'}`).
class IssueOption {
  const IssueOption({
    required this.id,
    required this.label,
    this.effect = const {},
    this.recommended = false,
    this.subtitle,
    this.badge,
  });

  final String id;
  final String label;

  /// A second line and a short trailing tag (e.g. a CO2 figure) for the card.
  final String? subtitle;
  final String? badge;
  final Map<String, Object?> effect;
  final bool recommended;
}

/// A problem a gate or worker found, with concrete ways out. Yatri decides
/// whether to fix it silently, re-task a worker, or ask the user.
class Issue {
  const Issue({
    required this.id,
    required this.agent,
    required this.message,
    required this.why,
    this.severity = IssueSeverity.warning,
    this.options = const [],
    this.userVisible = true,
  });

  /// Stable across rounds, so the same problem is never asked twice.
  final String id;
  final AgentKind agent;
  final String message;

  /// Shown behind the “?” icon: why the app is bringing this up.
  final String why;
  final IssueSeverity severity;
  final List<IssueOption> options;

  /// False for issues Yatri may resolve on its own.
  final bool userVisible;
}

enum ReportStatus {
  /// Finished normally.
  done,

  /// Finished, but on partial or estimated data.
  degraded,

  /// Cannot finish without the user (an [Issue] with options explains what).
  needsUser,

  /// Could not do the job at all; Yatri routes around it.
  failed,
}

/// What a worker hands back to Yatri.
class AgentReport {
  const AgentReport({
    required this.agent,
    required this.status,
    required this.summary,
    this.payload,
    this.evidence = const [],
    this.issues = const [],
    this.why,
  });

  factory AgentReport.failed(AgentKind agent, String reason) => AgentReport(
    agent: agent,
    status: ReportStatus.failed,
    summary: reason,
  );

  final AgentKind agent;
  final ReportStatus status;

  /// One line for the feed, e.g. "found 4 hotels".
  final String summary;

  /// The typed result (hotel options, budget report…). Opaque to the framework.
  final Object? payload;
  final List<Evidence> evidence;
  final List<Issue> issues;

  /// Why the agent did this, shown behind “?”.
  final String? why;

  bool get isUsable =>
      status == ReportStatus.done || status == ReportStatus.degraded;
}
