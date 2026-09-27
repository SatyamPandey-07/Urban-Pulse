import 'itinerary_parts.dart';

/// Trip-pooling on an itinerary: the shared vehicle for the journey and who
/// rides in it. Kept on the itinerary so the split can be recomputed as mates
/// join or leave, and so both travellers' plans agree.
class TripPoolMate {
  const TripPoolMate({required this.requestId, required this.name, required this.travellers, this.origin, this.hosting = false});

  /// The `trip_pool_requests` row this pairing came from.
  final String requestId;
  final String name;
  final int travellers;
  final String? origin;

  /// True when this traveller opened the trip and the mate joined it.
  final bool hosting;

  Map<String, dynamic> toJson() => {'requestId': requestId, 'name': name, 'travellers': travellers, 'origin': origin, 'hosting': hosting};

  static TripPoolMate fromJson(Map<String, dynamic> j) => TripPoolMate(
    requestId: '${j['requestId']}',
    name: '${j['name'] ?? 'Traveller'}',
    travellers: (j['travellers'] as num?)?.toInt() ?? 1,
    origin: j['origin'] as String?,
    hosting: j['hosting'] == true,
  );
}

class TripPool {
  const TripPool({
    required this.vehicleCostInr,
    required this.vehicleCo2Grams,
    required this.soloCostInr,
    required this.soloCo2Grams,
    required this.myTravellers,
    required this.soloLeg,
    this.mates = const [],
  });

  /// The journey as planned before pooling, restored when the pool empties.
  final TransportLeg soloLeg;

  /// The whole shared vehicle for the journey (all seats).
  final int vehicleCostInr;
  final int vehicleCo2Grams;

  /// This traveller's journey before pooling, to show the saving.
  final int soloCostInr;
  final int soloCo2Grams;
  final int myTravellers;
  final List<TripPoolMate> mates;

  int get seatsUsed => myTravellers + mates.fold(0, (s, m) => s + m.travellers);

  /// Cars carry four; a bigger group needs another vehicle.
  int get vehicles => (seatsUsed / 4).ceil().clamp(1, 10);

  /// This traveller's share of the shared journey.
  int get myCostInr => (vehicleCostInr * vehicles * myTravellers / seatsUsed).round();
  int get myCo2Grams => (vehicleCo2Grams * vehicles * myTravellers / seatsUsed).round();

  int get savedInr => (soloCostInr - myCostInr).clamp(0, 1 << 30);
  double get savedCo2Kg => ((soloCo2Grams - myCo2Grams).clamp(0, 1 << 30)) / 1000;

  TripPool withMate(TripPoolMate m) => TripPool(
    vehicleCostInr: vehicleCostInr,
    vehicleCo2Grams: vehicleCo2Grams,
    soloCostInr: soloCostInr,
    soloCo2Grams: soloCo2Grams,
    myTravellers: myTravellers,
    soloLeg: soloLeg,
    mates: [for (final x in mates) if (x.requestId != m.requestId) x, m],
  );

  TripPool withoutMate(String requestId) => TripPool(
    vehicleCostInr: vehicleCostInr,
    vehicleCo2Grams: vehicleCo2Grams,
    soloCostInr: soloCostInr,
    soloCo2Grams: soloCo2Grams,
    myTravellers: myTravellers,
    soloLeg: soloLeg,
    mates: [for (final x in mates) if (x.requestId != requestId) x],
  );

  String get matesLabel => mates.map((m) => '${m.name}${m.travellers > 1 ? ' (+${m.travellers - 1})' : ''}').join(', ');

  Map<String, dynamic> toJson() => {
    'vehicleCostInr': vehicleCostInr,
    'vehicleCo2Grams': vehicleCo2Grams,
    'soloCostInr': soloCostInr,
    'soloCo2Grams': soloCo2Grams,
    'myTravellers': myTravellers,
    'soloLeg': soloLeg.toJson(),
    'mates': [for (final m in mates) m.toJson()],
  };

  static TripPool fromJson(Map<String, dynamic> j) => TripPool(
    vehicleCostInr: (j['vehicleCostInr'] as num?)?.toInt() ?? 0,
    vehicleCo2Grams: (j['vehicleCo2Grams'] as num?)?.toInt() ?? 0,
    soloCostInr: (j['soloCostInr'] as num?)?.toInt() ?? 0,
    soloCo2Grams: (j['soloCo2Grams'] as num?)?.toInt() ?? 0,
    myTravellers: (j['myTravellers'] as num?)?.toInt() ?? 1,
    soloLeg: TransportLeg.fromJson(j['soloLeg'] is Map<String, dynamic> ? j['soloLeg'] as Map<String, dynamic> : const {}),
    mates: [
      for (final m in (j['mates'] as List<dynamic>? ?? const []))
        if (m is Map<String, dynamic>) TripPoolMate.fromJson(m),
    ],
  );
}
