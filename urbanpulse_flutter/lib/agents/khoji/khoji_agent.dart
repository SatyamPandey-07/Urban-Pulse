import '../../domain/access/access_rules.dart';
import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../atithi/hotel_finder.dart';
import '../bhatkanti/hotspot_finder.dart';
import '../runtime/agent_kind.dart';
import '../runtime/report.dart';
import '../runtime/task_board.dart';
import '../runtime/task_graph.dart';
import 'khoji.dart';

/// The hotspots Khoji checked, and the ones it found closed for good.
class HotspotVerification {
  const HotspotVerification({this.replacements = const {}, this.closedIds = const {}, this.checked = 0});

  final Map<String, Hotspot> replacements;
  final Set<String> closedIds;
  final int checked;
}

/// Khoji as a worker in the task graph. Atithi and Bhatkanti hand it their best
/// finds as delegated tasks (so the graph shows the edges), and get back
/// verified copies: claims with verdicts, guest reviews with their sources, and
/// access readings from those sources.
class KhojiAgent {
  KhojiAgent(this.khoji);

  final Khoji khoji;

  /// How many hotels and places are worth a check within the time-box.
  static const maxHotels = 3;
  static const maxPlaces = 3;

  // --- hotels -----------------------------------------------------------------

  Future<List<HotelOption>> verifyHotels(TaskContext parent, List<HotelOption> hotels, HotelQuery q) async {
    if (hotels.isEmpty || parent.cancelled) return hotels;
    final targets = hotels.take(maxHotels).toList();
    final needs = AccessRules.relevant(q.needs);

    final reports = await Future.wait([
      for (final h in targets)
        parent.delegate(
          TaskSpec(
            id: 'khoji.hotel.${h.id}',
            agent: AgentKind.khoji,
            title: 'Check ${_short(h.name)}',
            why: 'A listing can say anything. Khoji looks for guest reviews (especially the lower-rated ones) and checks the claims that matter to you.',
          ),
          (c) async {
            final claimNeeds = [for (final n in needs) if (_needsCheck(h, n)) n].take(2).toList();
            final f = await khoji.verify(
              KhojiRequest(
                subject: KhojiSubject.hotel,
                id: h.id,
                name: h.name,
                destination: q.destination,
                claims: [
                  for (final cl in h.claims.where((c) => !c.isReviews).take(3)) cl.text,
                  for (final n in claimNeeds) _needClaim(n),
                ],
                needs: needs,
                pageUrl: h.tripAdvisorUrl,
              ),
              isCancelled: () => c.cancelled,
            );
            return AgentReport(
              agent: c.agent,
              status: f.isEmpty ? ReportStatus.degraded : ReportStatus.done,
              summary: _summary(h.name, f),
              payload: f,
              why: f.methods.isEmpty ? 'No web evidence could be found, so nothing is marked as verified.' : 'Checked with ${f.methods.join(' and ')}.',
            );
          },
          say: 'asked Khoji to verify ${_short(h.name)}',
        ),
    ]);

    final byId = <String, HotelOption>{};
    for (var i = 0; i < targets.length; i++) {
      final f = reports[i].payload;
      if (f is KhojiFinding && !f.isEmpty) byId[targets[i].id] = _applyToHotel(targets[i], f, needs);
    }
    return [for (final h in hotels) byId[h.id] ?? h];
  }

  static bool _needsCheck(HotelOption h, AccessibilityNeed n) {
    final l = h.access[n]?.level ?? SupportLevel.unknown;
    return l == SupportLevel.unknown || l == SupportLevel.partial;
  }

  /// The claim Khoji is asked about for a need nothing has settled.
  static String _needClaim(AccessibilityNeed n) => switch (n) {
    AccessibilityNeed.wheelchair => 'Suitable for wheelchair users (step-free access, accessible bathroom)',
    AccessibilityNeed.limitedMobility => 'Easy for guests who find walking or stairs hard',
    AccessibilityNeed.visual => 'Suitable for guests with visual impairment',
    AccessibilityNeed.hearing => 'Suitable for guests with hearing impairment',
    AccessibilityNeed.elderlyCare => 'Comfortable for elderly guests (lift or ground floor, easy access)',
    AccessibilityNeed.serviceAnimal => 'Allows service animals',
    AccessibilityNeed.cognitiveSensory => 'Calm and suitable for guests with sensory or cognitive needs',
    AccessibilityNeed.otherSpecial => 'Suitable for guests with special needs',
    AccessibilityNeed.none => 'No special needs',
  };

