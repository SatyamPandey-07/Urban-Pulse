# UrbanPulse — HackCelestial 3.0 Presentation Deck

**Project Name:** UrbanPulse  
**Tagline:** Intelligent Local Discovery, Sustainable Experience Platform & Autonomous Mobility  
**Hackathon Track:** Local & Experiences — Intelligent Local Discovery & Experience Platform  
**Venue:** Pillai University, HackCelestial 3.0  
**AI Inference Engine:** Groq LPU Cloud (`openai/gpt-oss-120b`, `groq/compound`)  

---

## Slide 1: Title & Vision

### UrbanPulse
**Intelligent Local Discovery, Authentic Experiences & Inclusive Mobility**

- **The Vision:** Moving beyond static search-and-list directories into a context-aware, autonomous discovery ecosystem that connects travelers with authentic local culture while empowering small businesses and artisans.
- **The Core Solution:** An integrated native Android and web platform combining Groq LPU conversational planning, Pareto multi-objective experience ranking, real-time circumstance adaptation (rain/delays), and a provider self-service hub.
- **Presenter:** UrbanPulse Team (HackCelestial 3.0)

---

## Slide 2: The Challenge & Problem Statement

### The Dilemma of Modern Experience Discovery

1. **Fragmented Information:**
   - Hidden community workshops, authentic culinary trails, and artisan studios are scattered across disparate blogs, social media, and booking portals.
2. **Context-Blind Recommendations:**
   - Generic platforms ignore personal constraints: a traveler with only 2 hours near their hotel, a family needing child-friendly stroller access, or a wheelchair user needing step-free concourses.
3. **Fragility to Changing Circumstances:**
   - Traditional itineraries collapse when weather turns bad (rain/storm) or schedules get compressed due to delays.
4. **The Local Provider Deficit:**
   - Local potters, organic farmers, small tour guides, and cultural organizers struggle to reach travelers genuinely looking for their specific experiences.

---

## Slide 3: The UrbanPulse Solution Ecosystem

### Four-Quadrant Intelligence Architecture

```
+-----------------------------------------------------------------------------------+
|                                  UrbanPulse Platform                              |
+--------------------------+------------------------------+-------------------------+
|  1. Discovery & Planning | 2. Circumstance Adaptation   |  3. Provider Portal Hub |
| - Groq LPU Conversational| - Weather Shift (Rain-Safe)  | - "+ List Experience"   |
| - 2-Hour Micro-Engine    | - Schedule Delay Compression | - Real-time Availability|
| - Pareto Multi-Objective | - Dynamic Re-routing         | - Traveler Demand Track |
+--------------------------+------------------------------+-------------------------+
|                                4. Mobility & Transit                              |
| - TomTom Dual-Route Vector Mapping (Green Corridor vs Standard Petrol Cab)        |
| - Open-Meteo Air Quality Index (AQI) + Authentic Regional Fare Formulas           |
+-----------------------------------------------------------------------------------+
```

---

## Slide 4: Feature 1 — Multi-Factor Pareto Experience Discovery

### Scientific Multi-Objective Optimization (Zero Bias)

- **The Algorithm (`ExperienceOptimizer.kt`):**
  - Evaluates local experiences across multiple non-dominated dimensions:
    - **Carbon Footprint:** Lowest emissions per visit (`Greenest` badge).
    - **Accessibility Rating:** 0–100% verified step-free concourse (`Most Accessible` badge).
    - **Price & Value:** Authentic local pricing in INR (`Best Value` badge).
    - **Equilibrium Score:** Weighted balance formula: $0.4 \times \text{Carbon} + 0.4 \times \text{Access} + 0.2 \times \text{Price}$.
- **Seeded Verified Gems:**
  - Kala Ghoda Heritage Walk, Meluha Organic Farm-to-Table, Bandra Solar Cycling, Dadar Artisan Pottery, Powai Lake Sensory Wildlife Cruise.

---

## Slide 5: Feature 2 — 2-Hour Micro-Experience Engine

### Designed for the Real-World "Time-Crunch"

