// The structured result of Yatri AI's intake conversation — the hand-off
// contract between the receptionist agent and every later planning agent.

/// Transport modes a traveler can accept for the trip. `gCo2PerPaxKm` is an
/// indicative per-passenger emission used only for the badge and the nudge.
enum TripTransportMode {
  train('Train', '🚆', 14, true),
  metroLocal('Metro / local rail', '🚇', 30, true),
  eBus('Electric bus', '🚌', 35, true),
  bus('Bus', '🚍', 68, false),
  sharedEv('Shared EV cab', '🚕', 50, true),
  selfDriveEv('Self-drive EV', '🔋', 55, true),
  carTaxi('Car / taxi', '🚗', 170, false),
  flight('Flight', '✈️', 250, false);

  const TripTransportMode(this.label, this.emoji, this.gCo2PerPaxKm, this.isEco);

  final String label;
  final String emoji;
  final int gCo2PerPaxKm;
  final bool isEco;
}

enum AccessibilityNeed {
  wheelchair('Wheelchair user', '♿'),
  limitedMobility('Limited mobility / walking', '🚶'),
  visual('Visual impairment', '👁️'),
  hearing('Hearing impairment', '🦻'),
  elderlyCare('Elderly care', '🧓'),
  serviceAnimal('Travelling with a service animal', '🐕‍🦺'),
  cognitiveSensory('Sensory or cognitive needs', '🧠'),
  otherSpecial('Other special needs', '🤝'),
  none('No accessibility needs', '✅');

  const AccessibilityNeed(this.label, this.emoji);

  final String label;
  final String emoji;
}

enum WomenSafetyPref {
  womenOnlyTransport('Women-only cabs / coaches', '🚺'),
  verifiedStays('Verified, well-rated stays', '🏨'),
  avoidLateNightTransit('Avoid late-night transit', '🌙'),
  sharedLiveLocation('Live location sharing', '📍'),
  none('No specific preferences', '✅');

  const WomenSafetyPref(this.label, this.emoji);

  final String label;
  final String emoji;
}

enum TripStyle {
  leisure('Leisure & relaxing', '🏖️'),
  family('Family time', '👨‍👩‍👧'),
  pilgrimage('Pilgrimage', '🛕'),
  adventure('Adventure', '🧗'),
  heritage('Heritage & culture', '🏛️'),
  nature('Nature & wildlife', '🌿'),
  workation('Workation', '💻');

  const TripStyle(this.label, this.emoji);

  final String label;
  final String emoji;
}

enum TripPace {
  relaxed('Relaxed', '🐢'),
  balanced('Balanced', '⚖️'),
  packed('Packed', '⚡');

  const TripPace(this.label, this.emoji);

  final String label;
  final String emoji;
}

enum StayType {
  ecoStay('Eco stay', '🌱'),
  homestay('Homestay', '🏡'),
  hotel('Hotel', '🏨'),
  hostel('Hostel', '🛏️'),
  resort('Resort', '🌴');

  const StayType(this.label, this.emoji);

  final String label;
  final String emoji;
}

enum Dietary {
  veg('Vegetarian', '🥗'),
  vegan('Vegan', '🌱'),
  jain('Jain', '🙏'),
  halal('Halal', '🍢'),
  noPreference('No preference', '🍽️');

  const Dietary(this.label, this.emoji);

  final String label;
  final String emoji;
}

enum SustainabilityPriority {
  greenest('Greenest option', '🌍'),
  balanced('Balanced', '⚖️'),
  convenience('Convenience first', '🧳');

  const SustainabilityPriority(this.label, this.emoji);

  final String label;
  final String emoji;
}

/// Every piece of the brief that maps to one question the agent can ask.
enum BriefField {
  destination,
  origin,
  dates,
  travellers,
  group,
  womenSafety,
  accessibility,
  accessibilityDetails,
  transport,
  budget,
  style,
  pace,
  stay,
  dietary,
  sustainability,
  notes,
}

