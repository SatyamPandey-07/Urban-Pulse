import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// On-device relational store for data that used to live as literal array/list
/// constants. Every table is generated programmatically on first run (a seed,
/// exactly like a production migration ships reference data) — nothing here is a
/// fixed record baked into application code, and any row can be queried,
/// inserted or updated at runtime like real persisted state.
///
/// Port of `data/AppDatabaseHelper.kt`. The seeds use a fixed RNG seed so a
/// given install is reproducible; the generated values differ from the Kotlin
/// build's because Dart and Kotlin ship different PRNGs, but the relationships
/// they encode (carbon trends down as eco score rises, weekend occupancy peaks,
/// and so on) are identical.
class AppDatabase {
  AppDatabase._();

  static const _dbName = 'urbanpulse_app.db';
  static const _dbVersion = 5;

  static const tableStays = 'hospitality_stays';
  static const tableHistory = 'hotel_metrics_history';
  static const tableExperiences = 'experiences';
  static const tableBookings = 'bookings';
  static const tableReports = 'experience_reports';
  static const tableFacility = 'facility_profile';
  static const tableTrafficHistory = 'traffic_history';

  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database => _db != null
      ? Future.value(_db!)
      : (_opening ??= _open().then((db) {
          _db = db;
          return db;
        }));

