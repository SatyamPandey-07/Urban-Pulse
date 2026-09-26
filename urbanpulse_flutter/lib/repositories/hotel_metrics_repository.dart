import 'app_database.dart';

class HotelMetricSample {
  const HotelMetricSample({
    required this.occupancyPercent,
    required this.energyKwh,
    required this.waterLiters,
    required this.foodWasteKg,
  });

  final double occupancyPercent;
  final double energyKwh;
  final double waterLiters;
  final double foodWasteKg;
}

/// Reads the historical occupancy/energy/water/waste log used to train the
/// forecast models. Port of `data/HotelMetricsRepository.kt`.
class HotelMetricsRepository {
  HotelMetricsRepository([AppDatabase? database])
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<List<HotelMetricSample>> getHistory() async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableHistory,
      orderBy: 'day_index ASC',
    );
    return rows
        .map(
          (row) => HotelMetricSample(
            occupancyPercent: (row['occupancy_percent'] as num).toDouble(),
            energyKwh: (row['energy_kwh'] as num).toDouble(),
            waterLiters: (row['water_liters'] as num).toDouble(),
            foodWasteKg: (row['food_waste_kg'] as num).toDouble(),
          ),
        )
        .toList();
  }
}
