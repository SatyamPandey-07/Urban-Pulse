// UrbanPulse Central Registry — a real, shared backend for the Experiences Provider Hub.
// Replaces the per-browser localStorage store (web) / per-device SQLite store (Android) with
// one real database both clients can read/write, so a provider listing published from either
// client is visible to every other client. Run with: npm install && npm start (defaults to :3001).

const express = require("express");
const cors = require("cors");
const Database = require("better-sqlite3");
const path = require("path");
const fs = require("fs");
const crypto = require("crypto");

const PORT = process.env.PORT || 3001;
const DATA_DIR = path.join(__dirname, "data");
const DB_PATH = path.join(DATA_DIR, "urbanpulse.db");

fs.mkdirSync(DATA_DIR, { recursive: true });
const db = new Database(DB_PATH);
db.pragma("journal_mode = WAL");

db.exec(`
  CREATE TABLE IF NOT EXISTS experiences (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    location TEXT NOT NULL,
    duration REAL NOT NULL,
    price INTEGER NOT NULL,
    eco_score INTEGER NOT NULL DEFAULT 5,
    accessibility_rating INTEGER NOT NULL DEFAULT 75,
    accessibility_tags TEXT NOT NULL DEFAULT '[]',
    sustainability TEXT NOT NULL DEFAULT '',
    carbon_kg REAL NOT NULL DEFAULT 0.3,
    is_available_today INTEGER NOT NULL DEFAULT 1,
    views_count INTEGER NOT NULL DEFAULT 0,
    inquiry_count INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS bookings (
    id TEXT PRIMARY KEY,
    experience_id TEXT NOT NULL REFERENCES experiences(id),
    traveler_name TEXT NOT NULL,
    party_size INTEGER NOT NULL DEFAULT 1,
    booking_date TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'confirmed',
    created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS experience_reports (
    id TEXT PRIMARY KEY,
    experience_id TEXT NOT NULL REFERENCES experiences(id),
    confirms_accessibility INTEGER NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL
  );
`);

const SEED_EXPERIENCES = [
    {
        id: "exp_1", name: "Kala Ghoda Heritage Walk", category: "Heritage & Art", location: "Fort, Mumbai",
        duration: 2.5, price: 250, ecoScore: 5, accessibilityRating: 94,
        accessibilityTags: ["Wheelchair Ramp Access", "Audio Guide"],
        sustainability: "Audio-guided tactile exhibits, zero paper brochure", carbonKg: 0.3
    },
    {
        id: "exp_2", name: "Meluha Organic Farm-to-Table Workshop", category: "Culinary & Farming", location: "Powai, Mumbai",
        duration: 1.5, price: 450, ecoScore: 5, accessibilityRating: 92,
        accessibilityTags: ["Step-Free Entry", "Tactile Menu Cards"],
        sustainability: "100% farm-to-table organic sourcing, zero single-use plastic", carbonKg: 0.2
    },
    {
        id: "exp_3", name: "Bandra Bandstand Solar Cycling Tour", category: "Active & Outdoor", location: "Bandra West, Mumbai",
        duration: 2.0, price: 350, ecoScore: 5, accessibilityRating: 88,
        accessibilityTags: ["Adaptive Cycles Available", "Level Pathways"],
        sustainability: "Solar-charged e-cycle fleet, zero-emission sightseeing", carbonKg: 0.1
    },
    {
        id: "exp_4", name: "Dadar Artisan Pottery & Craft Studio", category: "Cultural Workshop", location: "Dadar, Mumbai",
        duration: 2.0, price: 300, ecoScore: 4, accessibilityRating: 90,
        accessibilityTags: ["Ground-Floor Access", "Sign-Language Guide"],
        sustainability: "Reused-material craft supplies, local artisan cooperative", carbonKg: 0.4
    },
    {
        id: "exp_5", name: "Powai Lake Sensory Wildlife Cruise", category: "Nature & Wildlife", location: "Powai, Mumbai",
        duration: 1.5, price: 280, ecoScore: 5, accessibilityRating: 95,
        accessibilityTags: ["Boarding Ramp", "Hearing Loop Commentary"],
        sustainability: "Silent electric-motor boats, no-noise wildlife sanctuary", carbonKg: 0.2
    }
];

