import 'package:sqflite/sqflite.dart';

import '../core/formatting.dart';
import '../models/experience_listing.dart';
import '../services/central_registry_client.dart';
import 'app_database.dart';

/// Reads/writes experience listings from the real Central Registry backend
/// (`server/`) when it's reachable — the same shared SQLite store the web app
/// uses — so a listing published from either client is visible on both. Falls
/// back to the on-device SQLite store (real persisted state, not an in-memory
/// placeholder) when the backend is unreachable, and mirrors backend reads into
/// that local store so the app still has real, non-fabricated data offline.
///
/// Port of `data/ExperienceRepository.kt`.
class ExperienceRepository {
  ExperienceRepository([AppDatabase? database])
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  static const _categoryAverageCarbonKg = 1.4;

  Future<List<ExperienceListing>> getAllExperiences() async {
    final fromBackend = await CentralRegistryClient.fetchExperiences();
    if (fromBackend != null) {
      await _mirrorToLocalCache(fromBackend);
      return fromBackend.map(_toListing).toList();
    }
    return _readFromLocalDb();
  }

  /// Indoor categories are rain-safe and child-friendly; everything else is an
  /// outdoor/nature activity. Shared by both the backend and local-cache paths.
  static List<String> _travelerTagsFor(String category) {
    final isIndoor = [
      'culinary',
      'craft',
      'workshop',
      'art',
      'heritage',
    ].any((needle) => category.toLowerCase().contains(needle));
    return isIndoor
        ? const ['Child-Friendly', 'Family', 'Indoor', 'Rain-Safe']
        : const ['Family', 'Outdoor', 'Nature'];
  }

  static String _carbonCopy(double carbonKg) {
    final belowAvgPct =
        (((_categoryAverageCarbonKg - carbonKg) / _categoryAverageCarbonKg) *
                100)
            .round()
            .coerceAtLeast(0);
    return '${fixed(carbonKg)} kg CO2e / visit ($belowAvgPct% below category avg)';
  }

  ExperienceListing _toListing(RegistryExperience row) => ExperienceListing(
    id: row.id,
    name: row.name,
    category: row.category,
    location: row.location,
    sustainabilityPractice: row.sustainability,
    ecoScore: row.ecoScore,
    accessibilityRating: row.accessibilityRating,
    accessibilityTags: row.accessibilityTags,
    carbonFootprintPerVisit: _carbonCopy(row.carbonKg),
    pricePerPerson: '${rupees(row.price)} / person',
    durationHours: row.duration,
    isAvailableToday: row.isAvailableToday,
    travelerTags: _travelerTagsFor(row.category),
    viewsCount: row.viewsCount,
    inquiryCount: row.inquiryCount,
    bookingCount: row.bookingCount,
    accessibilityConfirmCount: row.accessibilityConfirmCount,
    accessibilityDisputeCount: row.accessibilityDisputeCount,
  );

  /// Upserts backend rows into the local SQLite cache so the app has real (not
  /// fabricated) data when offline.
  Future<void> _mirrorToLocalCache(List<RegistryExperience> rows) async {
    final db = await _database.database;
    final batch = db.batch();
    for (final row in rows) {
      batch.insert(AppDatabase.tableExperiences, {
        'id': row.id,
        'name': row.name,
        'category': row.category,
        'location': row.location,
        'sustainability_practice': row.sustainability,
        'eco_score': row.ecoScore,
        'accessibility_rating': row.accessibilityRating,
        'accessibility_tags': row.accessibilityTags.join('|'),
        'carbon_kg_per_visit': row.carbonKg,
        'price_rupees': row.price,
        'duration_hours': row.duration,
        'is_available_today': row.isAvailableToday ? 1 : 0,
        'views_count': row.viewsCount,
        'inquiry_count': row.inquiryCount,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<ExperienceListing>> _readFromLocalDb() async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableExperiences,
      orderBy: 'eco_score DESC',
    );

    final experiences = <ExperienceListing>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final category = row['category'] as String;
      final carbonKg = (row['carbon_kg_per_visit'] as num).toDouble();

      experiences.add(
        ExperienceListing(
          id: id,
          name: row['name'] as String,
          category: category,
          location: row['location'] as String,
          sustainabilityPractice: row['sustainability_practice'] as String,
          ecoScore: (row['eco_score'] as num).toInt(),
          accessibilityRating: (row['accessibility_rating'] as num).toInt(),
          accessibilityTags: (row['accessibility_tags'] as String).split('|'),
          carbonFootprintPerVisit: _carbonCopy(carbonKg),
          pricePerPerson:
              '${rupees((row['price_rupees'] as num).toInt())} / person',
          durationHours: (row['duration_hours'] as num).toDouble(),
          isAvailableToday: (row['is_available_today'] as num).toInt() != 0,
          travelerTags: _travelerTagsFor(category),
          viewsCount: (row['views_count'] as num).toInt(),
          inquiryCount: (row['inquiry_count'] as num).toInt(),
          bookingCount: await _countRows(AppDatabase.tableBookings, id),
          accessibilityConfirmCount: await _countReports(id, confirms: true),
          accessibilityDisputeCount: await _countReports(id, confirms: false),
        ),
      );
    }
    return experiences;
  }

  Future<int> _countRows(String table, String experienceId) async {
    final db = await _database.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $table WHERE experience_id = ?',
      [experienceId],
    );
    return (result.first['n'] as num?)?.toInt() ?? 0;
  }

