/// What kind of address this is, as a delivery app groups them.
enum PlaceKind {
  home('Home'),
  work('Work'),
  other('Other');

  const PlaceKind(this.label);
  final String label;
}

/// A place the traveller has chosen: an address with a name of their own.
class SavedPlace {
  const SavedPlace({required this.id, required this.kind, required this.label, required this.address, required this.city, required this.lat, required this.lon});

  final String id;
  final PlaceKind kind;

  /// "Home", "Work", or the name given ("Mom's flat").
  final String label;

  /// The full address line as found.
  final String address;

  /// The city, which is what a trip starts from.
  final String city;
  final double lat;
  final double lon;

  SavedPlace copyWith({PlaceKind? kind, String? label, String? address, String? city, double? lat, double? lon}) => SavedPlace(
    id: id,
    kind: kind ?? this.kind,
    label: label ?? this.label,
    address: address ?? this.address,
    city: city ?? this.city,
    lat: lat ?? this.lat,
    lon: lon ?? this.lon,
  );

  Map<String, dynamic> toJson() => {'id': id, 'kind': kind.name, 'label': label, 'address': address, 'city': city, 'lat': lat, 'lon': lon};

  /// Reads one back, or null if it is not a usable place.
  static SavedPlace? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final label = j['label'];
    final lat = j['lat'];
    final lon = j['lon'];
    if (id is! String || label is! String || lat is! num || lon is! num) return null;
    if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) return null;
    final kindName = j['kind'];
    return SavedPlace(
      id: id,
      kind: PlaceKind.values.firstWhere((k) => k.name == kindName, orElse: () => PlaceKind.other),
      label: label,
      address: j['address'] is String ? j['address'] as String : '',
      city: j['city'] is String ? j['city'] as String : '',
      lat: lat.toDouble(),
      lon: lon.toDouble(),
    );
  }
}

/// A suggestion while typing an address.
class PlaceSuggestion {
  const PlaceSuggestion({required this.title, required this.subtitle, required this.lat, required this.lon});

  final String title;
  final String subtitle;
  final double lat;
  final double lon;

  /// One line for the chat bubble.
  String get line => subtitle.isEmpty ? title : '$title, $subtitle';
}
