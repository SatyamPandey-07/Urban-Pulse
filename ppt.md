# UrbanPulse — HackCelestial 3.0 Presentation Deck

**Project Name:** UrbanPulse  
**Tagline:** Autonomous Groq AI Mobility, Step-Free Navigation & B2B Hospitality Intelligence Platform  
**Target Category:** Smart Mobility, Environmental Sustainability & Inclusive Tourism  
**Venue:** Pillai University, HackCelestial 3.0  
**AI Inference Engine:** Groq LPU Cloud (`openai/gpt-oss-120b`, `groq/compound`)  

---

## Slide 1: Title & Vision

### UrbanPulse
**Empowering Sustainable Transit, Step-Free Mobility & ESG Hospitality**

- **The Vision:** Transforming urban mobility from a high-emission bottleneck into an equitable, zero-compromise green network.
- **The Solution:** An integrated mobile and web intelligence suite combining real-time dual-route comparison, autonomous Groq AI trip planning, and B2B hotel resource optimization with official ISO 14064 A4 PDF audit reports.
- **Presenter:** UrbanPulse Engineering Team

---

## Slide 2: The Core Problem

### Urban Mobility & Tourism Pain Points

1. **Emission Blindness & High Taxi Fares:**
   - Travelers lack real-time visibility into the carbon disparity between private cabs and electrified public transit corridors.
   - Standard cabs in metropolitan zones run on high base rates with congestion multipliers, generating up to 160g CO2e/km per passenger.

2. **Static & Hardcoded Itinerary Portals:**
   - Conventional travel apps show hardcoded templates that fail to account for the traveler's actual starting GPS location or specific accessibility needs.

3. **Accessibility Barriers (The Step-Free Deficit):**
   - Wheelchair users, senior citizens, and families with strollers face unmapped stairs, missing elevator links, and inaccessible boarding concourses.

4. **B2B Hospitality Resource Inefficiencies:**
   - Hotels lack automated forecasting tools to manage power loads, prevent food waste, and export verifiable ISO 14064 ESG compliance reports.

---

## Slide 3: Our Solution — The UrbanPulse Ecosystem

### Tri-Pillar Architecture

```
+-----------------------------------------------------------------------------------+
|                                  UrbanPulse Core                                  |
+--------------------------+------------------------------+-------------------------+
|   1. B2C Green Routing   |   2. Autonomous Groq AI      |   3. B2B Hotel ESG Hub  |
| - Live Dual-Path Mapping | - Groq LPU Inference         | - Occupancy Forecasting |
| - Open-Meteo AQI Ground  | - Interactive MCQ Dialogue   | - HVAC Setback Auto     |
| - Exact MH Taxi Formulas | - Dynamic Origin Anchoring   | - ISO 14064 A4 PDF Gen  |
+--------------------------+------------------------------+-------------------------+
```

---

## Slide 4: Feature 1 — Live Dual-Route Comparison Engine

### Standard Route vs. Green Path

- **Simultaneous Rendering:** Visualizes the conventional vehicle route side-by-side with the low-carbon public transit corridor on an interactive vector map.
- **Mathematical Grounding:**
  - Standard Cab: Base Rs 28 + Rs 18.50/km (Maharashtra Transport Dept formula, 160g CO2/km).
  - Green Transit: Tiered public pricing (Rs 10 to Rs 75, 14g to 28g CO2/km).
- **Environmental Context:** Live Open-Meteo Air Quality Index (AQI) displayed on a floating HUD.
- **Accessibility Verification:** 100% level boarding, elevator availability, and tactile paving status flagged on the route.

---

## Slide 5: Feature 2 — Autonomous Groq AI Trip Planner

### Powered by Groq LPU Inference (Zero Hardcoding)

- **Real Groq Model Suite:** Connects directly to active Groq models (`openai/gpt-oss-120b`, `groq/compound`) for sub-second agentic reasoning.
- **Interactive Multi-Turn MCQ Dialogue:**
  - Guides travelers through Multiple-Choice Questions for duration (1-7 days) and travel styles (Wheelchair Step-Free, Eco Pilgrim Trek, Budget Explorer, Luxury Solar Heritage).
