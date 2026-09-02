# UrbanPulse — Intelligent Local Discovery, Sustainable Experience Platform & Autonomous Mobility

**Track:** Local & Experiences — Intelligent Local Discovery & Experience Platform  
**Hackathon:** HackCelestial 3.0 (Pillai University)  
**Target Region:** Mumbai Metropolitan Region, Western Ghats, Himalayan Pilgrimage Corridors & Global Destinations  
**Core Technologies:** Groq LPU AI Engine (`openai/gpt-oss-120b`, `groq/compound`), TomTom Traffic & Routing MCP, Open-Meteo Environmental Intelligence API, Android SQLite Engine, Native PDF Engine (`PdfDocument` + `FileProvider`).

---

## Executive Summary & Track Alignment

UrbanPulse is an intelligent, end-to-end local discovery and sustainable travel platform engineered specifically to address the **"Local & Experiences"** challenge.

When travelers visit a new destination, discovering authentic local food, cultural workshops, festivals, hidden community spaces, and artisan experiences is difficult because data is fragmented across social media, booking portals, and outdated listings. Furthermore, travelers have distinct constraints: limited available time (e.g. only 2 hours near their hotel), tight budgets, group types (families with young children or seniors), and accessibility needs (wheelchairs, strollers, or audio guides). Meanwhile, local small businesses, artisans, and guides struggle to reach travelers genuinely interested in their offerings.

UrbanPulse bridges this gap by moving beyond traditional static search-and-list portals into an **autonomous, context-aware discovery ecosystem**:
1. **Multi-Factor Pareto Experience Optimization:** Balances available time, budget, carbon footprint, and step-free accessibility to recommend optimal local activities.
2. **2-Hour Micro-Experience Engine:** Instantly curates hyper-local experiences that realistically fit within a tight 90-to-120 minute window near the traveler's live GPS coordinates.
3. **Real-Time Circumstance Adaptation:** Dynamically adapts recommendations when circumstances change — automatically swapping outdoor walking/cycling for covered pottery workshops and art galleries during rain, or compressing plans during schedule delays.
4. **Group & Traveler Type Personalization:** Custom filters for *Child-Friendly*, *Family*, *Senior-Friendly*, and *Solo* explorers.
5. **Provider-Side Self-Service Portal & Hub:** Enables local artisans, guides, and activity providers to publish their offerings, toggle real-time availability (`Available Today` vs. `Booked Out`), and view traveler routing demand.
6. **Live Multi-Modal Transit Corridors:** Compares electric trains, e-buses, and Ro-Pax ferries against standard petrol cabs with authentic regional fare formulas and live AQI.

---

## System Architecture

```
+-----------------------------------------------------------------------------------------------+
|                                       UrbanPulse Platform                                     |
|           (Android Native Client: Kotlin / Material 3  +  Web Platform: ES6 / Leaflet)        |
+-----------------------------------------------+-----------------------------------------------+
                                                |
               +--------------------------------+--------------------------------+
               |                                                                 |
               v                                                                 v
+-------------------------------+                               +-------------------------------+
|     Traveler Experience Hub   |                               |      Provider Business Hub    |
| - Conversational Groq Yatri AI|                               | - Self-Service Listing Portal |
| - 2-Hour Micro-Experience Chip|                               | - Real-Time Availability (24/7|
| - Circumstance Adapt (Rain/Del|                               | - Demand & Route Analytics    |
| - Family & Accessibility Tags |                               | - B2B Hotel ESG Resource Hub  |
+---------------+---------------+                               +---------------+---------------+
                |                                                               |
                +-------------------------------+-------------------------------+
                                                |
                                                v
+-----------------------------------------------------------------------------------------------+
|                                    Intelligence & Compute Layer                               |
| - Groq LPU Inference Engine (openai/gpt-oss-120b: Sub-second conversational reasoning)         |
| - Pareto Multi-Objective Optimizer (Equilibrium across Carbon, Price, Accessibility & Time)    |
| - TomTom Routing Engine (Dual-route pathfinding: Green transit corridor vs. Petrol Cab)       |
| - Open-Meteo Environmental Stream (Live Air Quality Index: PM2.5, PM10, AQI status)           |
| - On-Device Relational Store (SQLite TABLE_EXPERIENCES + TABLE_HOSPITALITY + Overrides)       |
| - Android Native PDF Engine (A4 ISO 14064 Compliance Audit Exporter)                          |
+-----------------------------------------------------------------------------------------------+
```

---

## Addressing Hackathon Requirements 100%

