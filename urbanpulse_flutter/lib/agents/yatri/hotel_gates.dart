import '../../core/formatting.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../atithi/hotel_finder.dart';
import '../runtime/agent_kind.dart';
import '../runtime/report.dart';

/// The checks Yatri runs on Atithi's answer, in code. Each problem becomes an
/// [Issue] with concrete ways out, so a decision is a choice among real
/// options, never an invention.
abstract final class HotelGates {
  /// A widened search is never wider than this.
  static const maxRadiusKm = 30.0;

  /// Every problem with [r], most important first.
  static List<Issue> check(HotelSearchResult r) => [...checkAtithi(r), ...checkHisab(r)];

  /// What is wrong with the hotels themselves: none found, or none that suit.
  static List<Issue> checkAtithi(HotelSearchResult r) {
    final q = r.query;
    if (r.options.isEmpty) return [_none(q)];
    final needs = _needs(q);
    final suitable = [for (final o in r.options) if (!_failsAny(o, needs)) o];
    final confirmed = [for (final o in r.options) if (o.meets(needs)) o];
    if (needs.isNotEmpty && confirmed.isEmpty) return [_access(r, needs, suitable)];
    return const [];
  }

  /// Hisab's check: does anything suitable fit the nightly budget?
  static List<Issue> checkHisab(HotelSearchResult r) {
    final q = r.query;
    final cap = q.nightlyCapInr;
    if (cap == null || r.options.isEmpty) return const [];
    final needs = _needs(q);
    final suitable = [for (final o in r.options) if (!_failsAny(o, needs)) o];
    final confirmed = [for (final o in r.options) if (o.meets(needs)) o];
    final pool = confirmed.isNotEmpty ? confirmed : (suitable.isNotEmpty ? suitable : r.options);
    final priced = [for (final o in pool) if (o.nightlyInr != null) o];
    if (priced.isNotEmpty && priced.every((o) => o.nightlyInr! > cap)) {
      return [_budget(r, cap, priced, needs)];
    }
    return const [];
  }

  /// The search after the traveller chose [option] for [issue]. Null means
  /// "stop searching and go with what was found".
  static HotelQuery? apply(HotelQuery q, IssueOption option) {
    final e = option.effect;
    if (e['action'] == 'accept' || e['action'] == 'skip') return null;
    final cap = e['nightlyCapInr'];
    final radius = e['radiusKm'];
    if (cap is! num && radius is! num) return null;
    return q.copyWith(
      nightlyCapInr: cap is num ? cap.round() : null,
      radiusKm: radius is num ? radius.toDouble() : null,
    );
  }

  // --- the issues -----------------------------------------------------------

  static Issue _none(HotelQuery q) {
    final wider = q.radiusKm < maxRadiusKm;
    return Issue(
      id: 'hotels.none@${q.radiusKm.round()}',
      agent: AgentKind.atithi,
      severity: IssueSeverity.blocking,
      message: 'I could not find any hotels near ${q.destination}. '
          '${wider ? 'Should I search a wider area?' : 'How would you like to go on?'}',
      why: 'Atithi looked in several places (TripAdvisor, OpenStreetMap, Geoapify, the web) and came back empty. '
          'A wider area often finds stays in the next town.',
      options: [
        if (wider)
          IssueOption(
            id: 'wider',
            label: 'Search a wider area (up to ${maxRadiusKm.round()} km)',
            effect: {'radiusKm': maxRadiusKm},
            recommended: true,
          ),
        IssueOption(
          id: 'skip',
          label: 'Continue without a hotel — I will arrange my own stay',
          effect: const {'action': 'skip'},
          recommended: !wider,
        ),
      ],
    );
  }

