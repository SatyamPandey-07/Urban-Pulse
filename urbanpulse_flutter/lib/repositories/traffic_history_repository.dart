import '../models/live_city_data.dart';
import 'app_database.dart';

/// One recorded TomTom traffic-flow reading.
class TrafficReading {
  const TrafficReading({
    required this.recordedAt,
    required this.congestionPercent,
    required this.currentSpeedKmh,
    required this.freeFlowSpeedKmh,
  });

  final DateTime recordedAt;

  /// How far below free-flow the corridor is running, 0–100.
  final double congestionPercent;
  final int currentSpeedKmh;
  final int freeFlowSpeedKmh;
}

/// Persists the live traffic readings the Dashboard takes, so the congestion
/// chart plots a real recorded history instead of the fixed seven-value array
/// the Kotlin `BarChart` was given.
///
/// The chart starts empty on a fresh install and says so; it fills in as the app
/// is used. Nothing is back-filled or invented.
class TrafficHistoryRepository {
  TrafficHistoryRepository([AppDatabase? database])
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  /// Readings closer together than this are treated as the same sample, so
  /// opening the Dashboard repeatedly doesn't flood the series.
  static const _minimumGap = Duration(minutes: 20);

  /// How many readings the chart shows.
  static const historyLength = 7;

  Future<void> record(LiveTrafficData traffic) async {
    final db = await _database.database;
    final now = DateTime.now();

    final latest = await db.query(
      AppDatabase.tableTrafficHistory,
      orderBy: 'recorded_at DESC',
      limit: 1,
    );
    if (latest.isNotEmpty) {
      final last = DateTime.parse(latest.first['recorded_at'] as String);
      if (now.difference(last) < _minimumGap) return;
    }

    final freeFlow = traffic.freeFlowSpeedKmh;
    final congestion = freeFlow <= 0
        ? 0.0
        : (((freeFlow - traffic.currentSpeedKmh) / freeFlow) * 100).clamp(
            0.0,
            100.0,
          );

    await db.insert(AppDatabase.tableTrafficHistory, {
      'recorded_at': now.toIso8601String(),
      'congestion_percent': congestion,
      'current_speed_kmh': traffic.currentSpeedKmh,
      'free_flow_speed_kmh': freeFlow,
    });

    // Keep the table bounded to what the chart can show.
    await db.rawDelete(
      'DELETE FROM ${AppDatabase.tableTrafficHistory} WHERE recorded_at NOT IN '
      '(SELECT recorded_at FROM ${AppDatabase.tableTrafficHistory} '
      'ORDER BY recorded_at DESC LIMIT ?)',
      [historyLength],
    );
  }

  /// Oldest first, so the chart reads left to right.
  Future<List<TrafficReading>> recentReadings() async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableTrafficHistory,
      orderBy: 'recorded_at DESC',
      limit: historyLength,
    );
    return rows.reversed
        .map(
          (row) => TrafficReading(
            recordedAt: DateTime.parse(row['recorded_at'] as String),
            congestionPercent: (row['congestion_percent'] as num).toDouble(),
            currentSpeedKmh: (row['current_speed_kmh'] as num).toInt(),
            freeFlowSpeedKmh: (row['free_flow_speed_kmh'] as num).toInt(),
          ),
        )
        .toList();
  }
}
