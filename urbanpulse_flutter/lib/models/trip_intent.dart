/// Structured trip constraints extracted from a traveler's plain-language
/// request. Port of `intent/TripIntent.kt`.
class TripIntent {
  const TripIntent({
    this.prioritizeCarbon = false,
    this.prioritizeAccessibility = false,
    this.prioritizeSpeed = false,
    this.prioritizeBudget = false,
    this.requireWheelchairAccess = false,
    this.requireSolarEnergy = false,
    this.requireZeroWaste = false,
    this.maxPriceRupees,
    this.searchKeywords = '',
    this.parsedBy = 'rules',
  });

  final bool prioritizeCarbon;
  final bool prioritizeAccessibility;
  final bool prioritizeSpeed;
  final bool prioritizeBudget;
  final bool requireWheelchairAccess;
  final bool requireSolarEnergy;
  final bool requireZeroWaste;
  final int? maxPriceRupees;
  final String searchKeywords;

  /// `groq`, `gemini` or `rules` — surfaced in the UI so the user can see which
  /// engine actually parsed their request.
  final String parsedBy;

  String get engineLabel => switch (parsedBy) {
    'groq' => 'Groq LPU',
    'gemini' => 'Gemini',
    _ => 'keyword rules',
  };
}
