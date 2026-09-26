import '../bhatkanti/hotspot_finder.dart';
import '../runtime/agent_kind.dart';
import '../runtime/report.dart';

/// Yatri's checks on Bhatkanti's answer.
abstract final class HotspotGates {
  static List<Issue> check(HotspotSearchResult r) {
    if (r.selected.isEmpty) return [_none(r)];
    if (r.offersMixChoice) return [_mix(r)];
    return const [];
  }

  /// The search after the traveller chose [option]: null means "go with what
  /// there is". A mix choice re-picks from the pool without searching again.
  static HotspotMix? mixOf(IssueOption option) {
    final m = option.effect['mix'];
    for (final v in HotspotMix.values) {
      if (v.name == m) return v;
    }
    return null;
  }

  static HotspotQuery? widen(HotspotQuery q, IssueOption option) {
    final f = option.effect['radiusFactor'];
    return f is num ? q.copyWith(radiusFactor: f.toDouble()) : null;
  }

  static Issue _none(HotspotSearchResult r) {
    final q = r.query;
    final canWiden = q.radiusFactor < 2;
    return Issue(
      id: 'hotspots.none@${q.radiusFactor}',
      agent: AgentKind.bhatkanti,
      severity: IssueSeverity.blocking,
      message: 'I could not find places to visit near ${q.destination}. '
          '${canWiden ? 'Should I look further out?' : 'How would you like to go on?'}',
      why: 'Bhatkanti searched maps, Wikipedia and the web. A wider area often turns up sights in the next town.',
      options: [
        if (canWiden)
          const IssueOption(id: 'wider', label: 'Look further out', effect: {'radiusFactor': 2.0}, recommended: true),
        IssueOption(
          id: 'skip',
          label: 'Leave the days open — I will explore on my own',
          effect: const {'action': 'skip'},
          recommended: !canWiden,
        ),
      ],
    );
  }

  static Issue _mix(HotspotSearchResult r) {
    final q = r.query;
    final trending = r.pool.where((h) => h.isTrending).take(3).map((h) => h.name).toList();
    final classic = r.pool.where((h) => !h.isTrending && h.score >= 0.4).take(3).map((h) => h.name).toList();
    final e = trending.isEmpty ? '' : ' New: ${trending.join(', ')}.';
    final c = classic.isEmpty ? '' : ' Classics: ${classic.join(', ')}.';
    return Issue(
      id: 'hotspots.mix',
      agent: AgentKind.bhatkanti,
      severity: IssueSeverity.info,
      message: 'For ${q.destination} I found long-standing favourites and some newly popular places.$c$e What should the plan lean towards?',
      why: 'Well-known sights are reliable, while new places can be more exciting but have fewer reviews. '
          'It is a matter of taste, so Yatri asks rather than guessing.',
      options: [
        IssueOption(id: HotspotMix.balanced.name, label: HotspotMix.balanced.label, effect: {'mix': HotspotMix.balanced.name}, recommended: true),
        IssueOption(id: HotspotMix.classic.name, label: HotspotMix.classic.label, effect: {'mix': HotspotMix.classic.name}),
        IssueOption(id: HotspotMix.trending.name, label: HotspotMix.trending.label, effect: {'mix': HotspotMix.trending.name}),
      ],
    );
  }
}