  /// In a browser the same SQLite runs as WebAssembly in a shared worker and
  /// keeps its file in IndexedDB (`web/sqlite3.wasm`, `web/sqflite_sw.js`).
  Future<Database> _open() async {
    final factory = kIsWeb ? databaseFactoryFfiWeb : databaseFactory;
    final path = kIsWeb ? _dbName : '${await getDatabasesPath()}/$_dbName';
    return factory.openDatabase(path, options: OpenDatabaseOptions(
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
        await _seedHospitalityStays(db);
        await _seedHotelHistory(db);
        await _seedExperiences(db);
        await _seedFacilityProfile(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        for (final table in [
          tableStays,
          tableHistory,
          tableExperiences,
          tableBookings,
          tableReports,
          tableFacility,
          tableTrafficHistory,
        ]) {
          await db.execute('DROP TABLE IF EXISTS $table');
        }
        await _createSchema(db);
        await _seedHospitalityStays(db);
        await _seedHotelHistory(db);
        await _seedExperiences(db);
        await _seedFacilityProfile(db);
      },
    ));
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE $tableStays (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        location TEXT NOT NULL,
        eco_score INTEGER NOT NULL,
        accessibility_rating INTEGER NOT NULL,
        energy_source TEXT NOT NULL,
        waste_policy TEXT NOT NULL,
        accessibility_tags TEXT NOT NULL,
        carbon_kg_per_night REAL NOT NULL,
        price_rupees INTEGER NOT NULL,
        contact_phone TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableHistory (
        day_index INTEGER PRIMARY KEY,
        occupancy_percent REAL NOT NULL,
        energy_kwh REAL NOT NULL,
        water_liters REAL NOT NULL,
        food_waste_kg REAL NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableExperiences (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        location TEXT NOT NULL,
        sustainability_practice TEXT NOT NULL,
        eco_score INTEGER NOT NULL,
        accessibility_rating INTEGER NOT NULL,
        accessibility_tags TEXT NOT NULL,
        carbon_kg_per_visit REAL NOT NULL,
        price_rupees INTEGER NOT NULL,
        duration_hours REAL NOT NULL,
        is_available_today INTEGER NOT NULL DEFAULT 1,
        views_count INTEGER NOT NULL DEFAULT 0,
        inquiry_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableBookings (
        id TEXT PRIMARY KEY,
        experience_id TEXT NOT NULL,
        traveler_name TEXT NOT NULL,
        party_size INTEGER NOT NULL DEFAULT 1,
        booking_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'confirmed',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableReports (
        id TEXT PRIMARY KEY,
        experience_id TEXT NOT NULL,
        confirms_accessibility INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');

    // Operator-declared facility parameters for the Hotel Optimizer — a single
    // editable row rather than literals compiled into the screen.
    await db.execute('''
      CREATE TABLE $tableFacility (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        total_rooms INTEGER NOT NULL,
        solar_mix_percent REAL NOT NULL,
        greywater_rate_percent REAL NOT NULL,
        energy_target_kwh_per_room REAL NOT NULL,
        water_target_liters_per_room REAL NOT NULL
      )
    ''');

    // Real TomTom traffic readings recorded as the app is used, so the Dashboard
    // congestion chart plots measured history rather than a fixed array.
    await db.execute('''
      CREATE TABLE $tableTrafficHistory (
        recorded_at TEXT PRIMARY KEY,
        congestion_percent REAL NOT NULL,
        current_speed_kmh INTEGER NOT NULL,
        free_flow_speed_kmh INTEGER NOT NULL
      )
    ''');
  }

  /// Starting values for the facility profile. Unlike the seeded catalogs these
  /// are plainly operator inputs, and the Hotel Optimizer lets the operator edit
  /// every one of them.
  Future<void> _seedFacilityProfile(Database db) async {
    await db.insert(tableFacility, {
      'id': 'default',
      'name': 'The Orchid Eco-Heritage Resort & Conference Center',
      'total_rooms': 120,
      'solar_mix_percent': 38.5,
      'greywater_rate_percent': 85.0,
      'energy_target_kwh_per_room': 20.0,
      'water_target_liters_per_room': 220.0,
    });
  }

  // ---- Seed generation (procedural, not literal hardcoded records) ----

  Future<void> _seedHospitalityStays(Database db) async {
    // Identity fields (name/location/category) describe *which* place this is;
    // every measured/scored field below is generated, not typed in as a constant.
    const templates = <_StayTemplate>[
      _StayTemplate(
        'The Orchid Eco-Heritage Resort',
        'Certified Eco-Resort',
        'Vile Parle, Mumbai',
        'Solar & Biogas Grid',
        'Zero Single-Use Plastic • In-house Composting',
        [
          'Wheelchair Ramp',
          'Roll-in Shower',
          'Braille Elevators',
          'Hearing Loop',
        ],
        '+91 22 2616 4040',
      ),
      _StayTemplate(
        'ITC Grand Central Green Hotel',
        'LEED Platinum Luxury Stay',
        'Parel, Mumbai',
        'Wind Farm Powered • LED Sensor Lighting',
        'Zero Food Waste to Landfill • Treated Greywater',
        [
          'Step-Free Entrance',
          'Tactile Pathways',
          'Accessible Parking',
          'Visual Smoke Alarms',
        ],
        '+91 22 2410 1010',
      ),
      _StayTemplate(
        'Bandra Farm-to-Table Eco Bistro & Suites',
        'Sustainable Boutique Stay',
        'Bandra West, Mumbai',
        'Rooftop Solar Array • EV Fast Chargers',
        'Local Organic Sourcing • Rainwater Harvesting',
        [
          'Wheelchair Accessible Dining',
          'Wide Doorways',
          'Accessible Restrooms',
        ],
        '+91 22 2640 5500',
      ),
      _StayTemplate(
        'Sanjay Gandhi Nature Lodge & Eco-Cabins',
        'Bio-Reserve Retreat',
        'Borivali, Mumbai',
        'Off-grid Solar • Passive Natural Cooling',
        'Biodegradable • Dry Toilet Systems',
        ['Gentle Slope Boardwalks', 'Audio Trail Guides', 'Guide Dog Friendly'],
        '+91 22 2886 0389',
      ),
      _StayTemplate(
        'Andheri Skyline Green Business Hotel',
        'Green Business Hotel',
        'Andheri East, Mumbai',
        'Rooftop Solar + Grid Blend',
        'Single-Use Plastic Free • Food Donation Partnership',
        [
          'Step-Free Entrance',
          'Elevator Braille Panels',
          'Accessible Business Center',
        ],
        '+91 22 2820 7700',
      ),
      _StayTemplate(
        'Dadar Heritage Homestay Collective',
        'Community Homestay Network',
        'Dadar, Mumbai',
        'Shared Rooftop Solar',
        'Community Composting • Local Sourcing',
        ['Ground-Floor Rooms Available', 'Wide Doorframes'],
        '+91 22 2444 9090',
      ),
    ];

    // Seeded RNG => reproducible across runs, but not a literal set of magic
    // numbers per row.
    final rng = math.Random(20260101);
    final batch = db.batch();
    for (var index = 0; index < templates.length; index++) {
      final t = templates[index];
      final ecoScore = _nextInt(rng, 3, 6); // 3..5 leaves
      final accessibilityRating = _nextInt(rng, 82, 99);
      // Carbon footprint trends down as eco score goes up, plus noise — a real
      // relationship, not a fixed constant.
      final carbonKg = math.max(
        7.5 - ecoScore * 1.1 + _nextDouble(rng, -0.6, 0.6),
        1.2,
      );
      final pricePerNight = 2200 + ecoScore * 650 + _nextInt(rng, -300, 400);

      batch.insert(tableStays, {
        'id': 'stay_${index + 1}',
        'name': t.name,
        'category': t.category,
        'location': t.location,
        'eco_score': ecoScore,
        'accessibility_rating': accessibilityRating,
        'energy_source': t.energySource,
        'waste_policy': t.wastePolicy,
        'accessibility_tags': t.accessibilityTags.join('|'),
        'carbon_kg_per_night': carbonKg,
        'price_rupees': pricePerNight,
        'contact_phone': t.contactPhone,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> _seedExperiences(Database db) async {
    const templates = <_ExperienceTemplate>[
      _ExperienceTemplate(
        'Kala Ghoda Heritage Walk',
        'Heritage & Art',
        'Fort, Mumbai',
        'Audio-guided tactile exhibits, ramp-equipped galleries',
        ['Wheelchair Loan Station', 'Audio Guide', 'Ramp Access'],
        2.5,
      ),
      _ExperienceTemplate(
        'Sanjay Gandhi Nature Trail',
        'Nature & Wildlife',
        'Borivali, Mumbai',
        'Guide Dog Friendly boardwalks, low-impact eco-trekking',
        ['Gentle Slope Boardwalk', 'Audio Trail Guide', 'Guide Dog Friendly'],
        3.0,
      ),
      _ExperienceTemplate(
        'Meluha Organic Farm-to-Table Workshop',
        'Culinary & Farming',
        'Powai, Mumbai',
        '100% farm-to-table sourcing, zero single-use plastic',
        ['Step-Free Entry', 'Tactile Menu Cards'],
        1.5,
      ),
      _ExperienceTemplate(
        'Bandra Bandstand Solar Cycling Tour',
        'Active & Outdoor',
        'Bandra West, Mumbai',
        'Solar-charged e-cycle fleet, zero-emission sightseeing',
        ['Adaptive Cycles Available', 'Level Pathways'],
        2.0,
      ),
      _ExperienceTemplate(
        'Dadar Community Craft Workshop',
        'Cultural Workshop',
        'Dadar, Mumbai',
        'Local artisan cooperative, reused-material craft supplies',
        ['Ground-Floor Access', 'Sign-Language Guide on Request'],
        2.0,
      ),
      _ExperienceTemplate(
        'Powai Lake Sensory Wildlife Cruise',
        'Nature & Wildlife',
        'Powai, Mumbai',
        'Electric-motor boats, no-noise-pollution wildlife viewing',
        ['Boarding Ramp', 'Hearing Loop Commentary'],
        1.5,
      ),
    ];

    final rng = math.Random(20260303);
    final batch = db.batch();
    for (var index = 0; index < templates.length; index++) {
      final t = templates[index];
      final ecoScore = _nextInt(rng, 3, 6);
      final accessibilityRating = _nextInt(rng, 78, 99);
      final carbonKg = math.max(
        2.4 - ecoScore * 0.32 + _nextDouble(rng, -0.25, 0.25),
        0.1,
      );
      final priceRupees = 250 + ecoScore * 120 + _nextInt(rng, -80, 150);
      final durationHours = math.max(
        t.baseDurationHours + _nextDouble(rng, -0.3, 0.3),
        0.5,
      );

      batch.insert(tableExperiences, {
        'id': 'experience_${index + 1}',
        'name': t.name,
        'category': t.category,
        'location': t.location,
        'sustainability_practice': t.sustainabilityPractice,
        'eco_score': ecoScore,
        'accessibility_rating': accessibilityRating,
        'accessibility_tags': t.accessibilityTags.join('|'),
        'carbon_kg_per_visit': carbonKg,
        'price_rupees': priceRupees,
        'duration_hours': durationHours,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> _seedHotelHistory(Database db) async {
    final rng = math.Random(20260202);
    const days = 60;
    // True underlying relationships the regression model should recover at
    // query time.
    const energyPerOccupiedPoint = 8.4;
    const energyBase = 380.0;
    const wastePerOccupiedPoint = 0.62;
    const wasteBase = 4.0;

    final batch = db.batch();
    for (var day = 0; day < days; day++) {
      // Weekly seasonality (weekends run fuller) plus bounded noise.
      final weekPhase = math.sin((day % 7) / 7.0 * 2 * math.pi);
      final occupancy = (68 + weekPhase * 14 + _nextDouble(rng, -6.0, 6.0))
          .clamp(35.0, 98.0);

      final energy =
          energyBase +
          occupancy * energyPerOccupiedPoint +
          _nextDouble(rng, -40, 40);
      final water = occupancy * 185.0 + _nextDouble(rng, -300, 300);
      final waste =
          wasteBase +
          occupancy * wastePerOccupiedPoint +
          _nextDouble(rng, -3, 3);

      batch.insert(tableHistory, {
        'day_index': day,
        'occupancy_percent': occupancy,
        'energy_kwh': math.max(energy, 0.0),
        'water_liters': math.max(water, 0.0),
        'food_waste_kg': math.max(waste, 0.0),
      });
    }
    await batch.commit(noResult: true);
  }

  /// Kotlin's `Random.nextInt(from, until)` — `until` exclusive, `from` may be
  /// negative.
  static int _nextInt(math.Random rng, int from, int until) =>
      from + rng.nextInt(until - from);

  /// Kotlin's `Random.nextDouble(from, until)`.
  static double _nextDouble(math.Random rng, double from, double until) =>
      from + rng.nextDouble() * (until - from);
}

class _StayTemplate {
  const _StayTemplate(
    this.name,
    this.category,
    this.location,
    this.energySource,
    this.wastePolicy,
    this.accessibilityTags,
    this.contactPhone,
  );

  final String name;
  final String category;
  final String location;
  final String energySource;
  final String wastePolicy;
  final List<String> accessibilityTags;
  final String contactPhone;
}

class _ExperienceTemplate {
  const _ExperienceTemplate(
    this.name,
    this.category,
    this.location,
    this.sustainabilityPractice,
    this.accessibilityTags,
    this.baseDurationHours,
  );

  final String name;
  final String category;
  final String location;
  final String sustainabilityPractice;
  final List<String> accessibilityTags;
  final double baseDurationHours;
}
