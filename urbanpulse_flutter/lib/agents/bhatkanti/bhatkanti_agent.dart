import '../khoji/khoji_agent.dart';
import '../runtime/report.dart';
import '../runtime/task_board.dart';
import '../yatri/hotspot_gates.dart';
import 'hotspot_finder.dart';

/// Bhatkanti, the hotspot finder. A worker: it searches, narrates into the
/// feed and reports what it found plus the questions it can see. Yatri decides.
class BhatkantiAgent {
  BhatkantiAgent(this.finder, {this.khoji});

  final HotspotFinder finder;

  /// Khoji checks new places and unconfirmed access before they are planned.
  final KhojiAgent? khoji;

  Future<AgentReport> run(TaskContext ctx, HotspotQuery query) async {
    ctx.say(
      'is looking for places to visit in ${query.destination}',
      why: 'Bhatkanti picks about ${query.perDay} places a day: ${query.target} for this trip, from maps, Wikipedia and web searches.',
    );
    HotspotSearchResult result;
    try {
      result = await finder.find(
        query,
        onProgress: (text, {why}) => ctx.say(text, why: why),
        isCancelled: () => ctx.cancelled,
      );
    } catch (e) {
      return AgentReport.failed(ctx.agent, 'Bhatkanti could not search for places');
    }

    final k = khoji;
    if (k != null && result.selected.isNotEmpty && !ctx.cancelled) {
      try {
        final v = await k.verifyHotspots(ctx, result);
        if (v.replacements.isNotEmpty || v.closedIds.isNotEmpty) {
          result = HotspotFinder.amended(result, replacements: v.replacements, dropIds: v.closedIds);
        }
      } catch (_) {
        // verification is a bonus; the search result stands
      }
    }

    final issues = HotspotGates.check(result);
    if (result.selected.isEmpty) {
      return AgentReport(
        agent: ctx.agent,
        status: ReportStatus.degraded,
        summary: 'found no places near ${query.destination}',
        payload: result,
        issues: issues,
        why: result.warnings.isEmpty ? null : result.warnings.join(' '),
      );
    }

    final trending = result.trendingCount;
    return AgentReport(
      agent: ctx.agent,
      status: result.warnings.isNotEmpty ? ReportStatus.degraded : ReportStatus.done,
      summary: 'shortlisted ${result.selected.length} places'
          '${trending > 0 ? ' ($trending new and trending)' : ''}',
      payload: result,
      issues: issues,
      why: 'Chosen from ${result.considered} candidates for the trip length, style and accessibility needs.',
      evidence: [for (final s in result.sources) Evidence('Used $s', Provenance(source: s))],
    );
  }
}