/// What the traveler wants from the trip. Immutable; every mutation goes
/// through [copyWith] / [clearing] so the domain layer stays easy to test.
class TripBrief {
  const TripBrief({
    required this.id,
    required this.createdAt,
    this.destination,
    this.originCity,
    this.start,
    this.end,
    this.travellerCount,
    this.adults,
    this.seniors,
    this.children,
    this.women,
    this.childAges = const [],
    this.budgetMinInr,
    this.budgetMaxInr,
    this.transportModes = const {},
    this.accessibilityNeeds = const {},
    this.accessibilityConfirmed = false,
    this.accessibilityDetails = const {},
    this.womenSafety = const {},
    this.style,
    this.pace,
    this.stayTypes = const {},
    this.dietary = const {},
    this.sustainability = SustainabilityPriority.balanced,
    this.notes,
    this.uncertain = const {},
  });

  factory TripBrief.empty(DateTime now) =>
      TripBrief(id: 'brief_${now.millisecondsSinceEpoch}', createdAt: now);

  final String id;
  final DateTime createdAt;

  final String? destination;
  final String? originCity;
  final DateTime? start;
  final DateTime? end;

  final int? travellerCount;
  final int? adults;
  final int? seniors;
  final int? children;
  final int? women;
  final List<int> childAges;

  /// Whole-trip budget for every traveler together, in rupees.
  final int? budgetMinInr;
  final int? budgetMaxInr;

  final Set<TripTransportMode> transportModes;

  final Set<AccessibilityNeed> accessibilityNeeds;

  /// Accessibility is always asked: values that were only pre-ticked from
  /// Settings or guessed from free text never count until the traveler
  /// confirms them.
  final bool accessibilityConfirmed;

  /// Follow-up question id -> chosen option ids (e.g. `a11y.wheelchair.type`).
  final Map<String, Set<String>> accessibilityDetails;

  final Set<WomenSafetyPref> womenSafety;

  final TripStyle? style;
  final TripPace? pace;
  final Set<StayType> stayTypes;
  final Set<Dietary> dietary;
  final SustainabilityPriority sustainability;
  final String? notes;

  /// Fields the model extracted with low confidence (or with an assumed time)
  /// that the traveler still has to confirm.
  final Set<BriefField> uncertain;

  /// The adult / senior / child split is known (possibly worked out from the
  /// traveller's own words), whether or not the women count is.
  bool get hasPartsBreakdown =>
      adults != null && seniors != null && children != null;

  bool get hasGroupBreakdown => hasPartsBreakdown && women != null;

  /// Calendar days the trip touches, inclusive of both ends.
  int get days {
    final s = start;
    final e = end;
    if (s == null || e == null) return 0;
    final a = DateTime(s.year, s.month, s.day);
    final b = DateTime(e.year, e.month, e.day);
    return (b.difference(a).inDays + 1).clamp(1, 1000);
  }

  int get nights => days <= 1 ? 0 : days - 1;

  TripBrief copyWith({
    String? destination,
    String? originCity,
    DateTime? start,
    DateTime? end,
    int? travellerCount,
    int? adults,
    int? seniors,
    int? children,
    int? women,
    List<int>? childAges,
    int? budgetMinInr,
    int? budgetMaxInr,
    Set<TripTransportMode>? transportModes,
    Set<AccessibilityNeed>? accessibilityNeeds,
    bool? accessibilityConfirmed,
    Map<String, Set<String>>? accessibilityDetails,
    Set<WomenSafetyPref>? womenSafety,
    TripStyle? style,
    TripPace? pace,
    Set<StayType>? stayTypes,
    Set<Dietary>? dietary,
    SustainabilityPriority? sustainability,
    String? notes,
    Set<BriefField>? uncertain,
  }) => TripBrief(
    id: id,
    createdAt: createdAt,
    destination: destination ?? this.destination,
    originCity: originCity ?? this.originCity,
    start: start ?? this.start,
    end: end ?? this.end,
    travellerCount: travellerCount ?? this.travellerCount,
    adults: adults ?? this.adults,
    seniors: seniors ?? this.seniors,
    children: children ?? this.children,
    women: women ?? this.women,
    childAges: childAges ?? this.childAges,
    budgetMinInr: budgetMinInr ?? this.budgetMinInr,
    budgetMaxInr: budgetMaxInr ?? this.budgetMaxInr,
    transportModes: transportModes ?? this.transportModes,
    accessibilityNeeds: accessibilityNeeds ?? this.accessibilityNeeds,
    accessibilityConfirmed:
        accessibilityConfirmed ?? this.accessibilityConfirmed,
    accessibilityDetails: accessibilityDetails ?? this.accessibilityDetails,
    womenSafety: womenSafety ?? this.womenSafety,
    style: style ?? this.style,
    pace: pace ?? this.pace,
    stayTypes: stayTypes ?? this.stayTypes,
    dietary: dietary ?? this.dietary,
    sustainability: sustainability ?? this.sustainability,
    notes: notes ?? this.notes,
    uncertain: uncertain ?? this.uncertain,
  );

