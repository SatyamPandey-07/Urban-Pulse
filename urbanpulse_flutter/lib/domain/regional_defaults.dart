/// Last-resort, deterministic cost figures used when neither a real source nor
/// the language model can supply a number. They are deliberately rough and the
/// UI always labels anything built on them as an estimate.
///
/// Rupees. "Tier" is how expensive the destination is: budget (small towns,
/// hill stations off-season), mid (typical Indian tourist towns) or premium
/// (metros, resort areas, international).
enum CostTier {
  budget,
  mid,
  premium;

  static CostTier parse(Object? v) {
    for (final t in values) {
      if (t.name == '$v'.toLowerCase().trim()) return t;
    }
    return CostTier.mid;
  }
}

abstract final class RegionalDefaults {
  /// A double room per night.
  static int hotelNightlyInr(CostTier tier) => switch (tier) {
    CostTier.budget => 1400,
    CostTier.mid => 3000,
    CostTier.premium => 7000,
  };

  /// Food per person per day.
  static int foodPerPersonDayInr(CostTier tier) => switch (tier) {
    CostTier.budget => 450,
    CostTier.mid => 800,
    CostTier.premium => 1800,
  };

  /// Local transport for the whole group per day (cabs, autos, buses).
  static int localTransportPerDayInr(CostTier tier) => switch (tier) {
    CostTier.budget => 500,
    CostTier.mid => 900,
    CostTier.premium => 1800,
  };

  /// A typical paid entry per person.
  static int entryFeeInr(CostTier tier) => switch (tier) {
    CostTier.budget => 50,
    CostTier.mid => 150,
    CostTier.premium => 500,
  };

  /// Rooms needed for a group: two people per room, and a child sharing with
  /// a parent does not add a room.
  static int roomsFor({required int adults, required int seniors, required int children}) {
    final grownUps = adults + seniors;
    // A group of only children is not a real booking; give it one room.
    if (grownUps <= 0) return 1;
    return (grownUps + 1) ~/ 2;
  }

  /// Road/rail vs air per-kilometre fare per person, in rupees, for a rough
  /// intercity estimate when no real fare is available.
  static double farePerKmInr(String mode) => switch (mode) {
    'train' => 1.1,
    'bus' => 1.6,
    'eBus' => 1.9,
    'carTaxi' => 12,
    'sharedEv' => 9,
    'selfDriveEv' => 6,
    'metroLocal' => 2.5,
    'flight' => 6.5,
    _ => 3,
  };
}