  static Issue _access(HotelSearchResult r, Set<AccessibilityNeed> needs, List<HotelOption> suitable) {
    final q = r.query;
    final what = _needsPhrase(needs);
    final wider = q.radiusKm < maxRadiusKm;
    final anyChance = suitable.isNotEmpty;
    return Issue(
      id: 'hotels.access@${q.radiusKm.round()}',
      agent: AgentKind.atithi,
      severity: IssueSeverity.blocking,
      message: anyChance
          ? 'I found ${r.options.length} hotels, but none is confirmed to suit $what. '
              'Some are unconfirmed rather than ruled out. What would you like?'
          : 'None of the ${r.options.length} hotels I found suits $what. What would you like?',
      why: 'Access is checked against OpenStreetMap tags and the hotels\' own listings. '
          'Where nothing says a hotel works, it stays “unconfirmed” instead of being assumed fine.',
      options: [
        if (anyChance)
          const IssueOption(
            id: 'accept',
            label: 'Show me the best of them; I will confirm with the hotel',
            effect: {'action': 'accept'},
            recommended: true,
          ),
        if (wider)
          IssueOption(
            id: 'wider',
            label: 'Search a wider area (up to ${maxRadiusKm.round()} km)',
            effect: {'radiusKm': maxRadiusKm},
            recommended: !anyChance,
          ),
        if (!anyChance)
          IssueOption(
            id: 'accept',
            label: 'Show me the closest options anyway',
            effect: const {'action': 'accept'},
            recommended: !wider,
          ),
        ..._stayOptions(r.options, needs),
      ],
    );
  }

  static Issue _budget(HotelSearchResult r, int cap, List<HotelOption> priced, Set<AccessibilityNeed> needs) {
    final q = r.query;
    final cheapest = priced.map((o) => o.nightlyInr!).reduce((a, b) => a < b ? a : b);
    final raise = _roundUp(cheapest, 100);
    final more = _roundUp((raise * 1.3).round(), 100);
    final forWhom = needs.isEmpty ? 'hotel' : 'hotel that suits ${_needsPhrase(needs)}';
    final estimated = priced.every((o) => o.priceIsEstimated);
    final wider = q.radiusKm < maxRadiusKm;
    return Issue(
      id: 'hotels.budget@$cap',
      agent: AgentKind.hisab,
      severity: IssueSeverity.blocking,
      message: 'The cheapest $forWhom I found is about ₹$cheapest a night${estimated ? ' (estimated)' : ''}, '
          'above your budget of about ₹$cap. What should I do?',
      why: 'Hisab reserves about 40% of your trip budget for the stay: ₹$cap a night per room here. '
          'Raising it shifts money from food, transport and activities, which Hisab will rebalance.',
      options: [
        IssueOption(
          id: 'raise',
          label: 'Raise the hotel budget to ₹$raise a night',
          effect: {'nightlyCapInr': raise},
          recommended: true,
        ),
        if (more > raise)
          IssueOption(id: 'raise_more', label: 'Raise it to ₹$more for more choice', effect: {'nightlyCapInr': more}),
        if (wider)
          IssueOption(
            id: 'wider',
            label: 'Keep ₹$cap and search a wider area',
            effect: {'radiusKm': maxRadiusKm},
          ),
        IssueOption(
          id: 'accept',
          label: 'Keep ₹$cap and show me the closest options',
          effect: const {'action': 'accept'},
        ),
        ..._stayOptions(priced, needs),
      ],
    );
  }

  /// When nothing meets everything: up to three real stays to choose from,
  /// each saying what it meets, what is unconfirmed and what fails, and its
  /// price, so the traveller decides what is good enough.
  static List<IssueOption> _stayOptions(List<HotelOption> options, Set<AccessibilityNeed> needs) {
    int count(HotelOption h, SupportLevel l) => needs.where((n) => (h.access[n]?.level ?? SupportLevel.unknown) == l).length;
    final ranked = [for (var i = 0; i < options.length; i++) (i, options[i])]
      ..sort((a, b) {
        final byFail = count(a.$2, SupportLevel.no).compareTo(count(b.$2, SupportLevel.no));
        if (byFail != 0) return byFail;
        final byUnknown = count(a.$2, SupportLevel.unknown).compareTo(count(b.$2, SupportLevel.unknown));
        return byUnknown != 0 ? byUnknown : a.$1.compareTo(b.$1);
      });
    return [
      for (final (_, h) in ranked.take(3))
        IssueOption(
          id: 'hotel.${h.id}',
          label: 'Stay at ${h.name}',
          subtitle: _fitLine(h, needs),
          effect: {'action': 'swapHotel', 'hotelId': h.id},
        ),
    ];
  }