  Future<int> _countReports(
    String experienceId, {
    required bool confirms,
  }) async {
    final db = await _database.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM ${AppDatabase.tableReports} '
      'WHERE experience_id = ? AND confirms_accessibility = ?',
      [experienceId, confirms ? 1 : 0],
    );
    return (result.first['n'] as num?)?.toInt() ?? 0;
  }

  /// Creates a real booking on the shared backend when reachable, and always
  /// writes through to the local cache.
  Future<bool> createBooking(
    String experienceId, {
    required String travelerName,
    required int partySize,
    required String bookingDate,
  }) async {
    final onBackend = await CentralRegistryClient.createBooking(
      experienceId,
      travelerName: travelerName,
      partySize: partySize,
      bookingDate: bookingDate,
    );
    try {
      final db = await _database.database;
      final rowId = await db.insert(AppDatabase.tableBookings, {
        'id':
            onBackend?.id ?? 'booking_${DateTime.now().millisecondsSinceEpoch}',
        'experience_id': experienceId,
        'traveler_name': travelerName,
        'party_size': partySize,
        'booking_date': bookingDate,
        'status': 'confirmed',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      return rowId != 0;
    } catch (_) {
      return onBackend != null;
    }
  }

  /// Submits a real traveler accessibility report — a genuine second,
  /// independent signal for the Evidence Graph (confirming or disputing the
  /// provider's own claim), not the same source echoed back.
  Future<bool> submitAccessibilityReport(
    String experienceId, {
    required bool confirmsAccessibility,
    required String note,
  }) async {
    final onBackend = await CentralRegistryClient.submitReport(
      experienceId,
      confirmsAccessibility: confirmsAccessibility,
      note: note,
    );
    try {
      final db = await _database.database;
      final rowId = await db.insert(AppDatabase.tableReports, {
        'id':
            onBackend?.id ?? 'report_${DateTime.now().millisecondsSinceEpoch}',
        'experience_id': experienceId,
        'confirms_accessibility': confirmsAccessibility ? 1 : 0,
        'note': note,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      return rowId != 0;
    } catch (_) {
      return onBackend != null;
    }
  }

  /// Toggles availability on the shared backend when reachable, and always
  /// writes through to the local cache.
  Future<void> toggleAvailability(String id, {required bool available}) async {
    await CentralRegistryClient.toggleAvailability(id);
    final db = await _database.database;
    await db.update(
      AppDatabase.tableExperiences,
      {'is_available_today': available ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Records a real view/inquiry event on the shared backend when reachable, and
  /// always writes through locally.
  Future<void> recordView(String id) => _recordEvent(
    id,
    'views_count',
    () => CentralRegistryClient.recordView(id),
  );

  Future<void> recordInquiry(String id) => _recordEvent(
    id,
    'inquiry_count',
    () => CentralRegistryClient.recordInquiry(id),
  );

  Future<void> _recordEvent(
    String id,
    String localColumn,
    Future<RegistryExperience?> Function() backendCall,
  ) async {
    final updated = await backendCall();
    final db = await _database.database;
    if (updated != null) {
      await db.update(
        AppDatabase.tableExperiences,
        {
          'views_count': updated.viewsCount,
          'inquiry_count': updated.inquiryCount,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await db.rawUpdate(
        'UPDATE ${AppDatabase.tableExperiences} '
        'SET $localColumn = $localColumn + 1 WHERE id = ?',
        [id],
      );
    }
  }

  Future<List<ExperienceListing>> getAdaptiveExperiences({
    bool isRain = false,
    double maxDuration = 3.0,
    bool familyOnly = false,
  }) async {
    final all = (await getAllExperiences()).where((e) => e.isAvailableToday);
    return all.where((exp) {
      final matchRain =
          !isRain ||
          exp.travelerTags.contains('Indoor') ||
          exp.travelerTags.contains('Rain-Safe');
      final matchDuration = exp.durationHours <= maxDuration;
      final matchFamily =
          !familyOnly || exp.travelerTags.contains('Child-Friendly');
      return matchRain && matchDuration && matchFamily;
    }).toList();
  }

  Future<bool> addExperience({
    required String name,
    required String category,
    required String location,
    required String sustainabilityPractice,
    required List<String> accessibilityTags,
    int accessibilityRating = 90,
    int ecoScore = 4,
    double carbonKg = 0.5,
    int priceRupees = 350,
    double durationHours = 2.0,
  }) async {
    final onBackend = await CentralRegistryClient.createExperience(
      name: name,
      category: category,
      location: location,
      duration: durationHours,
      price: priceRupees,
      ecoScore: ecoScore,
      accessibilityRating: accessibilityRating,
      accessibilityTags: accessibilityTags,
      sustainability: sustainabilityPractice,
      carbonKg: carbonKg,
    );
    try {
      final db = await _database.database;
      final rowId = await db.insert(AppDatabase.tableExperiences, {
        'id': onBackend?.id ?? 'exp_${DateTime.now().millisecondsSinceEpoch}',
        'name': name,
        'category': category,
        'location': location,
        'sustainability_practice': sustainabilityPractice,
        'eco_score': ecoScore,
        'accessibility_rating': accessibilityRating,
        'accessibility_tags': accessibilityTags.join('|'),
        'carbon_kg_per_visit': carbonKg,
        'price_rupees': priceRupees,
        'duration_hours': durationHours,
        'is_available_today': 1,
        'views_count': 0,
        'inquiry_count': 0,
      });
      return rowId != 0;
    } catch (_) {
      return onBackend != null;
    }
  }
}