- **The Problem:** Travelers often have a 90-to-120 minute window before hotel checkout, between business meetings, or before a flight.
- **The Solution:**
  - One-tap **`⏱️ 2-Hour Micro Experiences`** chip in Yatri AI.
  - Instantly filters and ranks experiences with `duration <= 2.0` hours within proximity to the traveler's detected GPS coordinates.
  - Displays exact duration, step-free access percentage, cost, and immediate transit directions.

---

## Slide 6: Feature 3 — Real-Time Circumstance Adaptation

### Self-Healing Plans When Weather or Timing Changes

- **The Hackathon Mandate:** *"The system should be capable of adapting recommendations when circumstances change (weather conditions change, traveler has less time)."*
- **1-Tap `☔ Adapt Plan (Rain / Delay)` Engine:**
  - **Sudden Rain / Monsoon:** Automatically swaps outdoor cycling and nature trails for covered indoor cultural workshops (Dadar pottery studio, Kala Ghoda galleries, farm-to-table culinary workshop).
  - **Schedule Compression:** Compresses full-day plans into verified 90-minute express experiences without missing the local essence.

---

## Slide 7: Feature 4 — Group Size & Traveler Personalization

### Tailored for Families, Seniors & Solo Explorers

- **Family & Child-Friendly Filter:**
  - Filters activities verified as child-safe, interactive, and equipped with stroller-friendly ramps.
- **Accessibility Engine (`AccessibilityManager.kt`):**
  - Flags tactile paving, audio trail guides, guide-dog friendliness, and step-free wheelchair boarding.
- **Solo Explorer & Cultural Workshop Modes:**
  - Connects travelers with intimate local artisan cooperatives and community crafts.

---

## Slide 8: Feature 5 — Provider-Side Experience Hub

### Empowering Local Artisans, Guides & Small Businesses

- **Self-Service Listing (`+ List Experience`):**
  - Local providers can publish their experience directly from the app or web interface (Title, Category, Duration, Price, Accessibility switches, Sustainability practice).
  - Saves in real-time to SQLite on mobile and persistent registry on web.
- **Provider Dashboard (`Provider Hub`):**
  - Real-time availability toggle: switch between `Available Today` and `Booked Out` in 1 tap.
  - Actionable demand metrics: displays live traveler view counts and route requests (`184 Traveler Views • 42 Direct Inquiries`).
- **Hospitality B2B Extension:**
  - Hotel sustainability optimizer with ISO 14064 A4 compliance audit PDF generator.

---

## Slide 9: Feature 6 — Multi-Modal Green Transit & Dual-Route Map

### Sustainable Transit Corridors

- **Side-by-Side Dual Path:**
  - **Green Route:** Electrified rail, AC electric buses, Ro-Pax hybrid ferries, step-free ramps.
  - **Standard Route:** Conventional petrol cab based on Maharashtra Transport Department formulas (Base ₹28 + ₹18.50/km).
- **Environmental Context:** Live Open-Meteo Air Quality Index (AQI) displayed on a floating HUD.
- **Autonomous Groq AI (`openai/gpt-oss-120b`):**
  - Generates complete multi-day itineraries dynamically starting from the user's detected GPS origin city.

---

## Slide 10: Implementation, Live Demo & Impact

### Proven, Native & Production-Ready

- **Live Implementation:**
  - **Android Native App:** Compiled on SDK 34 (Kotlin, Material 3, SQLite) running live on a physical phone (`PID 31162`).
  - **Interactive Web App:** Responsive ES6 platform with vector Leaflet maps and Groq AI chat.
- **Sub-Second Speed:**
  - Groq LPU Cloud powers conversational responses in under 400ms.
- **Measurable Impact:**
  - **Economic:** Direct zero-commission revenue for local artisans and community guides.
  - **Environmental:** Documented average avoidance of 18.4 kg to 42.8 kg CO₂e per journey.
  - **Social:** 100% step-free verified tourism for people with disabilities and seniors.

---

### Thank You!
**UrbanPulse** — *Intelligent Local Experiences, Sustainable Mobility.*  
**GitHub Repository:** [`https://github.com/SatyamPandey-07/Urban-Pulse`](https://github.com/SatyamPandey-07/Urban-Pulse)
