import 'app_database.dart';

/// The operator-declared parameters of the facility the Hotel Optimizer models.
///
/// In the Kotlin build these were literals scattered across the screen and the
/// PDF generator (`totalRooms = 120`, a hardcoded facility name, "38.5%
/// Renewable", "declared 85% rate"). They are operator inputs, not measurements,
/// so they now live in a real editable, persisted row — and the audit sheet
/// reports whatever the operator actually declared.
class FacilityProfile {
  const FacilityProfile({
    required this.name,
    required this.totalRooms,
    required this.solarMixPercent,
    required this.greywaterRatePercent,
    required this.energyTargetKwhPerRoom,
    required this.waterTargetLitersPerRoom,
  });

  final String name;
  final int totalRooms;

  /// Operator-declared onsite renewable generation share.
  final double solarMixPercent;

  /// Operator-declared share of water recycled as greywater.
  final double greywaterRatePercent;

  /// BEE 5-Star energy benchmark the audit checks against.
  final double energyTargetKwhPerRoom;

  /// Water target the audit checks against.
  final double waterTargetLitersPerRoom;

  FacilityProfile copyWith({
    String? name,
    int? totalRooms,
    double? solarMixPercent,
    double? greywaterRatePercent,
    double? energyTargetKwhPerRoom,
    double? waterTargetLitersPerRoom,
  }) => FacilityProfile(
    name: name ?? this.name,
    totalRooms: totalRooms ?? this.totalRooms,
    solarMixPercent: solarMixPercent ?? this.solarMixPercent,
    greywaterRatePercent: greywaterRatePercent ?? this.greywaterRatePercent,
    energyTargetKwhPerRoom:
        energyTargetKwhPerRoom ?? this.energyTargetKwhPerRoom,
    waterTargetLitersPerRoom:
        waterTargetLitersPerRoom ?? this.waterTargetLitersPerRoom,
  );
}

class FacilityRepository {
  FacilityRepository([AppDatabase? database])
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  /// Single-row table; this is that row's id.
  static const _profileId = 'default';

  Future<FacilityProfile> getProfile() async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableFacility,
      where: 'id = ?',
      whereArgs: [_profileId],
      limit: 1,
    );
    final row = rows.first;
    return FacilityProfile(
      name: row['name'] as String,
      totalRooms: (row['total_rooms'] as num).toInt(),
      solarMixPercent: (row['solar_mix_percent'] as num).toDouble(),
      greywaterRatePercent: (row['greywater_rate_percent'] as num).toDouble(),
      energyTargetKwhPerRoom: (row['energy_target_kwh_per_room'] as num)
          .toDouble(),
      waterTargetLitersPerRoom: (row['water_target_liters_per_room'] as num)
          .toDouble(),
    );
  }

  Future<void> saveProfile(FacilityProfile profile) async {
    final db = await _database.database;
    await db.update(
      AppDatabase.tableFacility,
      {
        'name': profile.name,
        'total_rooms': profile.totalRooms,
        'solar_mix_percent': profile.solarMixPercent,
        'greywater_rate_percent': profile.greywaterRatePercent,
        'energy_target_kwh_per_room': profile.energyTargetKwhPerRoom,
        'water_target_liters_per_room': profile.waterTargetLitersPerRoom,
      },
      where: 'id = ?',
      whereArgs: [_profileId],
    );
  }
}