const seedIfEmpty = db.prepare("SELECT COUNT(*) AS n FROM experiences").get();
if (seedIfEmpty.n === 0) {
    const insert = db.prepare(`
        INSERT INTO experiences (id, name, category, location, duration, price, eco_score, accessibility_rating, accessibility_tags, sustainability, carbon_kg, is_available_today, views_count, inquiry_count, created_at)
        VALUES (@id, @name, @category, @location, @duration, @price, @ecoScore, @accessibilityRating, @accessibilityTags, @sustainability, @carbonKg, 1, 0, 0, @createdAt)
    `);
    const seedTx = db.transaction((rows) => {
        for (const row of rows) {
            insert.run({
                ...row,
                accessibilityTags: JSON.stringify(row.accessibilityTags),
                createdAt: new Date().toISOString()
            });
        }
    });
    seedTx(SEED_EXPERIENCES);
}

const countBookings = db.prepare("SELECT COUNT(*) AS n FROM bookings WHERE experience_id = ? AND status = 'confirmed'");
const countReports = db.prepare("SELECT confirms_accessibility, COUNT(*) AS n FROM experience_reports WHERE experience_id = ? GROUP BY confirms_accessibility");

function rowToJson(row) {
    const reportRows = countReports.all(row.id);
    const confirmCount = reportRows.find(r => r.confirms_accessibility === 1)?.n || 0;
    const disputeCount = reportRows.find(r => r.confirms_accessibility === 0)?.n || 0;
    return {
        id: row.id,
        name: row.name,
        category: row.category,
        location: row.location,
        duration: row.duration,
        price: row.price,
        ecoScore: row.eco_score,
        accessibilityRating: row.accessibility_rating,
        accessibilityTags: JSON.parse(row.accessibility_tags),
        sustainability: row.sustainability,
        carbonKg: row.carbon_kg,
        isAvailableToday: !!row.is_available_today,
        viewsCount: row.views_count,
        inquiryCount: row.inquiry_count,
        bookingCount: countBookings.get(row.id).n,
        accessibilityConfirmCount: confirmCount,
        accessibilityDisputeCount: disputeCount,
        createdAt: row.created_at
    };
}

function bookingRowToJson(row) {
    return {
        id: row.id,
        experienceId: row.experience_id,
        travelerName: row.traveler_name,
        partySize: row.party_size,
        bookingDate: row.booking_date,
        status: row.status,
        createdAt: row.created_at
    };
}

function reportRowToJson(row) {
    return {
        id: row.id,
        experienceId: row.experience_id,
        confirmsAccessibility: !!row.confirms_accessibility,
        note: row.note,
        createdAt: row.created_at
    };
}

const app = express();
app.use(cors());
app.use(express.json());

app.get("/api/health", (req, res) => {
    res.json({ status: "ok", dbPath: DB_PATH });
});

app.get("/api/experiences", (req, res) => {
    const rows = db.prepare("SELECT * FROM experiences ORDER BY created_at DESC").all();
    res.json(rows.map(rowToJson));
});