  /// “wheelchair: yes · elderly: not confirmed · ≈ ₹4,200 a night”.
  static String _fitLine(HotelOption h, Set<AccessibilityNeed> needs) {
    final parts = [
      for (final n in needs)
        '${n.label.split(' ').first.toLowerCase()}: ${switch (h.access[n]?.level) {
          SupportLevel.yes => 'yes',
          SupportLevel.partial => 'partly',
          SupportLevel.no => 'no',
          _ => 'not confirmed',
        }}',
      if (h.nightlyInr != null) '${h.priceIsEstimated ? '≈ ' : ''}${rupees(h.nightlyInr!)} a night',
    ];
    return parts.join(' · ');
  }

  /// [issue] once no more searches are allowed: only the choices that need no
  /// new search (a real stay, accepting, skipping) are left.
  static Issue withoutSearching(Issue issue) {
    final left = [
      for (final o in issue.options)
        if (o.effect['action'] == 'accept' || o.effect['action'] == 'skip' || o.effect['action'] == 'swapHotel') o,
    ];
    final options = left.isEmpty ? issue.options : left;
    final hasRecommended = options.any((o) => o.recommended);
    return Issue(
      id: '${issue.id}#last',
      agent: issue.agent,
      severity: issue.severity,
      message: '${issue.message} (I have searched as widely as I can.)',
      why: issue.why,
      options: [
        for (var i = 0; i < options.length; i++)
          i == 0 && !hasRecommended
              ? IssueOption(id: options[i].id, label: options[i].label, subtitle: options[i].subtitle, badge: options[i].badge, effect: options[i].effect, recommended: true)
              : options[i],
      ],
    );
  }

  // --- how well a stay suits the group ------------------------------------------

  /// How well [h] suits [needs], lower is better: needs known to fail, then
  /// needs nobody has confirmed, then needs only partly met. A hostel (shared
  /// rooms and bathrooms, rarely a lift) counts as one more unconfirmed need for
  /// a wheelchair user or an elderly traveller.
  static List<int> fitKey(HotelOption h, Set<AccessibilityNeed> needs) {
    final relevant = {for (final n in needs) if (n != AccessibilityNeed.none) n};
    int count(SupportLevel l) => relevant.where((n) => (h.access[n]?.level ?? SupportLevel.unknown) == l).length;
    final hostel = (relevant.contains(AccessibilityNeed.wheelchair) || relevant.contains(AccessibilityNeed.elderlyCare)) &&
        RegExp(r'hostel|dorm|backpacker', caseSensitive: false).hasMatch('${h.type} ${h.name}');
    return [count(SupportLevel.no), count(SupportLevel.unknown) + (hostel ? 1 : 0), count(SupportLevel.partial)];
  }

  /// [a] suits the group at least as well as [b].
  static bool fitsAsWell(HotelOption a, HotelOption b, Set<AccessibilityNeed> needs) {
    final ka = fitKey(a, needs);
    final kb = fitKey(b, needs);
    for (var i = 0; i < ka.length; i++) {
      if (ka[i] != kb[i]) return ka[i] < kb[i];
    }
    return true;
  }

  // --- helpers --------------------------------------------------------------

  static Set<AccessibilityNeed> _needs(HotelQuery q) => {
    for (final n in q.needs)
      if (n != AccessibilityNeed.none) n,
  };

  static bool _failsAny(HotelOption o, Set<AccessibilityNeed> needs) =>
      needs.any((n) => o.access[n]?.level == SupportLevel.no);

  static int _roundUp(int v, int step) => ((v + step - 1) ~/ step) * step;

  /// “wheelchair access and hearing support”, for questions.
  static String _needsPhrase(Set<AccessibilityNeed> needs) {
    final labels = [
      for (final n in needs)
        switch (n) {
          AccessibilityNeed.wheelchair => 'wheelchair access',
          AccessibilityNeed.limitedMobility => 'step-free access',
          AccessibilityNeed.visual => 'support for visual impairment',
          AccessibilityNeed.hearing => 'support for hearing impairment',
          AccessibilityNeed.elderlyCare => 'elderly-friendly access',
          AccessibilityNeed.serviceAnimal => 'a service animal',
          AccessibilityNeed.cognitiveSensory => 'sensory or cognitive needs',
          AccessibilityNeed.otherSpecial => 'your special needs',
          AccessibilityNeed.none => 'your needs',
        },
    ];
    if (labels.isEmpty) return 'your needs';
    if (labels.length == 1) return labels.single;
    return '${labels.sublist(0, labels.length - 1).join(', ')} and ${labels.last}';
  }
}
