import '../../core/formatting.dart';
import '../runtime/report.dart';
import '../runtime/task_board.dart';
import '../yatri/green_gates.dart';
import 'carbon_engine.dart';

/// Hariyali, the sustainability agent: scores the carbon and eco impact of the
/// plan and suggests greener choices. A worker: it measures and reports, and
/// Yatri decides whether the traveller should be asked.
class HariyaliAgent {
  Future<AgentReport> run(TaskContext ctx, GreenInput input, {required bool preferGreenest}) async {
    ctx.say(
      'is measuring the carbon footprint of the plan',
      why: 'Hariyali adds up emissions from the journey, local travel and the stay, and compares them with the most polluting comparable choices.',
    );
    final GreenResult result;
    try {
      result = GreenEngine.compute(input);
    } catch (_) {
      return AgentReport.failed(ctx.agent, 'Hariyali could not measure the footprint');
    }
    final r = result.report;
    return AgentReport(
      agent: ctx.agent,
      status: ReportStatus.degraded, // emission factors are typical values
      summary: 'the plan emits about ${fixed(r.co2Kg, 0)} kg CO₂, ${fixed(r.co2SavedKg, 0)} kg less than the most polluting choices (eco score ${r.score})',
      payload: result,
      issues: GreenGates.check(result, input, preferGreenest: preferGreenest),
      why: 'Emission factors are typical values per passenger-kilometre and per hotel night, so the figures are estimates.',
    );
  }
}
