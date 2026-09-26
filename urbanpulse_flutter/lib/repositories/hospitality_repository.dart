import '../core/formatting.dart';
import '../models/hospitality_stay.dart';
import 'app_database.dart';

/// Reads hospitality listings from the on-device SQLite store instead of a
/// static in-code list. The city-average comparison and "% below city avg" copy
/// are computed from the stored numeric carbon value at read time.
///
/// Port of `data/HospitalityRepository.kt`.
class HospitalityRepository {
  HospitalityRepository([AppDatabase? database])
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  static const _cityAverageCarbonKg = 13.0;

  Future<List<HospitalityStay>> getAllStays() async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableStays,
      orderBy: 'eco_score DESC',
    );

    return rows.map((row) {
      final carbonKg = (row['carbon_kg_per_night'] as num).toDouble();
      final priceRupees = (row['price_rupees'] as num).toInt();
      final belowAvgPct =
          (((_cityAverageCarbonKg - carbonKg) / _cityAverageCarbonKg) * 100)
              .round()
              .coerceAtLeast(0);

      return HospitalityStay(
        id: row['id'] as String,
        name: row['name'] as String,
        category: row['category'] as String,
        location: row['location'] as String,
        ecoScore: (row['eco_score'] as num).toInt(),
        accessibilityRating: (row['accessibility_rating'] as num).toInt(),
        energySource: row['energy_source'] as String,
        wastePolicy: row['waste_policy'] as String,
        accessibilityTags: (row['accessibility_tags'] as String).split('|'),
        carbonFootprintPerNight:
            '${fixed(carbonKg)} kg CO2e / night ($belowAvgPct% below city avg)',
        pricePerNight: '${rupees(priceRupees)} / night',
        contactPhone: row['contact_phone'] as String,
      );
    }).toList();
  }
}
