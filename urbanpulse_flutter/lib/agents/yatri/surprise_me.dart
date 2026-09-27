import 'dart:async';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../../models/itinerary/itinerary.dart';
import '../../models/trip_brief.dart';
import '../../services/data/forecast_client.dart';
import '../runtime/agent_kind.dart';
import '../runtime/llm_pool.dart';

/// A short-trip destination Surprise Me can pick from.
class SurprisePlace {
  const SurprisePlace(this.name, this.state, this.lat, this.lon, this.tags, {this.access = 1, this.costLevel = 2, this.highlights = const []});

  final String name;
  final String state;
  final double lat;
  final double lon;

  /// hills, beach, heritage, spiritual, nature, wildlife, adventure, lakes, food.
  final Set<String> tags;

  /// 0 hard for wheelchairs and the elderly (steep, stairs), 1 mixed, 2 easy.
  final int access;

  /// 1 budget, 2 moderate, 3 pricey.
  final int costLevel;
  final List<String> highlights;

  LatLng get point => LatLng(lat, lon);
}

/// One pick, ready to hand to Yatri.
class SurprisePick {
  const SurprisePick({
    required this.place,
    required this.distanceKm,
    required this.nights,
    required this.why,
    required this.highlights,
    required this.estimateInr,
    required this.brief,
    this.weather,
    this.rainy = false,
  });

  final SurprisePlace place;
  final int distanceKm;
  final int nights;

  /// Why it suits this traveller, tied to their past trips.
  final String why;
  final List<String> highlights;
  final int estimateInr;
  final String? weather;
  final bool rainy;
  final TripBrief brief;
}

/// What past trips say about this traveller.
class TravelProfile {
  const TravelProfile({
    required this.home,
    required this.visited,
    required this.trips,
    this.last,
    this.styles = const {},
    this.dailyPerPersonInr,
  });

  final String home;

  /// Destination keys already planned or taken.
  final Set<String> visited;
  final int trips;

  /// The most recent brief: group, needs, pace, transport and food carry over.
  final TripBrief? last;
  final Map<TripStyle, int> styles;
  final int? dailyPerPersonInr;

  bool get mobility => last?.accessibilityNeeds.any((n) => n == AccessibilityNeed.wheelchair || n == AccessibilityNeed.limitedMobility || n == AccessibilityNeed.elderlyCare) ?? false;

