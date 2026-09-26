import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../khoji/khoji_agent.dart';
import '../runtime/report.dart';
import '../runtime/task_board.dart';
import '../yatri/hotel_gates.dart';
import 'hotel_finder.dart';

/// Atithi, the hotel finder. A worker: it searches, narrates what it does into
/// the feed, and reports what it found together with the problems it can see.
/// It never decides anything: Yatri does.
class AtithiAgent {
  AtithiAgent(this.finder, {this.khoji});

  final HotelFinder finder;

  /// Khoji checks the best hotels before Yatri sees them.
  final KhojiAgent? khoji;

  Future<AgentReport> run(TaskContext ctx, HotelQuery query) async {
    ctx.say(
      'is searching for stays near ${query.destination}',
      why: 'Atithi combines TripAdvisor prices, OpenStreetMap and web search so no single source decides what you see.',
    );
    HotelSearchResult result;
    try {
      result = await finder.find(
        query,
        onProgress: (text, {why}) => ctx.say(text, why: why),
        isCancelled: () => ctx.cancelled,
      );
    } catch (e) {
      return AgentReport.failed(ctx.agent, 'Atithi could not search for hotels');
    }

    // Khoji verifies the top few: claims, guest reviews, access evidence.
    final k = khoji;
    if (k != null && result.options.isNotEmpty && !ctx.cancelled) {
      try {
        final checked = await k.verifyHotels(ctx, result.options, query);
        final needs = {for (final n in query.needs) if (n != AccessibilityNeed.none) n};
        final verified = checked.any((h) => h.claims.any((c) => c.isReviews)) || checked.any((h) => h.claims.any((c) => c.verdict != Verdict.unverified));
        result = result.copyWith(options: _demoteFailing(checked, needs), extraSources: verified ? const ['Guest reviews and web checks (Khoji)'] : null);
      } catch (_) {
        // verification is a bonus; the search result stands
      }
    }

    final live = result.options.where((o) => !o.priceIsEstimated).length;
    final estimated = result.options.length - live;
    final issues = HotelGates.checkAtithi(result);

    if (result.options.isEmpty) {
      return AgentReport(
        agent: ctx.agent,
        status: ReportStatus.degraded,
        summary: 'found no hotels near ${query.destination}',
        payload: result,
        issues: issues,
        why: result.warnings.isEmpty ? null : result.warnings.join(' '),
        evidence: _evidence(result),
      );
    }

    final priceNote = live > 0
        ? '$live with live prices${estimated > 0 ? ', $estimated estimated' : ''}'
        : 'prices are estimates';
    return AgentReport(
      agent: ctx.agent,
      status: estimated > 0 || result.warnings.isNotEmpty ? ReportStatus.degraded : ReportStatus.done,
      summary: 'found ${result.options.length} hotels ($priceNote)',
      payload: result,
      issues: issues,
      why: 'Shortlisted from ${result.considered} hotels, ranked by fit for your group, budget and distance.',
      evidence: _evidence(result),
    );
  }

  /// Hotels that verification showed do not suit the group go below the rest,
  /// otherwise keeping the ranking.
  static List<HotelOption> _demoteFailing(List<HotelOption> options, Set<AccessibilityNeed> needs) {
    if (needs.isEmpty) return options;
    bool fails(HotelOption h) => needs.any((n) => h.access[n]?.level == SupportLevel.no);
    return [
      for (final h in options) if (!fails(h)) h,
      for (final h in options) if (fails(h)) h,
    ];
  }

  static List<Evidence> _evidence(HotelSearchResult r) => [
    for (final s in r.sources) Evidence('Used $s', Provenance(source: s)),
  ];
}
