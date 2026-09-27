/// Port of `HospitalityStay.kt`.
class HospitalityStay {
  const HospitalityStay({
    required this.id,
    required this.name,
    required this.category,
    required this.location,
    required this.ecoScore,
    required this.accessibilityRating,
    required this.energySource,
    required this.wastePolicy,
    required this.accessibilityTags,
    required this.carbonFootprintPerNight,
    required this.pricePerNight,
    required this.contactPhone,
    this.bookingUrl,
    this.rating,
    this.reviewCount,
  });

  final String id;
  final String name;

  /// "Eco-Resort", "Green Hotel", "Sustainable Dining", …
  final String category;
  final String location;

  /// 1 to 5 leaves.
  final int ecoScore;

  /// 1 to 100%.
  final int accessibilityRating;

  /// e.g. "100% Solar & Wind".
  final String energySource;

  /// e.g. "Zero Single-Use Plastic • Organic Composting".
  final String wastePolicy;
  final List<String> accessibilityTags;

  /// e.g. "4.2 kg CO2e / night (68% below city avg)".
  final String carbonFootprintPerNight;
  final String pricePerNight;
  final String contactPhone;

  /// Where to see or book it, when the finder had a link.
  final String? bookingUrl;

  /// Guest rating out of 5 and how many reviews it rests on, when known.
  final double? rating;
  final int? reviewCount;
}
