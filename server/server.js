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

function rowToJson(row) {
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

app.listen(PORT, () => {
    console.log(`UrbanPulse Central Registry listening on http://localhost:${PORT}`);
    console.log(`SQLite database: ${DB_PATH}`);
});