  static AccessibilityNeed? _needOf(String claim) {
    for (final n in AccessibilityNeed.values) {
      if (n != AccessibilityNeed.none && _needClaim(n) == claim) return n;
    }
    return null;
  }

  HotelOption _applyToHotel(HotelOption h, KhojiFinding f, Set<AccessibilityNeed> needs) {
    final access = {...h.access};

    void mergeNeed(AccessibilityNeed n, NeedSupport s) {
      final prev = access[n];
      access[n] = prev == null ? s : AccessRules.merge(prev, s);
    }

    // Guest reviews and pages that speak about a need.
    for (final e in f.access.entries) {
      if (needs.contains(e.key)) mergeNeed(e.key, e.value);
    }

    // A verdict on "suitable for X" becomes a reading of the need.
    final claims = <Claim>[];
    for (final c in f.claims) {
      final n = _needOf(c.text);
      if (n != null) {
        final s = _supportFromVerdict(n, c);
        if (s != null && needs.contains(n)) mergeNeed(n, s);
        // The synthetic wording is Khoji's, not the listing's: keep it as a claim only when it settled something.
        if (c.verdict != Verdict.unverified) claims.add(c);
        continue;
      }
      claims.add(c);
    }
    // Keep listing claims Khoji did not touch.
    final touched = {for (final c in claims) c.text};
    final merged = [
      for (final old in h.claims)
        if (!old.isReviews && !touched.contains(old.text)) old,
      ...claims,
      ?f.reviews,
    ];
    return h.copyWith(access: access, claims: merged);
  }

  static NeedSupport? _supportFromVerdict(AccessibilityNeed n, Claim c) {
    final level = switch (c.verdict) {
      Verdict.confirmed => SupportLevel.yes,
      Verdict.mixed => SupportLevel.partial,
      Verdict.contradicted => SupportLevel.no,
      Verdict.unverified => null,
    };
    if (level == null) return null;
    final src = c.sources.firstOrNull;
    return NeedSupport(
      need: n,
      level: level,
      detail: src?.snippet == null || src!.snippet!.isEmpty ? 'Checked by Khoji against web sources' : 'A source says: ${src.snippet}',
      provenance: Provenance(source: 'Web sources checked by Khoji', url: src?.url, confidence: c.confidence),
    );
  }

  // --- hotspots ------------------------------------------------------------------------

  /// Checks the places most in need of it: new and trending ones (which may not
  /// exist any more) and the best ones whose access nobody has confirmed.
  Future<HotspotVerification> verifyHotspots(TaskContext parent, HotspotSearchResult r) async {
    if (r.selected.isEmpty || parent.cancelled) return const HotspotVerification();
    final needs = AccessRules.relevant(r.query.needs);
    final byNeed = [
      for (final h in r.selected)
        if (needs.isNotEmpty && needs.any((n) => (h.access[n]?.level ?? SupportLevel.unknown) == SupportLevel.unknown) && h.kind != HotspotKind.food) h,
    ];
    final picks = <Hotspot>[
      for (final h in r.selected) if (h.isTrending) h,
      ...byNeed,
    ];
    final seen = <String>{};
    final targets = [for (final h in picks) if (seen.add(h.id)) h].take(maxPlaces).toList();
    if (targets.isEmpty) return const HotspotVerification();

    final reports = await Future.wait([
      for (final h in targets)
        parent.delegate(
          TaskSpec(
            id: 'khoji.place.${h.id}',
            agent: AgentKind.khoji,
            title: 'Check ${_short(h.name)}',
            why: h.isTrending
                ? 'New places can close or be less good than the buzz. Khoji checks that ${h.name} is real and what visitors say.'
                : 'Nobody has confirmed whether ${h.name} works for your access needs, so Khoji looks for evidence.',
          ),
          (c) async {
            final claimNeeds = [for (final n in needs) if ((h.access[n]?.level ?? SupportLevel.unknown) == SupportLevel.unknown) n].take(2).toList();
            final f = await khoji.verify(
              KhojiRequest(
                subject: KhojiSubject.hotspot,
                id: h.id,
                name: h.name,
                destination: r.query.destination,
                claims: [for (final n in claimNeeds) _placeClaim(n)],
                needs: needs,
                wikiTitle: h.sources.where((s) => s.source == 'Wikipedia').firstOrNull?.title,
                checkClosed: true,
              ),
              isCancelled: () => c.cancelled,
            );
            return AgentReport(
              agent: c.agent,
              status: f.isEmpty ? ReportStatus.degraded : ReportStatus.done,
              summary: f.closed == true ? '${h.name} appears to have closed for good' : _summary(h.name, f),
              payload: f,
              why: f.closed == true
                  ? 'A page Khoji found says it is permanently closed, so Yatri will replace it.'
                  : (f.methods.isEmpty ? 'No web evidence could be found, so nothing is marked as verified.' : 'Checked with ${f.methods.join(' and ')}.'),
            );
          },
          say: 'asked Khoji to verify ${_short(h.name)}',
        ),
    ]);

    final replacements = <String, Hotspot>{};
    final closed = <String>{};
    for (var i = 0; i < targets.length; i++) {
      final f = reports[i].payload;
      if (f is! KhojiFinding) continue;
      if (f.closed == true) {
        closed.add(targets[i].id);
        continue;
      }
      if (!f.isEmpty) replacements[targets[i].id] = _applyToHotspot(targets[i], f, needs);
    }
    if (closed.isNotEmpty) {
      parent.say(
        'found ${closed.length} place${closed.length == 1 ? '' : 's'} closed for good and replaced ${closed.length == 1 ? 'it' : 'them'}',
        why: 'Nothing that no longer exists belongs in a plan.',
        kind: FeedKind.verify,
      );
    }
    return HotspotVerification(replacements: replacements, closedIds: closed, checked: targets.length);
  }

