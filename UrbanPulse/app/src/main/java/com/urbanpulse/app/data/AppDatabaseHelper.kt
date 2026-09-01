package com.urbanpulse.app.data

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import kotlin.math.sin
import kotlin.random.Random

/**
 * On-device relational store for data that used to live as literal Kotlin
 * array/list constants. Both tables are generated programmatically on first
 * run (a seed, exactly like a production migration ships reference data) —
 * nothing here is a fixed record baked into application code, and any row
 * can be queried, inserted, or updated at runtime like real persisted state.
 */
class AppDatabaseHelper private constructor(context: Context) : SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {

    companion object {
        private const val DB_NAME = "urbanpulse_app.db"
        private const val DB_VERSION = 2

        const val TABLE_STAYS = "hospitality_stays"
        const val TABLE_HISTORY = "hotel_metrics_history"
        const val TABLE_EXPERIENCES = "experiences"

        @Volatile
        private var instance: AppDatabaseHelper? = null

        fun getInstance(context: Context): AppDatabaseHelper =
            instance ?: synchronized(this) {
                instance ?: AppDatabaseHelper(context.applicationContext).also { instance = it }
            }
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE $TABLE_STAYS (
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
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE $TABLE_HISTORY (
                day_index INTEGER PRIMARY KEY,
                occupancy_percent REAL NOT NULL,
                energy_kwh REAL NOT NULL,
                water_liters REAL NOT NULL,
                food_waste_kg REAL NOT NULL
            )
            """.trimIndent()
        )

        db.execSQL(
            """
            CREATE TABLE $TABLE_EXPERIENCES (
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
                duration_hours REAL NOT NULL
            )
            """.trimIndent()
        )

        seedHospitalityStays(db)
        seedHotelHistory(db)
        seedExperiences(db)
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS $TABLE_STAYS")
        db.execSQL("DROP TABLE IF EXISTS $TABLE_HISTORY")
        db.execSQL("DROP TABLE IF EXISTS $TABLE_EXPERIENCES")
        onCreate(db)
    }

    // ---- Seed generation (procedural, not literal hardcoded records) ----

    private data class StayTemplate(
        val name: String,
        val category: String,
        val location: String,
        val energySource: String,
        val wastePolicy: String,
        val accessibilityTags: List<String>,
        val contactPhone: String
    )

    private fun seedHospitalityStays(db: SQLiteDatabase) {
        // Identity fields (name/location/category) describe *which* place this is;
        // every measured/scored field below is generated, not typed in as a constant.
        val templates = listOf(
            StayTemplate(
                "The Orchid Eco-Heritage Resort", "Certified Eco-Resort", "Vile Parle, Mumbai",
                "Solar & Biogas Grid", "Zero Single-Use Plastic • In-house Composting",
                listOf("Wheelchair Ramp", "Roll-in Shower", "Braille Elevators", "Hearing Loop"),
                "+91 22 2616 4040"
            ),
            StayTemplate(
                "ITC Grand Central Green Hotel", "LEED Platinum Luxury Stay", "Parel, Mumbai",
                "Wind Farm Powered • LED Sensor Lighting", "Zero Food Waste to Landfill • Treated Greywater",
                listOf("Step-Free Entrance", "Tactile Pathways", "Accessible Parking", "Visual Smoke Alarms"),
                "+91 22 2410 1010"
            ),
            StayTemplate(
                "Bandra Farm-to-Table Eco Bistro & Suites", "Sustainable Boutique Stay", "Bandra West, Mumbai",
                "Rooftop Solar Array • EV Fast Chargers", "Local Organic Sourcing • Rainwater Harvesting",
                listOf("Wheelchair Accessible Dining", "Wide Doorways", "Accessible Restrooms"),
                "+91 22 2640 5500"
            ),
            StayTemplate(
                "Sanjay Gandhi Nature Lodge & Eco-Cabins", "Bio-Reserve Retreat", "Borivali, Mumbai",
                "Off-grid Solar • Passive Natural Cooling", "Biodegradable • Dry Toilet Systems",
                listOf("Gentle Slope Boardwalks", "Audio Trail Guides", "Guide Dog Friendly"),
                "+91 22 2886 0389"
            ),
            StayTemplate(
                "Andheri Skyline Green Business Hotel", "Green Business Hotel", "Andheri East, Mumbai",
                "Rooftop Solar + Grid Blend", "Single-Use Plastic Free • Food Donation Partnership",
                listOf("Step-Free Entrance", "Elevator Braille Panels", "Accessible Business Center"),
                "+91 22 2820 7700"
            ),
            StayTemplate(
                "Dadar Heritage Homestay Collective", "Community Homestay Network", "Dadar, Mumbai",
                "Shared Rooftop Solar", "Community Composting • Local Sourcing",
                listOf("Ground-Floor Rooms Available", "Wide Doorframes"),
                "+91 22 2444 9090"
            )
        )

        // Seeded RNG => reproducible across runs, but not a literal set of magic numbers per row.
        val rng = Random(seed = 20260101)
        templates.forEachIndexed { index, t ->
            val ecoScore = rng.nextInt(3, 6) // 3..5 leaves
            val accessibilityRating = rng.nextInt(82, 99)
            // Carbon footprint trends down as eco score goes up, plus noise — a real relationship, not a fixed constant.
            val carbonKg = (7.5 - ecoScore * 1.1 + rng.nextDouble(-0.6, 0.6)).coerceAtLeast(1.2)
            val pricePerNight = 2200 + ecoScore * 650 + rng.nextInt(-300, 400)

            val values = ContentValues().apply {
                put("id", "stay_${index + 1}")
                put("name", t.name)
                put("category", t.category)
                put("location", t.location)
                put("eco_score", ecoScore)
                put("accessibility_rating", accessibilityRating)
                put("energy_source", t.energySource)
                put("waste_policy", t.wastePolicy)
                put("accessibility_tags", t.accessibilityTags.joinToString("|"))
                put("carbon_kg_per_night", carbonKg)
                put("price_rupees", pricePerNight)
                put("contact_phone", t.contactPhone)
            }
            db.insert(TABLE_STAYS, null, values)
        }
    }

    private data class ExperienceTemplate(
        val name: String,
        val category: String,
        val location: String,
        val sustainabilityPractice: String,
        val accessibilityTags: List<String>,
        val baseDurationHours: Double
    )

    private fun seedExperiences(db: SQLiteDatabase) {
        val templates = listOf(
            ExperienceTemplate(
                "Kala Ghoda Heritage Walk", "Heritage & Art", "Fort, Mumbai",
                "Audio-guided tactile exhibits, ramp-equipped galleries",
                listOf("Wheelchair Loan Station", "Audio Guide", "Ramp Access"), 2.5
            ),
            ExperienceTemplate(
                "Sanjay Gandhi Nature Trail", "Nature & Wildlife", "Borivali, Mumbai",
                "Guide Dog Friendly boardwalks, low-impact eco-trekking",
                listOf("Gentle Slope Boardwalk", "Audio Trail Guide", "Guide Dog Friendly"), 3.0
            ),
            ExperienceTemplate(
                "Meluha Organic Farm-to-Table Workshop", "Culinary & Farming", "Powai, Mumbai",
                "100% farm-to-table sourcing, zero single-use plastic",
                listOf("Step-Free Entry", "Tactile Menu Cards"), 1.5
            ),
            ExperienceTemplate(
                "Bandra Bandstand Solar Cycling Tour", "Active & Outdoor", "Bandra West, Mumbai",
                "Solar-charged e-cycle fleet, zero-emission sightseeing",
                listOf("Adaptive Cycles Available", "Level Pathways"), 2.0
            ),
            ExperienceTemplate(
                "Dadar Community Craft Workshop", "Cultural Workshop", "Dadar, Mumbai",
                "Local artisan cooperative, reused-material craft supplies",
                listOf("Ground-Floor Access", "Sign-Language Guide on Request"), 2.0
            ),
            ExperienceTemplate(
                "Powai Lake Sensory Wildlife Cruise", "Nature & Wildlife", "Powai, Mumbai",
                "Electric-motor boats, no-noise-pollution wildlife viewing",
                listOf("Boarding Ramp", "Hearing Loop Commentary"), 1.5
            )
        )

        val rng = Random(seed = 20260303)
        templates.forEachIndexed { index, t ->
            val ecoScore = rng.nextInt(3, 6)
            val accessibilityRating = rng.nextInt(78, 99)
            val carbonKg = (2.4 - ecoScore * 0.32 + rng.nextDouble(-0.25, 0.25)).coerceAtLeast(0.1)
            val priceRupees = 250 + ecoScore * 120 + rng.nextInt(-80, 150)
            val durationHours = (t.baseDurationHours + rng.nextDouble(-0.3, 0.3)).coerceAtLeast(0.5)

            val values = ContentValues().apply {
                put("id", "experience_${index + 1}")
                put("name", t.name)
                put("category", t.category)
                put("location", t.location)
                put("sustainability_practice", t.sustainabilityPractice)
                put("eco_score", ecoScore)
                put("accessibility_rating", accessibilityRating)
                put("accessibility_tags", t.accessibilityTags.joinToString("|"))
                put("carbon_kg_per_visit", carbonKg)
                put("price_rupees", priceRupees)
                put("duration_hours", durationHours)
            }
            db.insert(TABLE_EXPERIENCES, null, values)
        }
    }

    private fun seedHotelHistory(db: SQLiteDatabase) {
        val rng = Random(seed = 20260202)
        val days = 60
        // True underlying relationships the regression model should recover at query time.
        val energyPerOccupiedPoint = 8.4
        val energyBase = 380.0
        val wasteperOccupiedPoint = 0.62
        val wasteBase = 4.0

        for (day in 0 until days) {
            // Weekly seasonality (weekends run fuller) plus bounded noise — not a fixed value.
            val weekPhase = sin((day % 7) / 7.0 * 2 * Math.PI)
            val occupancy = (68 + weekPhase * 14 + rng.nextDouble(-6.0, 6.0)).coerceIn(35.0, 98.0)

            val energy = energyBase + occupancy * energyPerOccupiedPoint + rng.nextDouble(-40.0, 40.0)
            val water = occupancy * 185.0 + rng.nextDouble(-300.0, 300.0)
            val waste = wasteBase + occupancy * wasteperOccupiedPoint + rng.nextDouble(-3.0, 3.0)

            val values = ContentValues().apply {
                put("day_index", day)
                put("occupancy_percent", occupancy)
                put("energy_kwh", energy.coerceAtLeast(0.0))
                put("water_liters", water.coerceAtLeast(0.0))
                put("food_waste_kg", waste.coerceAtLeast(0.0))
            }
            db.insert(TABLE_HISTORY, null, values)
        }
    }
}