  /// Resets one field back to "not answered" (a null-valued [copyWith] cannot).
  TripBrief clearing(BriefField field) {
    switch (field) {
      case BriefField.destination:
        return _rebuild(destination: null, keepDestination: false);
      case BriefField.origin:
        return _rebuild(originCity: null, keepOrigin: false);
      case BriefField.dates:
        return _rebuild(start: null, end: null, keepDates: false);
      case BriefField.travellers:
        return _rebuild(travellerCount: null, keepTravellers: false);
      case BriefField.group:
        return _rebuild(clearGroup: true);
      case BriefField.budget:
        return _rebuild(budgetMin: null, budgetMax: null, keepBudget: false);
      case BriefField.style:
        return _rebuild(style: null, keepStyle: false);
      case BriefField.pace:
        return _rebuild(pace: null, keepPace: false);
      case BriefField.notes:
        return _rebuild(notes: null, keepNotes: false);
      case BriefField.transport:
        return copyWith(transportModes: const {});
      case BriefField.womenSafety:
        return copyWith(womenSafety: const {});
      case BriefField.accessibility:
      case BriefField.accessibilityDetails:
        return copyWith(
          accessibilityConfirmed: false,
          accessibilityDetails: const {},
        );
      case BriefField.stay:
        return copyWith(stayTypes: const {});
      case BriefField.dietary:
        return copyWith(dietary: const {});
      case BriefField.sustainability:
        return copyWith(sustainability: SustainabilityPriority.balanced);
    }
  }

  TripBrief _rebuild({
    String? destination,
    String? originCity,
    DateTime? start,
    DateTime? end,
    int? travellerCount,
    int? budgetMin,
    int? budgetMax,
    TripStyle? style,
    TripPace? pace,
    String? notes,
    bool keepDestination = true,
    bool keepOrigin = true,
    bool keepDates = true,
    bool keepTravellers = true,
    bool keepBudget = true,
    bool keepStyle = true,
    bool keepPace = true,
    bool keepNotes = true,
    bool clearGroup = false,
  }) => TripBrief(
    id: id,
    createdAt: createdAt,
    destination: keepDestination ? this.destination : destination,
    originCity: keepOrigin ? this.originCity : originCity,
    start: keepDates ? this.start : start,
    end: keepDates ? this.end : end,
    travellerCount: keepTravellers ? this.travellerCount : travellerCount,
    adults: clearGroup ? null : adults,
    seniors: clearGroup ? null : seniors,
    children: clearGroup ? null : children,
    women: clearGroup ? null : women,
    childAges: clearGroup ? const [] : childAges,
    budgetMinInr: keepBudget ? budgetMinInr : budgetMin,
    budgetMaxInr: keepBudget ? budgetMaxInr : budgetMax,
    transportModes: transportModes,
    accessibilityNeeds: accessibilityNeeds,
    accessibilityConfirmed: accessibilityConfirmed,
    accessibilityDetails: accessibilityDetails,
    womenSafety: womenSafety,
    style: keepStyle ? this.style : style,
    pace: keepPace ? this.pace : pace,
    stayTypes: stayTypes,
    dietary: dietary,
    sustainability: sustainability,
    notes: keepNotes ? this.notes : notes,
    uncertain: uncertain,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'destination': destination,
    'originCity': originCity,
    'start': start?.toIso8601String(),
    'end': end?.toIso8601String(),
    'travellerCount': travellerCount,
    'adults': adults,
    'seniors': seniors,
    'children': children,
    'women': women,
    'childAges': childAges,
    'budgetMinInr': budgetMinInr,
    'budgetMaxInr': budgetMaxInr,
    'transportModes': [for (final m in transportModes) m.name],
    'accessibilityNeeds': [for (final n in accessibilityNeeds) n.name],
    'accessibilityConfirmed': accessibilityConfirmed,
    'accessibilityDetails': {
      for (final e in accessibilityDetails.entries) e.key: e.value.toList(),
    },
    'womenSafety': [for (final s in womenSafety) s.name],
    'style': style?.name,
    'pace': pace?.name,
    'stayTypes': [for (final s in stayTypes) s.name],
    'dietary': [for (final d in dietary) d.name],
    'sustainability': sustainability.name,
    'notes': notes,
    'uncertain': [for (final f in uncertain) f.name],
  };