app.post("/api/experiences", (req, res) => {
    const body = req.body || {};
    if (!body.name || typeof body.name !== "string") {
        return res.status(400).json({ error: "name is required" });
    }
    const id = "exp_" + crypto.randomUUID();
    const row = {
        id,
        name: body.name,
        category: body.category || "General",
        location: body.location || "Mumbai",
        duration: Number(body.duration) || 2.0,
        price: Number(body.price) || 350,
        ecoScore: Number(body.ecoScore) || 5,
        accessibilityRating: Number(body.accessibilityRating) || 75,
        accessibilityTags: JSON.stringify(body.accessibilityTags || ["Standard Access"]),
        sustainability: body.sustainability || "Local community cooperative",
        carbonKg: Number(body.carbonKg) || 0.3,
        createdAt: new Date().toISOString()
    };
    db.prepare(`
        INSERT INTO experiences (id, name, category, location, duration, price, eco_score, accessibility_rating, accessibility_tags, sustainability, carbon_kg, is_available_today, views_count, inquiry_count, created_at)
        VALUES (@id, @name, @category, @location, @duration, @price, @ecoScore, @accessibilityRating, @accessibilityTags, @sustainability, @carbonKg, 1, 0, 0, @createdAt)
    `).run(row);
    const saved = db.prepare("SELECT * FROM experiences WHERE id = ?").get(id);
    res.status(201).json(rowToJson(saved));
});

app.patch("/api/experiences/:id/availability", (req, res) => {
    const existing = db.prepare("SELECT * FROM experiences WHERE id = ?").get(req.params.id);
    if (!existing) return res.status(404).json({ error: "not found" });
    const next = existing.is_available_today ? 0 : 1;
    db.prepare("UPDATE experiences SET is_available_today = ? WHERE id = ?").run(next, req.params.id);
    res.json(rowToJson(db.prepare("SELECT * FROM experiences WHERE id = ?").get(req.params.id)));
});

app.post("/api/experiences/:id/view", (req, res) => {
    const existing = db.prepare("SELECT * FROM experiences WHERE id = ?").get(req.params.id);
    if (!existing) return res.status(404).json({ error: "not found" });
    db.prepare("UPDATE experiences SET views_count = views_count + 1 WHERE id = ?").run(req.params.id);
    res.json(rowToJson(db.prepare("SELECT * FROM experiences WHERE id = ?").get(req.params.id)));
});

app.post("/api/experiences/:id/inquiry", (req, res) => {
    const existing = db.prepare("SELECT * FROM experiences WHERE id = ?").get(req.params.id);
    if (!existing) return res.status(404).json({ error: "not found" });
    db.prepare("UPDATE experiences SET inquiry_count = inquiry_count + 1 WHERE id = ?").run(req.params.id);
    res.json(rowToJson(db.prepare("SELECT * FROM experiences WHERE id = ?").get(req.params.id)));
});

// --- Bookings: real persisted records, not a hardcoded "184 bookings" style metric ---

app.post("/api/experiences/:id/bookings", (req, res) => {
    const existing = db.prepare("SELECT * FROM experiences WHERE id = ?").get(req.params.id);
    if (!existing) return res.status(404).json({ error: "not found" });
    const body = req.body || {};
    if (!body.travelerName || typeof body.travelerName !== "string") {
        return res.status(400).json({ error: "travelerName is required" });
    }
    const id = "booking_" + crypto.randomUUID();
    const row = {
        id,
        experienceId: req.params.id,
        travelerName: body.travelerName,
        partySize: Number(body.partySize) || 1,
        bookingDate: body.bookingDate || new Date().toISOString().slice(0, 10),
        createdAt: new Date().toISOString()
    };
    db.prepare(`
        INSERT INTO bookings (id, experience_id, traveler_name, party_size, booking_date, status, created_at)
        VALUES (@id, @experienceId, @travelerName, @partySize, @bookingDate, 'confirmed', @createdAt)
    `).run(row);
    const saved = db.prepare("SELECT * FROM bookings WHERE id = ?").get(id);
    res.status(201).json(bookingRowToJson(saved));
});

app.get("/api/experiences/:id/bookings", (req, res) => {
    const rows = db.prepare("SELECT * FROM bookings WHERE experience_id = ? ORDER BY created_at DESC").all(req.params.id);
    res.json(rows.map(bookingRowToJson));
});