### 1. Multi-Factor Contextual Recommendations
Instead of generic tourist lists, UrbanPulse evaluates seven concurrent traveler dimensions:
- **Available Time:** Filters from 2-hour micro-experiences up to 7-day multi-city circuits.
- **Current / Planned Location:** FusedLocationProvider resolves exact GPS coordinates with automatic reverse geocoding to the city/locality level.
- **Budget Sensitivity:** Dynamic price modeling with transit fare breakdowns in INR.
- **Accessibility Requirements:** Native `AccessibilityManager` verifying step-free ramps, level concourses, and tactile/audio guides.
- **Traveler Type & Group Size:** Safe, gentle-slope filters for families with children, senior citizens, and solo adventurers.
- **Eco-Footprint:** Quantitative CO₂e avoided per visit vs. standard fossil-fuel baselines.

### 2. Real-Time Circumstance Adaptation (Rain, Weather, Delays)
Travel plans are unpredictable. UrbanPulse features a 1-tap **"Adapt Plan (Rain / Delay)"** agent:
- **Inclement Weather:** When rain or storms hit, outdoor cycling tours (e.g., Bandra Bandstand) and nature treks are instantly swapped for covered artisan workshops (Dadar Pottery Studio, Kala Ghoda galleries, farm-to-table workshops).
- **Time Crunch:** Compresses multi-hour itineraries into verified 90-minute activities that fit before hotel checkout or flights.

### 3. Provider-Side Experience Portal & Management Hub
Local small businesses and artisans are equal stakeholders on the platform:
- **"+ List Experience" Form:** Allows pottery artists, organic farmers, culinary teachers, and local heritage guides to create verified listings with duration, pricing, and accessibility tags.
- **Provider Dashboard:** Allows providers to toggle status (`Available Today` / `Booked Out`) in real time and track traveler interest through direct route metrics (`184 Traveler Views • 42 Route Inquiries`).
- **Hospitality Resource Hub:** Provides hotel partners with dynamic occupancy-based energy, water, and food surplus diversion tools, certified with ISO 14064 A4 PDF export.

---

## Technical Specifications

| Component | Technology Stack |
|---|---|
| **AI Inference** | Groq LPU Cloud (`openai/gpt-oss-120b`, `groq/compound`) |
| **Android Architecture** | Kotlin, Android SDK 34, Material Design 3, Coroutines, Jetpack Lifecycle |
| **Optimization Algorithm**| Mathematical Pareto Multi-Objective Frontier (`ExperienceOptimizer.kt`) |
| **Mapping & Routing** | TomTom Maps SDK (Native Android) + Leaflet.js Vector Maps (Web) |
| **Environmental Intelligence** | Open-Meteo Air Quality & Weather API (PM2.5, PM10, AQI) |
| **Document Generation** | Android Native `PdfDocument` + `FileProvider` (A4 ISO 14064 Audit) |
| **Persistence** | SQLite Database (`AppDatabaseHelper.kt`) + Encrypted SharedPreferences |

---

## Verified Seeded Local Experiences (Mumbai & Regional)

1. **Kala Ghoda Heritage Walk** (Fort, Mumbai) — 2.5h • ₹250 • Step-Free Ramps • Audio Guide • Tactile Exhibits.
2. **Meluha Organic Farm-to-Table Workshop** (Powai, Mumbai) — 1.5h • ₹450 • 100% Organic • Rain-Safe • Zero Plastic.
3. **Bandra Bandstand Solar Cycling Tour** (Bandra West, Mumbai) — 2.0h • ₹350 • Solar E-Bikes • Level Pathways.
4. **Dadar Artisan Pottery & Craft Studio** (Dadar, Mumbai) — 2.0h • ₹300 • Artisan Cooperative • Reused Clay • Sign-Language Friendly.
5. **Powai Lake Sensory Wildlife Cruise** (Powai, Mumbai) — 1.5h • ₹280 • Silent Electric Boats • Hearing Loops • Boarding Ramps.
6. **Sanjay Gandhi Nature Trail** (Borivali, Mumbai) — 3.0h • ₹200 • Guide Dog Friendly • Gentle Slope Boardwalks.

---

## How to Build & Run

### Android Native App
```bash
# Clone the repository
git clone https://github.com/SatyamPandey-07/Urban-Pulse.git
cd Urban-Pulse/UrbanPulse

# Build debug APK
./gradlew assembleDebug

# Install on connected device
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

### Web Platform
```bash
# From repository root
npx serve .
# Open http://localhost:3000 in your browser
```

---

## Presentation Pitch Deck
The complete 10-slide presentation deck is available in [`ppt.md`](file:///d:/urbanpulse-android-master/urbanpulse-android-master/ppt.md).
