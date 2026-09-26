import '../runtime/report.dart';
import '../runtime/task_board.dart';
import '../yatri/hotel_gates.dart';
import 'hotel_finder.dart';

/// Atithi, the hotel finder. A worker: it searches, narrates what it does into
/// the feed, and reports what it found together with the problems it can see.
/// It never decides anything: Yatri does.
class AtithiAgent {
  AtithiAgent(this.finder);

  final HotelFinder finder;

  Future<AgentReport> run(TaskContext ctx, HotelQuery query) async {
    ctx.say(
      'is searching for stays near ${query.destination}',
      why: 'Atithi combines TripAdvisor prices, OpenStreetMap and web search so no single source decides what you see.',
    );
    final HotelSearchResult result;
    try {
      result = await finder.find(
        query,
        onProgress: (text, {why}) => ctx.say(text, why: why),
        isDegraded: () => ctx.degraded || ctx.cancelled,
      );
    } catch (e) {
      return AgentReport.failed(ctx.agent, 'Atithi could not search for hotels');
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

  static List<Evidence> _evidence(HotelSearchResult r) => [
    for (final s in r.sources) Evidence('Used $s', Provenance(source: s)),
  ];
}
