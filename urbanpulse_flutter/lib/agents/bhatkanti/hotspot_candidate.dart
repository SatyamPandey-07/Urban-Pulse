import 'package:latlong2/latlong.dart';

import '../../models/itinerary/itinerary_parts.dart';
import '../../models/trip_brief.dart';
import '../../services/data/http_util.dart';
import '../atithi/hotel_candidate.dart';
import '../runtime/report.dart';

/// A place under consideration, built up from several sources before it
/// becomes a [Hotspot]. Mutable on purpose: sources add to it as they agree.
class HotspotCandidate {
  HotspotCandidate({
    required this.name,
    required this.location,
    required String source,
    this.kind,
    this.why,
    this.visitMinutes,
    this.feeInr,
    this.feeIsEstimated = false,
    this.openingHours,
    this.isOutdoor,
    this.isTrending = false,
    Map<String, String>? tags,
    this.wikiTitle,
    this.wikiUrl,
    this.website,
    this.osmId,
    this.geoapifyId,
    List<SourceRef>? sources,
  }) : tags = tags ?? {},
       sourceNames = {source},
       sources = sources ?? [];

  String name;
  LatLng location;
  HotspotKind? kind;
  String? why;
  int? visitMinutes;
  int? feeInr;
  bool feeIsEstimated;
  String? openingHours;
  bool? isOutdoor;
  bool isTrending;
  final Map<String, String> tags;
  String? wikiTitle;
  String? wikiUrl;
  String? website;
  String? osmId;
  String? geoapifyId;

  /// How many independent web results named this place.
  int webMentions = 0;

  /// The model's 0..1 "essential for a first visit" rating, when asked.
  double? importance;
  bool kindIsEstimated = false;
  bool whyIsEstimated = false;

  final Set<String> sourceNames;
  final List<SourceRef> sources;
  final Map<AccessibilityNeed, NeedSupport> access = {};

  String get id => osmId ?? geoapifyId ?? 'web:${HotelCandidates.normalize(name).replaceAll(' ', '_')}';

  /// Folds [other] (the same place from another source) into this one.
  void absorb(HotspotCandidate other) {
    if (other.name.length > name.length && HotelCandidates.similarity(name, other.name) >= 0.99) {
      // same words; keep the fuller spelling
      name = other.name;
    }
    kind ??= other.kind;
    why ??= other.why;
    visitMinutes ??= other.visitMinutes;
    if (feeInr == null || (feeIsEstimated && !other.feeIsEstimated && other.feeInr != null)) {
      feeInr = other.feeInr ?? feeInr;
      feeIsEstimated = other.feeInr == null ? feeIsEstimated : other.feeIsEstimated;
    }
    openingHours ??= other.openingHours;
    isOutdoor ??= other.isOutdoor;
    isTrending = isTrending || other.isTrending;
    for (final e in other.tags.entries) {
      tags.putIfAbsent(e.key, () => e.value);
    }
    wikiTitle ??= other.wikiTitle;
    wikiUrl ??= other.wikiUrl;
    website ??= other.website;
    osmId ??= other.osmId;
    geoapifyId ??= other.geoapifyId;
    webMentions += other.webMentions;
    sourceNames.addAll(other.sourceNames);
    for (final s in other.sources) {
      if (!sources.any((x) => x.url == s.url)) sources.add(s);
    }
    for (final e in other.access.entries) {
      final prev = access[e.key];
      access[e.key] = prev == null ? e.value : _mergeAccess(prev, e.value);
    }
  }

  static NeedSupport _mergeAccess(NeedSupport a, NeedSupport b) {
    if (a.level == SupportLevel.unknown) return b;
    if (b.level == SupportLevel.unknown) return a;
    return a.provenance.confidence >= b.provenance.confidence ? a : b;
  }
}

abstract final class HotspotCandidates {
  /// Whether [a] and [b] are the same place: near-identical names close by, or
  /// very similar names within a few hundred metres.
  static bool sameSpot(HotspotCandidate a, HotspotCandidate b) {
    final na = HotelCandidates.normalize(a.name);
    final nb = HotelCandidates.normalize(b.name);
    if (na.isEmpty || nb.isEmpty) return false;
    final km = haversineKm(a.location.latitude, a.location.longitude, b.location.latitude, b.location.longitude);
    if (na == nb) return km <= 3;
    if (sameName(a.name, b.name) && km <= 1.5) return true;
    final sim = HotelCandidates.similarity(a.name, b.name);
    return (sim >= 0.75 && km <= 0.6) || (sim >= 0.9 && km <= 2);
  }