- **Dynamic Origin GPS Anchoring:**
  - Dynamically fetches the user's real-time GPS location via native reverse geocoding so Day 1 transit originates realistically from their current city (e.g. Mumbai, Navi Mumbai, Thane).
- **Universal Destination Support:**
  - Synthesizes itineraries for any location worldwide (Matheran, Kedarnath Dham, Lonavala, Alibaug, Manali, Goa, Jaipur, Tokyo).
- **Structured Output:**
  - Outputs departure times, specific electrified transit connections (Central Local, Toy Train, Vande Bharat, AC E-Bus), verified eco-hotels, and alternative transit comparisons.

---

## Slide 6: Feature 3 — Dedicated Trips Hub & Carbon Passport

### Gamified Sustainable Tourism

- **Offline-First Itinerary Storage:** Saved trips can be accessed anytime with one tap.
- **Full-Timeline Schedule Inspector:** Inspect day-by-day itineraries, transfer stations, step-free access flags, and landmark timings.
- **Carbon Credit Economy:**
  - Awards verified PULSE Points for every kilogram of CO2e avoided compared to standard vehicle travel.

---

## Slide 7: Feature 4 — B2B Hotel Sustainability Optimizer

### Enterprise ESG Compliance & Resource Management

- **Dynamic Occupancy Slider:** Real-time recalculation of power consumption (kWh), greywater recycled (Liters), and kitchen food surplus (kg).
- **Automated HVAC Setpoint:** One-tap 26°C setback for unoccupied wings, reducing daily electricity load by up to 180 kWh.
- **Surplus Food Rescue:** Instant dispatch trigger connecting hotel kitchens to verified food shelters (Feeding India / Roti Bank).
- **Native ISO 14064 A4 PDF Audit Generator:**
  - Generates verifiable, cryptographic, vector-based PDF audit reports directly on the device using Android's native `PdfDocument` engine, shareable via Android `FileProvider`.

---

## Slide 8: Technical Architecture & Stack

### Enterprise-Grade Tech Stack

| Layer | Technologies Used |
|---|---|
| **AI Inference** | Groq LPU Cloud (`openai/gpt-oss-120b`, `groq/compound`) |
| **Mobile Client** | Android SDK 34 (Kotlin, Jetpack Compose, Material 3, Coroutines) |
| **Web Platform** | HTML5, Vanilla ES6 JavaScript, CSS3 Design System, Leaflet.js |
| **Mapping & Routing** | TomTom Maps SDK, Routing & Traffic Flow APIs |
| **Sensors & Environment** | Open-Meteo Air Quality (PM2.5, PM10, AQI) |
| **PDF Document Engine** | Android Native `PdfDocument` + `FileProvider` |
| **Persistence** | Room SQLite Database, Encrypted SharedPreferences |

---

## Slide 9: Live Demo Walkthrough

### What Evaluators Can Test Right Now

1. **One-Tap Demo Access:** Instant reviewer login on Welcome/Login screens without registration friction.
2. **Dual-Route Canvas:** Select destinations (Lonavala, Kedarnath, Fortis Mulund, Powai EV Hub, CSMT, Alibaug) and observe the simultaneous Red vs. Green path comparison.
3. **Groq Yatri AI Dialogue:** Ask "Plan a trip to Matheran" or "Plan a trip to Kedarnath" and experience the interactive MCQ questions and origin-anchored itinerary synthesis powered by Groq.
4. **Trips Hub Inspection:** Tap "View Schedule" to review complete multi-day timelines.
5. **Hotel ESG PDF Export:** Adjust the occupancy slider and tap "Download PDF Report" to generate an authentic A4 PDF audit document.

---

## Slide 10: Conclusion & Impact

### Sustainable Transit for Millions

- **Scalability:** Zero server maintenance costs through high-throughput Groq LPU inference and client-side document compilation.
- **Social Impact:** 100% verified step-free accessibility ensuring no traveler is left behind.
- **Environmental Impact:** Measurable, auditable carbon reduction across metropolitan and regional transit networks.

**Thank You!**  
*GitHub Repository:* [https://github.com/SatyamPandey-07/Urban-Pulse](https://github.com/SatyamPandey-07/Urban-Pulse)  
*Release APK:* [v1.0.0-hackcelestial](https://github.com/SatyamPandey-07/Urban-Pulse/releases/tag/v1.0.0-hackcelestial)
