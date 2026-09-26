/// Port of `ExperienceListing.kt`.
class ExperienceListing {
  ExperienceListing({
    required this.id,
    required this.name,
    required this.category,
    required this.location,
    required this.sustainabilityPractice,
    required this.ecoScore,
    required this.accessibilityRating,
    required this.accessibilityTags,
    required this.carbonFootprintPerVisit,
    required this.pricePerPerson,
    required this.durationHours,
    this.isAvailableToday = true,
    this.travelerTags = const ['Child-Friendly', 'Family', 'Indoor'],
    this.viewsCount = 0,
    this.inquiryCount = 0,
    this.bookingCount = 0,
    this.accessibilityConfirmCount = 0,
    this.accessibilityDisputeCount = 0,
  });

  final String id;
  final String name;

  /// "Heritage & Art", "Nature & Wildlife", "Culinary & Farming", …
  final String category;
  final String location;
  final String sustainabilityPractice;

  /// 1 to 5 leaves.
  final int ecoScore;

  /// 0 to 100%.
  final int accessibilityRating;
  final List<String> accessibilityTags;

  /// e.g. "0.8 kg CO2e / visit (43% below category avg)".
  final String carbonFootprintPerVisit;

  /// e.g. "₹610 / person".
  final String pricePerPerson;
  final double durationHours;
  final bool isAvailableToday;
  final List<String> travelerTags;
  final int viewsCount;
  final int inquiryCount;
  final int bookingCount;
  final int accessibilityConfirmCount;
  final int accessibilityDisputeCount;
}