// --- Traveler accessibility reports: a real second, independent signal for the Evidence Graph ---
// (confirms or disputes the provider's own accessibility claim — genuine corroboration/contradiction,
// not the same source checked against itself)

app.post("/api/experiences/:id/reports", (req, res) => {
    const existing = db.prepare("SELECT * FROM experiences WHERE id = ?").get(req.params.id);
    if (!existing) return res.status(404).json({ error: "not found" });
    const body = req.body || {};
    if (typeof body.confirmsAccessibility !== "boolean") {
        return res.status(400).json({ error: "confirmsAccessibility (boolean) is required" });
    }
    const id = "report_" + crypto.randomUUID();
    db.prepare(`
        INSERT INTO experience_reports (id, experience_id, confirms_accessibility, note, created_at)
        VALUES (?, ?, ?, ?, ?)
    `).run(id, req.params.id, body.confirmsAccessibility ? 1 : 0, body.note || "", new Date().toISOString());
    const saved = db.prepare("SELECT * FROM experience_reports WHERE id = ?").get(id);
    res.status(201).json(reportRowToJson(saved));
});

app.get("/api/experiences/:id/reports", (req, res) => {
    const rows = db.prepare("SELECT * FROM experience_reports WHERE experience_id = ? ORDER BY created_at DESC").all(req.params.id);
    res.json(rows.map(reportRowToJson));
});

// --- Impact Dashboard: real cross-platform aggregates, computed live via SQL — not a
// fabricated "X kg CO2 saved" headline number. Only reports what's genuinely measurable
// from persisted rows (bookings, travelers, accessibility reports, listings).

app.get("/api/impact-stats", (req, res) => {
    const experienceCount = db.prepare("SELECT COUNT(*) AS n FROM experiences").get().n;
    const bookingStats = db.prepare(
        "SELECT COUNT(*) AS bookingCount, COALESCE(SUM(party_size), 0) AS travelerCount FROM bookings WHERE status = 'confirmed'"
    ).get();
    const reportStats = db.prepare(
        "SELECT confirms_accessibility, COUNT(*) AS n FROM experience_reports GROUP BY confirms_accessibility"
    ).all();
    const confirmCount = reportStats.find(r => r.confirms_accessibility === 1)?.n || 0;
    const disputeCount = reportStats.find(r => r.confirms_accessibility === 0)?.n || 0;
    const carbonFootprint = db.prepare(`
        SELECT COALESCE(SUM(e.carbon_kg * b.cnt), 0) AS totalKg
        FROM experiences e
        JOIN (SELECT experience_id, COUNT(*) AS cnt FROM bookings WHERE status = 'confirmed' GROUP BY experience_id) b
        ON b.experience_id = e.id
    `).get().totalKg;
    const avgEcoScore = db.prepare("SELECT AVG(eco_score) AS avg FROM experiences").get().avg || 0;
    const topExperiences = db.prepare(`
        SELECT e.id, e.name, e.location,
               (SELECT COUNT(*) FROM bookings WHERE experience_id = e.id AND status = 'confirmed') AS bookingCount
        FROM experiences e
        ORDER BY bookingCount DESC, e.eco_score DESC
        LIMIT 5
    `).all();

    res.json({
        experienceCount,
        bookingCount: bookingStats.bookingCount,
        travelerCount: bookingStats.travelerCount,
        accessibilityConfirmCount: confirmCount,
        accessibilityDisputeCount: disputeCount,
        bookedExperiencesCarbonFootprintKg: Math.round(carbonFootprint * 10) / 10,
        averageEcoScore: Math.round(avgEcoScore * 10) / 10,
        topExperiences: topExperiences.map(e => ({ id: e.id, name: e.name, location: e.location, bookingCount: e.bookingCount })),
        generatedAt: new Date().toISOString()
    });
});

app.listen(PORT, () => {
    console.log(`UrbanPulse Central Registry listening on http://localhost:${PORT}`);
    console.log(`SQLite database: ${DB_PATH}`);
});