  static String _placeClaim(AccessibilityNeed n) => switch (n) {
    AccessibilityNeed.wheelchair => 'Accessible to wheelchair users (step-free, ramps)',
    AccessibilityNeed.limitedMobility => 'Manageable for visitors who find walking or steps hard',
    AccessibilityNeed.visual => 'Suitable for visitors with visual impairment',
    AccessibilityNeed.hearing => 'Suitable for visitors with hearing impairment',
    AccessibilityNeed.elderlyCare => 'Comfortable for elderly visitors (seating, easy paths)',
    AccessibilityNeed.serviceAnimal => 'Allows service animals',
    AccessibilityNeed.cognitiveSensory => 'Quiet or calm enough for visitors with sensory or cognitive needs',
    AccessibilityNeed.otherSpecial => 'Suitable for visitors with special needs',
    AccessibilityNeed.none => 'No special needs',
  };

  static AccessibilityNeed? _placeNeedOf(String claim) {
    for (final n in AccessibilityNeed.values) {
      if (n != AccessibilityNeed.none && _placeClaim(n) == claim) return n;
    }
    return null;
  }

  Hotspot _applyToHotspot(Hotspot h, KhojiFinding f, Set<AccessibilityNeed> needs) {
    final access = {...h.access};
    void mergeNeed(AccessibilityNeed n, NeedSupport s) {
      final prev = access[n];
      access[n] = prev == null ? s : AccessRules.merge(prev, s);
    }

    for (final e in f.access.entries) {
      if (needs.contains(e.key)) mergeNeed(e.key, e.value);
    }
    final claims = <Claim>[];
    for (final c in f.claims) {
      final n = _placeNeedOf(c.text);
      if (n != null) {
        final s = _supportFromVerdict(n, c);
        if (s != null && needs.contains(n)) mergeNeed(n, s);
        if (c.verdict != Verdict.unverified) claims.add(c);
      } else {
        claims.add(c);
      }
    }
    final sources = [...h.sources];
    for (final s in f.sources) {
      if (!sources.any((x) => x.url == s.url)) sources.add(s);
    }
    return h.copyWith(access: access, claims: [...h.claims, ...claims, ?f.reviews], sources: sources);
  }

  // --- helpers ---------------------------------------------------------------------------

  static String _short(String name) => name.length <= 28 ? name : '${name.substring(0, 27)}…';

  static String _summary(String name, KhojiFinding f) {
    if (f.isEmpty) return 'found no web evidence for ${_short(name)}';
    final parts = <String>[
      if (f.confirmed > 0) '${f.confirmed} claim${f.confirmed == 1 ? '' : 's'} confirmed',
      if (f.contradicted > 0) '${f.contradicted} contradicted',
      if (f.reviews != null) '${f.reviews!.reviewQuotes.length} review${f.reviews!.reviewQuotes.length == 1 ? '' : 's'}',
    ];
    return parts.isEmpty ? 'checked ${_short(name)}' : '${_short(name)}: ${parts.join(', ')}';
  }
}