  TripStyle? get favouriteStyle {
    if (styles.isEmpty) return null;
    return (styles.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  static TravelProfile from({required String home, required List<TripBrief> briefs, required List<Itinerary> itineraries}) {
    final all = [...briefs, for (final it in itineraries) ?it.brief];
    all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final visited = <String>{
      for (final b in all) if (b.destination != null) _key(b.destination!),
      for (final it in itineraries) _key(it.destination),
    };
    final styles = <TripStyle, int>{};
    final daily = <int>[];
    for (final b in all) {
      if (b.style != null) styles[b.style!] = (styles[b.style!] ?? 0) + 1;
      final max = b.budgetMaxInr;
      final people = math.max(1, b.travellerCount ?? 1);
      if (max != null && b.days > 0) daily.add((max / people / b.days).round());
    }
    daily.sort();
    return TravelProfile(
      home: home,
      visited: visited,
      trips: {for (final b in all) b.id}.length,
      last: all.firstOrNull,
      styles: styles,
      dailyPerPersonInr: daily.isEmpty ? null : daily[daily.length ~/ 2],
    );
  }

  static String _key(String d) => d.split(',').first.trim().toLowerCase();

  String get summary {
    final b = last;
    final parts = <String>[
      'Home: $home',
      'Trips planned before: $trips',
      if (visited.isNotEmpty) 'Already been or planned: ${visited.join(', ')}',
      if (favouriteStyle != null) 'Favourite trip style: ${favouriteStyle!.label}',
      if (b != null) ...[
        'Last group: ${b.travellerCount ?? 1} (${[if ((b.adults ?? 0) > 0) '${b.adults} adults', if ((b.seniors ?? 0) > 0) '${b.seniors} seniors', if ((b.children ?? 0) > 0) '${b.children} children'].join(', ')})',
        if (b.pace != null) 'Pace: ${b.pace!.label}',
        if (b.accessibilityNeeds.any((n) => n != AccessibilityNeed.none)) 'Access needs: ${b.accessibilityNeeds.where((n) => n != AccessibilityNeed.none).map((n) => n.name).join(', ')}',
        if (b.transportModes.isNotEmpty) 'Usually travels by: ${b.transportModes.map((m) => m.label).join(', ')}',
        if (b.stayTypes.isNotEmpty) 'Stays: ${b.stayTypes.map((s) => s.label).join(', ')}',
        if (b.dietary.isNotEmpty) 'Food: ${b.dietary.map((d) => d.name).join(', ')}',
        'Sustainability: ${b.sustainability.label}',
      ],
      if (dailyPerPersonInr != null) 'Usual budget: about ₹$dailyPerPersonInr per person per day',
    ];
    return parts.join('\n');
  }
}

enum SurpriseStep { profile, shortlist, weather, budget, pick }

/// Surprise Me: Yatri and the agents choose a short trip for this traveller
/// from what their past trips say about them.
class SurpriseMe {
  SurpriseMe({this.llm, this.forecast, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final AgentLlm? llm;
  final ForecastClient? forecast;
  final DateTime Function() _now;

  /// Short trips across India, with coordinates for "within reach".
  static const places = [
    SurprisePlace('Lonavala', 'Maharashtra', 18.7546, 73.4062, {'hills', 'nature'}, access: 1, highlights: ['Tiger Point views', 'Bhushi Dam', 'Karla Caves']),
    SurprisePlace('Mahabaleshwar', 'Maharashtra', 17.9307, 73.6477, {'hills', 'nature', 'food'}, access: 1, highlights: ['Venna Lake', 'strawberry farms', 'Arthur’s Seat']),
    SurprisePlace('Alibaug', 'Maharashtra', 18.6414, 72.8722, {'beach', 'heritage'}, access: 2, highlights: ['Kolaba Fort at low tide', 'Varsoli beach', 'seafood shacks']),
    SurprisePlace('Nashik', 'Maharashtra', 19.9975, 73.7898, {'spiritual', 'food', 'heritage'}, access: 2, highlights: ['Sula vineyards', 'Panchavati ghats', 'Trimbakeshwar']),
    SurprisePlace('Aurangabad', 'Maharashtra', 19.8762, 75.3433, {'heritage'}, access: 1, highlights: ['Ellora Caves', 'Bibi Ka Maqbara', 'Daulatabad Fort']),
    SurprisePlace('Matheran', 'Maharashtra', 18.9866, 73.2707, {'hills', 'nature'}, access: 0, costLevel: 2, highlights: ['toy train', 'car-free trails', 'Panorama Point']),
    SurprisePlace('Tarkarli', 'Maharashtra', 16.0299, 73.4719, {'beach', 'adventure'}, access: 1, highlights: ['snorkelling', 'Sindhudurg Fort', 'Konkan food']),
    SurprisePlace('Goa', 'Goa', 15.4909, 73.8278, {'beach', 'heritage', 'food'}, access: 2, costLevel: 3, highlights: ['Fontainhas lanes', 'Old Goa churches', 'Palolem beach']),
    SurprisePlace('Gokarna', 'Karnataka', 14.5479, 74.3188, {'beach', 'spiritual'}, access: 1, highlights: ['Om Beach', 'Mahabaleshwar temple', 'sunset cliffs']),
    SurprisePlace('Hampi', 'Karnataka', 15.3350, 76.4600, {'heritage', 'adventure'}, access: 1, highlights: ['Vittala Temple', 'coracle rides', 'Matanga Hill sunrise']),
    SurprisePlace('Coorg', 'Karnataka', 12.4244, 75.7382, {'hills', 'nature', 'food'}, access: 1, highlights: ['coffee estates', 'Abbey Falls', 'Raja’s Seat']),
    SurprisePlace('Mysuru', 'Karnataka', 12.2958, 76.6394, {'heritage', 'food'}, access: 2, highlights: ['Mysore Palace', 'Devaraja Market', 'Brindavan Gardens']),
    SurprisePlace('Chikmagalur', 'Karnataka', 13.3161, 75.7720, {'hills', 'nature'}, access: 1, highlights: ['Mullayanagiri', 'coffee trails', 'Hebbe Falls']),
    SurprisePlace('Pondicherry', 'Puducherry', 11.9416, 79.8083, {'beach', 'heritage', 'food'}, access: 2, highlights: ['French Quarter', 'Auroville', 'Promenade']),
    SurprisePlace('Ooty', 'Tamil Nadu', 11.4102, 76.6950, {'hills', 'nature'}, access: 1, highlights: ['Nilgiri toy train', 'Botanical Garden', 'tea factories']),
    SurprisePlace('Kodaikanal', 'Tamil Nadu', 10.2381, 77.4892, {'hills', 'lakes'}, access: 1, highlights: ['Kodai Lake', 'Coaker’s Walk', 'pine forests']),
    SurprisePlace('Munnar', 'Kerala', 10.0889, 77.0595, {'hills', 'nature'}, access: 1, highlights: ['tea estates', 'Eravikulam', 'Mattupetty Dam']),
    SurprisePlace('Alleppey', 'Kerala', 9.4981, 76.3388, {'lakes', 'nature', 'food'}, access: 2, costLevel: 3, highlights: ['houseboat on the backwaters', 'Marari beach', 'toddy shops']),
    SurprisePlace('Jaipur', 'Rajasthan', 26.9124, 75.7873, {'heritage', 'food'}, access: 1, highlights: ['City Palace', 'Hawa Mahal', 'Johari Bazaar']),
    SurprisePlace('Udaipur', 'Rajasthan', 24.5854, 73.7125, {'heritage', 'lakes'}, access: 1, costLevel: 3, highlights: ['Lake Pichola', 'City Palace', 'Bagore ki Haveli']),
    SurprisePlace('Pushkar', 'Rajasthan', 26.4899, 74.5511, {'spiritual', 'heritage'}, access: 1, costLevel: 1, highlights: ['Pushkar Lake ghats', 'Brahma temple', 'desert sunset']),
    SurprisePlace('Mount Abu', 'Rajasthan', 24.5926, 72.7156, {'hills', 'spiritual', 'lakes'}, access: 1, highlights: ['Dilwara temples', 'Nakki Lake', 'Sunset Point']),
    SurprisePlace('Agra', 'Uttar Pradesh', 27.1767, 78.0081, {'heritage'}, access: 2, highlights: ['Taj Mahal at sunrise', 'Agra Fort', 'Mehtab Bagh']),
    SurprisePlace('Varanasi', 'Uttar Pradesh', 25.3176, 82.9739, {'spiritual', 'heritage', 'food'}, access: 0, costLevel: 1, highlights: ['Ganga Aarti', 'boat at dawn', 'Sarnath']),
    SurprisePlace('Rishikesh', 'Uttarakhand', 30.0869, 78.2676, {'spiritual', 'adventure', 'nature'}, access: 1, costLevel: 1, highlights: ['Triveni Ghat aarti', 'river rafting', 'Beatles Ashram']),
    SurprisePlace('Mussoorie', 'Uttarakhand', 30.4598, 78.0644, {'hills', 'nature'}, access: 1, highlights: ['Mall Road', 'Kempty Falls', 'Landour']),
    SurprisePlace('Nainital', 'Uttarakhand', 29.3919, 79.4542, {'hills', 'lakes'}, access: 1, highlights: ['Naini Lake', 'Snow View Point', 'Tiffin Top']),
    SurprisePlace('Shimla', 'Himachal Pradesh', 31.1048, 77.1734, {'hills', 'heritage'}, access: 1, highlights: ['The Ridge', 'Kalka-Shimla railway', 'Jakhu']),
    SurprisePlace('Amritsar', 'Punjab', 31.6340, 74.8723, {'spiritual', 'heritage', 'food'}, access: 2, costLevel: 1, highlights: ['Golden Temple', 'Wagah border', 'Amritsari kulcha']),
    SurprisePlace('Khajuraho', 'Madhya Pradesh', 24.8318, 79.9199, {'heritage'}, access: 2, highlights: ['Western temples', 'light and sound show', 'Panna safari']),
    SurprisePlace('Pachmarhi', 'Madhya Pradesh', 22.4674, 78.4346, {'hills', 'nature', 'adventure'}, access: 0, highlights: ['Bee Falls', 'Pandav Caves', 'Dhoopgarh sunset']),
    SurprisePlace('Darjeeling', 'West Bengal', 27.0410, 88.2663, {'hills', 'nature'}, access: 0, highlights: ['Tiger Hill sunrise', 'toy train', 'tea gardens']),
    SurprisePlace('Shillong', 'Meghalaya', 25.5788, 91.8933, {'hills', 'nature'}, access: 1, highlights: ['Umiam Lake', 'Elephant Falls', 'Police Bazaar food']),
    SurprisePlace('Puri', 'Odisha', 19.8135, 85.8312, {'beach', 'spiritual'}, access: 2, costLevel: 1, highlights: ['Jagannath Temple', 'Konark Sun Temple', 'Chilika Lake']),
    SurprisePlace('Ranthambore', 'Rajasthan', 26.0173, 76.5026, {'wildlife', 'nature'}, access: 2, costLevel: 3, highlights: ['tiger safari', 'Ranthambore Fort', 'Padam Talao']),
    SurprisePlace('Jim Corbett', 'Uttarakhand', 29.5300, 78.7747, {'wildlife', 'nature'}, access: 2, costLevel: 3, highlights: ['jeep safari', 'Garjiya temple', 'Kosi river']),
  ];

  static const _styleTags = {
    TripStyle.leisure: {'beach', 'lakes', 'hills'},
    TripStyle.family: {'hills', 'beach', 'wildlife'},
    TripStyle.pilgrimage: {'spiritual'},
    TripStyle.adventure: {'adventure', 'hills'},
    TripStyle.heritage: {'heritage'},
    TripStyle.nature: {'nature', 'wildlife', 'hills'},
    TripStyle.workation: {'hills', 'beach'},
  };

  /// Runs the agents; [onStep] reports each one as it finishes.
  Future<List<SurprisePick>> pick(
    TravelProfile p, {
    required LatLng home,
    Set<String> exclude = const {},
    void Function(SurpriseStep step, String detail)? onStep,
  }) async {
    final (start, nights) = _weekend(p);
    onStep?.call(
      SurpriseStep.profile,
      p.trips == 0 ? 'No past trips yet: picking for a first weekend away.' : 'Read ${p.trips} past trip${p.trips == 1 ? '' : 's'}${p.favouriteStyle == null ? '' : ': you like ${p.favouriteStyle!.label.toLowerCase()}'}.',
    );

    // Bhatkanti: places within weekend reach that fit the traveller.
    final scored = <(SurprisePlace, double, int)>[];
    for (final place in places) {
      if (exclude.contains(place.name)) continue;
      final km = (const Distance().as(LengthUnit.Kilometer, home, place.point) * 1.25).round(); // by road
      if (km < 40) continue; // that is home, not a trip
      scored.add((place, _score(p, place, km), km));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final shortlist = scored.take(8).toList();
    onStep?.call(SurpriseStep.shortlist, 'Shortlisted ${shortlist.map((s) => s.$1.name).take(5).join(', ')}${shortlist.length > 5 ? '…' : ''}.');

    // Raah: the weekend weather at each.
    final weather = <String, (String, bool)>{};
    final fc = forecast;
    if (fc != null) {
      await Future.wait([
        for (final (place, _, _) in shortlist)
          fc
              .outlook(place.lat, place.lon, start, start.add(Duration(days: nights)), today: _now())
              .timeout(const Duration(seconds: 12))
              .then((days) {
                if (days.isEmpty) return;
                final max = days.map((d) => d.tempMaxC ?? 0).reduce(math.max).round();
                final rainy = days.where((d) => d.isRainy).length;
                weather[place.name] = ('$max°C${rainy > 0 ? ' · rain on $rainy day${rainy == 1 ? '' : 's'}' : ' · dry'}${days.first.isForecast ? '' : ' (typical)'}', rainy > 0);
              })
              .catchError((_) {}),
      ]);
    }
    onStep?.call(SurpriseStep.weather, weather.isEmpty ? 'Weather unavailable; picking on everything else.' : 'Checked the weekend at ${weather.length} places.');

    // Heavy rain pushes a place down (not out: some like the monsoon).
    shortlist.sort((a, b) => (b.$2 - ((weather[b.$1.name]?.$2 ?? false) ? 1.5 : 0)).compareTo(a.$2 - ((weather[a.$1.name]?.$2 ?? false) ? 1.5 : 0)));

    // Hisab: cost from the traveller's usual daily budget.
    final people = math.max(1, p.last?.travellerCount ?? 2);
    int estimate(SurprisePlace place) {
      final daily = p.dailyPerPersonInr ?? const [0, 2500, 4000, 6500][place.costLevel];
      return ((daily * (nights + 1) * people) / 500).round() * 500;
    }

    onStep?.call(SurpriseStep.budget, 'About ₹${estimate(shortlist.first.$1)} for ${nights + 1} days for $people at the top pick.');

    // Yatri: the final three, with reasons in the traveller's terms.
    var picks = await _viaModel(p, shortlist, weather, nights);
    picks ??= [for (final s in shortlist.take(3)) (s.$1, _why(p, s.$1, s.$3), s.$1.highlights)];
    onStep?.call(SurpriseStep.pick, picks.map((x) => x.$1.name).join(', '));

    return [
      for (final (place, why, highlights) in picks)
        SurprisePick(
          place: place,
          distanceKm: shortlist.firstWhere((s) => s.$1 == place).$3,
          nights: nights,
          why: why,
          highlights: highlights,
          estimateInr: estimate(place),
          weather: weather[place.name]?.$1,
          rainy: weather[place.name]?.$2 ?? false,
          brief: _brief(p, place, start, nights, estimate(place)),
        ),
    ];
  }

  /// The coming weekend: leave Saturday morning; one night, or two for a
  /// relaxed traveller or a far place.
  (DateTime, int) _weekend(TravelProfile p) {
    final now = _now();
    var d = DateTime(now.year, now.month, now.day, 7);
    final toSaturday = (DateTime.saturday - d.weekday) % 7;
    d = d.add(Duration(days: toSaturday == 0 && now.hour >= 7 ? 7 : toSaturday));
    return (d, p.last?.pace == TripPace.relaxed ? 2 : 1);
  }

  double _score(TravelProfile p, SurprisePlace place, int km) {
    var s = 0.0;
    // Reach: a weekend wants 80-350 km by road; flights make far places fine.
    final flies = p.last?.transportModes.contains(TripTransportMode.flight) ?? false;
    if (km <= 350) {
      s += 3 - (km - 180).abs() / 120;
    } else {
      s += flies ? 0.5 : -3 - (km - 350) / 150;
    }
    // Style from past trips (or a gentle default).
    final fav = p.favouriteStyle;
    final wanted = fav == null ? const {'hills', 'heritage', 'nature'} : _styleTags[fav]!;
    s += 2 * place.tags.intersection(wanted).length;
    // Somewhere new.
    if (p.visited.contains(place.name.toLowerCase())) s -= 4;
    // Access needs: easy places first.
    if (p.mobility) s += (place.access - 1) * 2.5;
    // Budget: pricey places for thrifty travellers score lower.
    final daily = p.dailyPerPersonInr;
    if (daily != null && daily < 3000 && place.costLevel == 3) s -= 1.5;
    if (p.last?.sustainability == SustainabilityPriority.greenest && km < 250) s += 0.8;
    return s;
  }

  String _why(TravelProfile p, SurprisePlace place, int km) {
    final bits = <String>[
      '$km km away: an easy weekend',
      if (p.favouriteStyle != null && place.tags.intersection(_styleTags[p.favouriteStyle!]!).isNotEmpty) 'fits the ${p.favouriteStyle!.label.toLowerCase()} trips you choose',
      if (p.mobility && place.access == 2) 'mostly level and easy to get around, for your group’s access needs',
      if (p.visited.isNotEmpty) 'somewhere you have not been yet',
    ];
    return '${bits.join('; ')}.';
  }

  Future<List<(SurprisePlace, String, List<String>)>?> _viaModel(
    TravelProfile p,
    List<(SurprisePlace, double, int)> shortlist,
    Map<String, (String, bool)> weather,
    int nights,
  ) async {
    final m = llm;
    if (m == null || !m.isConfigured || shortlist.length < 3) return null;
    final options = [
      for (final (place, _, km) in shortlist)
        '- ${place.name} (${place.state}): $km km by road; ${place.tags.join(', ')}; '
            'access ${const ['hard', 'mixed', 'easy'][place.access]}; highlights: ${place.highlights.join(', ')}'
            '${weather[place.name] == null ? '' : '; weekend weather: ${weather[place.name]!.$1}'}',
    ];
    try {
      final reply = await m.askJson(
        AgentKind.yatri,
        system:
            'You are Yatri, a travel planner in India. Pick three short weekend trips (${nights + 1} days) for this traveller from the OPTIONS only. '
            'For each, say in one or two warm sentences why it suits THEM, referring to what their past trips show (style, pace, group, access needs, budget, places already visited). '
            'Never pick a place they have already been to unless nothing else fits. Respect access needs strictly. '
            'Reply with JSON only: {"picks":[{"destination":"<exact name from OPTIONS>","why":"...","highlights":["...","...","..."]}]}',
        user: 'TRAVELLER\n${p.summary}\n\nOPTIONS\n${options.join('\n')}',
        tier: LlmTier.heavy,
        temperature: 0.7,
        maxTokens: 900,
        timeout: const Duration(seconds: 25),
      );
      final raw = reply.map?['picks'];
      if (raw is! List) return null;
      final out = <(SurprisePlace, String, List<String>)>[];
      for (final r in raw) {
        if (r is! Map) continue;
        final name = '${r['destination'] ?? ''}'.trim().toLowerCase();
        final hit = shortlist.where((s) => s.$1.name.toLowerCase() == name).firstOrNull;
        if (hit == null || out.any((o) => o.$1 == hit.$1)) continue;
        final why = '${r['why'] ?? ''}'.trim();
        final hl = [for (final h in (r['highlights'] as List? ?? const [])) '$h'.trim()].where((h) => h.isNotEmpty).take(3).toList();
        out.add((hit.$1, why.isEmpty ? _why(p, hit.$1, hit.$3) : why, hl.isEmpty ? hit.$1.highlights : hl));
      }
      return out.length >= 2 ? out.take(3).toList() : null;
    } catch (_) {
      return null;
    }
  }

  TripBrief _brief(TravelProfile p, SurprisePlace place, DateTime start, int nights, int estimate) {
    final last = p.last;
    final end = DateTime(start.year, start.month, start.day + nights, 19);
    final base = TripBrief.empty(_now());
    final people = math.max(1, last?.travellerCount ?? 2);
    return base.copyWith(
      destination: '${place.name}, ${place.state}',
      originCity: p.home,
      start: start,
      end: end,
      travellerCount: people,
      adults: last?.adults ?? people,
      seniors: last?.seniors ?? 0,
      children: last?.children ?? 0,
      women: last?.women,
      childAges: last?.childAges,
      budgetMinInr: (estimate * 0.7).round(),
      budgetMaxInr: estimate,
      transportModes: last?.transportModes.isNotEmpty == true ? last!.transportModes : const {TripTransportMode.carTaxi},
      accessibilityNeeds: last?.accessibilityNeeds ?? const {AccessibilityNeed.none},
      accessibilityConfirmed: last?.accessibilityConfirmed ?? true,
      accessibilityDetails: last?.accessibilityDetails,
      womenSafety: last?.womenSafety,
      style: last?.style ?? p.favouriteStyle,
      pace: last?.pace ?? TripPace.balanced,
      stayTypes: last?.stayTypes,
      dietary: last?.dietary,
      sustainability: last?.sustainability,
    );
  }
}