  static const _minor = {'the', 'of', 'and', 'a', 'an', 'at', 'in', 'on', 'to'};

  /// The distinctive words of a place's name, without qualifiers such as
  /// "(exterior view)", "[closed]" or ", Jaipur".
  static Set<String> coreWords(String name) {
    final core = name.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ').split(RegExp(r',| - | – | \| ')).first;
    return {
      for (final t in core.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
        if (t.length > 1 && !_minor.contains(t)) t,
    };
  }

  /// Two names for the same place: "Hawa Mahal" and "Hawa Mahal (exterior
  /// view)", "City Palace" and "City Palace of Jaipur". The shorter name must
  /// have at least two distinctive words, so "Palace" alone matches nothing.
  static bool sameName(String a, String b) {
    final ca = coreWords(a);
    final cb = coreWords(b);
    if (ca.isEmpty || cb.isEmpty) return false;
    final (small, big) = ca.length <= cb.length ? (ca, cb) : (cb, ca);
    return small.length >= 2 && big.containsAll(small);
  }

  static List<HotspotCandidate> merge(Iterable<HotspotCandidate> all) {
    final out = <HotspotCandidate>[];
    for (final c in all) {
      final match = out.where((o) => sameSpot(o, c)).firstOrNull;
      if (match == null) {
        out.add(c);
      } else {
        match.absorb(c);
      }
    }
    return out;
  }

  // --- classification ---------------------------------------------------------

  /// A kind from OpenStreetMap tags and Geoapify categories, or null.
  static HotspotKind? kindFromTags(Map<String, String> t, [Iterable<String> categories = const []]) {
    final cats = categories.join(' ').toLowerCase();
    final tourism = t['tourism'] ?? '';
    final historic = t['historic'] ?? '';
    final leisure = t['leisure'] ?? '';
    final natural = t['natural'] ?? '';
    final amenity = t['amenity'] ?? '';

    if (amenity == 'place_of_worship' || cats.contains('religion') || const {'temple', 'church', 'monastery', 'shrine'}.contains(historic)) {
      return HotspotKind.religious;
    }
    if (tourism == 'viewpoint' || cats.contains('viewpoint')) return HotspotKind.viewpoint;
    if (tourism == 'museum' || tourism == 'gallery' || cats.contains('museum') || cats.contains('entertainment.culture')) {
      return HotspotKind.culture;
    }
    if (historic.isNotEmpty || t.containsKey('heritage') || cats.contains('heritage')) return HotspotKind.heritage;
    if (natural.isNotEmpty || const {'park', 'garden', 'nature_reserve'}.contains(leisure) || cats.contains('natural') || cats.contains('leisure.park')) {
      return HotspotKind.nature;
    }
    if (tourism == 'zoo' || tourism == 'theme_park' || cats.contains('amusement')) return HotspotKind.adventure;
    if (cats.contains('catering') || const {'restaurant', 'cafe', 'food_court'}.contains(amenity)) return HotspotKind.food;
    if (cats.contains('commercial') || t.containsKey('shop')) return HotspotKind.shopping;
    if (tourism == 'attraction' || tourism == 'artwork' || cats.contains('tourism')) return null;
    return null;
  }

  /// Guess a kind from words in the name ("Fort", "Falls", "Temple").
  static HotspotKind? kindFromName(String name) {
    final n = name.toLowerCase();
    bool has(List<String> words) => words.any((w) => RegExp('\\b$w\\b').hasMatch(n));
    if (has(['temple', 'mandir', 'church', 'cathedral', 'mosque', 'masjid', 'gurudwara', 'gurdwara', 'monastery', 'dargah', 'ghat', 'shrine', 'basilica', 'synagogue'])) {
      return HotspotKind.religious;
    }
    if (has(['fort', 'palace', 'mahal', 'tomb', 'ruins', 'monument', 'memorial', 'stepwell', 'baoli', 'gate', 'citadel', 'castle', 'haveli', 'minar'])) {
      return HotspotKind.heritage;
    }
    if (has(['museum', 'gallery', 'theatre', 'theater', 'cultural', 'heritage'])) return HotspotKind.culture;
    if (has(['falls', 'waterfall', 'lake', 'park', 'garden', 'gardens', 'beach', 'hill', 'hills', 'valley', 'peak', 'sanctuary', 'reserve', 'forest', 'national', 'dam', 'river', 'cave', 'caves', 'estate', 'plantation', 'island'])) {
      return HotspotKind.nature;
    }
    if (has(['viewpoint', 'point', 'sunset', 'sunrise', 'lookout', 'top'])) return HotspotKind.viewpoint;
    if (has(['zoo', 'safari', 'trek', 'trail', 'rafting', 'adventure', 'ropeway', 'amusement', 'water park'])) return HotspotKind.adventure;
    if (has(['market', 'bazaar', 'bazar', 'mall', 'shopping'])) return HotspotKind.shopping;
    if (has(['restaurant', 'cafe', 'dhaba', 'kitchen', 'bakery', 'eatery', 'thali', 'sweets', 'biryani'])) return HotspotKind.food;
    return null;
  }

  static HotspotKind? parseKind(Object? v) {
    final s = '$v'.toLowerCase().trim();
    for (final k in HotspotKind.values) {
      if (k.name == s) return k;
    }
    if (s == 'trending') return null;
    return null;
  }

  /// Typical time on site by kind, in minutes.
  static int defaultVisitMinutes(HotspotKind k) => switch (k) {
    HotspotKind.heritage => 90,
    HotspotKind.nature => 100,
    HotspotKind.culture => 80,
    HotspotKind.religious => 50,
    HotspotKind.food => 60,
    HotspotKind.adventure => 150,
    HotspotKind.viewpoint => 40,
    HotspotKind.shopping => 70,
    HotspotKind.trending => 60,
    HotspotKind.other => 60,
  };

  static bool defaultOutdoor(HotspotKind k) => switch (k) {
    HotspotKind.culture || HotspotKind.food || HotspotKind.shopping => false,
    _ => true,
  };

  /// Whether the OSM `fee` / `charge` tags say the place costs money: a value
  /// in rupees, 0 when free, or null when unknown.
  static int? feeFromTags(Map<String, String> t) {
    final fee = (t['fee'] ?? '').toLowerCase();
    final charge = t['charge'] ?? '';
    final digits = RegExp(r'(\d{1,5})').firstMatch(charge)?.group(1);
    if (digits != null && fee != 'no') return int.tryParse(digits);
    if (fee == 'no') return 0;
    return null;
  }

  /// Points before any model input: how likely this is a sight people come for.
  static double baseScore(HotspotCandidate c, LatLng center, double radiusKm) {
    var s = 0.1;
    if (c.wikiTitle != null || c.tags.containsKey('wikipedia')) s += 0.32;
    if (c.tags.containsKey('wikidata')) s += 0.08;
    final tourism = c.tags['tourism'] ?? '';
    if (tourism == 'attraction') s += 0.14;
    if (tourism == 'museum' || tourism == 'viewpoint') s += 0.08;
    if (c.tags.containsKey('historic') || c.tags.containsKey('heritage')) s += 0.1;
    if (c.tags.containsKey('name:en') || c.tags.containsKey('website')) s += 0.03;
    s += (c.webMentions.clamp(0, 3)) * 0.13;
    if (c.sourceNames.length >= 2) s += 0.06;
    final km = haversineKm(center.latitude, center.longitude, c.location.latitude, c.location.longitude);
    s -= 0.12 * (km / (radiusKm <= 0 ? 1 : radiusKm)).clamp(0, 1.5);
    return s.clamp(0, 1.2);
  }

  /// A one-sentence "why" from a longer text: its first sentence, trimmed.
  static String firstSentence(String? text, {int max = 170}) {
    final t = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.isEmpty) return '';
    final m = RegExp(r'^(.{20,}?[.!?])(\s|$)').firstMatch(t);
    var s = m?.group(1) ?? t;
    if (s.length > max) s = '${s.substring(0, max - 1).trimRight()}…';
    return s;
  }

  /// Evidence trail for the finished [Hotspot].
  static Provenance provenanceOf(HotspotCandidate c) {
    final real = c.sourceNames.where((s) => s != 'AI estimate').toList();
    if (real.isEmpty) return Provenance.aiEstimate;
    return Provenance(source: real.join(' + '), confidence: (0.55 + 0.1 * real.length).clamp(0, 0.95));
  }
}