  static TripBrief fromJson(Map<String, dynamic> json) {
    T? byName<T extends Enum>(List<T> values, Object? name) {
      for (final v in values) {
        if (v.name == name) return v;
      }
      return null;
    }

    Set<T> enumSet<T extends Enum>(List<T> values, Object? raw) => {
      for (final n in (raw as List<dynamic>? ?? const []))
        if (byName(values, n) case final v?) v,
    };

    DateTime? date(Object? raw) => raw is String ? DateTime.tryParse(raw) : null;

    return TripBrief(
      id: json['id'] as String? ?? 'brief',
      createdAt: date(json['createdAt']) ?? DateTime.now(),
      destination: json['destination'] as String?,
      originCity: json['originCity'] as String?,
      start: date(json['start']),
      end: date(json['end']),
      travellerCount: json['travellerCount'] as int?,
      adults: json['adults'] as int?,
      seniors: json['seniors'] as int?,
      children: json['children'] as int?,
      women: json['women'] as int?,
      childAges: [
        for (final a in (json['childAges'] as List<dynamic>? ?? const []))
          (a as num).toInt(),
      ],
      budgetMinInr: json['budgetMinInr'] as int?,
      budgetMaxInr: json['budgetMaxInr'] as int?,
      transportModes: enumSet(TripTransportMode.values, json['transportModes']),
      accessibilityNeeds: enumSet(
        AccessibilityNeed.values,
        json['accessibilityNeeds'],
      ),
      accessibilityConfirmed: json['accessibilityConfirmed'] as bool? ?? false,
      accessibilityDetails: {
        for (final e
            in (json['accessibilityDetails'] as Map<String, dynamic>? ??
                    const {})
                .entries)
          e.key: {for (final v in e.value as List<dynamic>) v as String},
      },
      womenSafety: enumSet(WomenSafetyPref.values, json['womenSafety']),
      style: byName(TripStyle.values, json['style']),
      pace: byName(TripPace.values, json['pace']),
      stayTypes: enumSet(StayType.values, json['stayTypes']),
      dietary: enumSet(Dietary.values, json['dietary']),
      sustainability:
          byName(SustainabilityPriority.values, json['sustainability']) ??
          SustainabilityPriority.balanced,
      notes: json['notes'] as String?,
      uncertain: enumSet(BriefField.values, json['uncertain']),
    );
  }

  /// Compact human-readable summary used in LLM prompts and the planner
  /// hand-off.
  String toPromptSummary() {
    final parts = <String>[
      if (destination != null) 'destination $destination',
      if (originCity != null) 'from $originCity',
      if (start != null && end != null)
        '${_ymd(start!)} to ${_ymd(end!)} ($days days)',
      if (travellerCount != null) '$travellerCount travellers',
      if (hasPartsBreakdown)
        'adults $adults, seniors $seniors, children $children'
            '${childAges.isEmpty ? '' : ' (ages ${childAges.join('/')})'}'
            '${women == null ? '' : ', women $women'}',
      if (budgetMaxInr != null)
        'budget INR ${budgetMinInr ?? 0}-$budgetMaxInr total',
      if (transportModes.isNotEmpty)
        'transport: ${transportModes.map((m) => m.label).join(', ')}',
      if (accessibilityNeeds.isNotEmpty)
        'accessibility: ${accessibilityNeeds.map((n) => n.label).join(', ')}',
      for (final e in accessibilityDetails.entries)
        if (e.value.isNotEmpty) '${e.key}=${e.value.join('+')}',
      if (womenSafety.isNotEmpty)
        'safety: ${womenSafety.map((s) => s.label).join(', ')}',
      if (style != null) 'style ${style!.label}',
      if (pace != null) 'pace ${pace!.label}',
      if (stayTypes.isNotEmpty)
        'stay: ${stayTypes.map((s) => s.label).join(', ')}',
      if (dietary.isNotEmpty) 'diet: ${dietary.map((d) => d.label).join(', ')}',
      'sustainability ${sustainability.label}',
      if (notes != null && notes!.trim().isNotEmpty) 'notes: $notes',
    ];
    return parts.join('; ');
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
