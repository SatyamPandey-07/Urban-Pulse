# UrbanPulse — Autonomous Green Mobility, Accessible Navigation & B2B Hospitality Intelligence Platform

**Track:** Smart Mobility & Sustainable Tourism | **Hackathon:** HackCelestial 3.0 (Pillai University)  
**Target Region:** Mumbai Metropolitan Region, Western Ghats, Himalayan Pilgrimage Corridors & Global Destinations  
**AI & Cloud Tech:** Groq LPU AI Engine (`openai/gpt-oss-120b` & `groq/compound` models), TomTom Traffic & Dual-Route MCP, Open-Meteo Environmental Intelligence API, Android Native PDF Engine (`PdfDocument` + `FileProvider`).

---

## Executive Summary

UrbanPulse is an end-to-end intelligent urban mobility and sustainable hospitality platform. It addresses urban transport emissions and accessibility barriers by combining real-time routing engines, multimodal carbon estimators, autonomous AI travel planners powered by **Groq LPU Inference**, and B2B hotel resource optimization with verifiable ISO 14064 ESG compliance reporting.

Unlike static trip planners, UrbanPulse anchors all calculations to the traveler's live detected GPS origin city (e.g., Mumbai, Navi Mumbai, Thane), calculates simultaneous dual-path routes (standard vehicle vs. eco-transit corridor) using verified municipal taxi fare formulas, dynamically queries live air quality indexes (AQI), and deploys autonomous Groq AI agents to construct complete, step-free, low-carbon itineraries for any destination worldwide.

---

## System Architecture

```
+-----------------------------------------------------------------------------------+
|                                 UrbanPulse Client                                 |
|   (Android Native App - Kotlin / Material 3  +  Web App - Vanilla ES6 / Leaflet)  |
+----------------------------------------+------------------------------------------+
                                         |
               +-------------------------+-------------------------+
               |                                                   |
               v                                                   v
+-----------------------------+                           +-----------------------------+
|    Groq AI Agentic Engine   |                           |    TomTom Routing & Traffic |
|  (OpenAI / Groq Compound)   |                           |    (Fastest Car vs. Eco)    |
| - Autonomous Itinerary Gen  |                           | - Real Dual-Path Geometry   |
| - Interactive MCQ Dialogue  |                           | - Turn-by-Turn Waypoints    |
| - Dynamic Origin Anchoring  |                           | - Bottleneck Delay Insights |
+--------------+--------------+                           +--------------+--------------+
               |                                                         |
               +-------------------------+-------------------------------+
                                         |
                                         v
+-----------------------------------------------------------------------------------+
|                             Core Intelligence Modules                             |
|  - Dynamic Trip Planner (Day-by-Day Timeline, Origin-to-Destination Transit)      |
|  - Multimodal Carbon Calculator (CO2e avoided vs. Regional Baseline)              |
|  - Open-Meteo Environmental Intelligence (PM2.5, PM10, European/US AQI)           |
|  - B2B Hotel Sustainability Hub (Dynamic Occupancy, HVAC Setback, Food Rescue)    |
|  - Official ISO 14064 A4 PDF Compliance Audit Generator                           |
+-----------------------------------------------------------------------------------+
```

---

## Key Features & Technological Innovation

### 1. Groq LPU Autonomous Yatri AI Engine (Zero Hardcoding)
- **Real Groq Model Suite:** Connects directly to Groq active models (`openai/gpt-oss-120b`, `groq/compound`) for ultra-low latency sub-second reasoning.
- **Interactive Multi-Turn Dialogue:** Guides travelers through multiple-choice questions (duration: 1-7 days, travel styles: Step-Free Wheelchair, Eco Pilgrim Trek, Budget Explorer, Luxury Heritage).
- **Dynamic Origin Anchoring:** Automatically resolves the traveler's GPS location via native reverse geocoding so that Day 1 transit originates realistically from their current locality.
- **Universal Destination Intelligence:** Generates complete multi-day timelines for any destination globally (Matheran, Kedarnath Dham, Lonavala, Alibaug, Manali, Goa, Jaipur, Tokyo).

### 2. Live Dual-Route Comparison Engine
- **Simultaneous Visualization:** Renders both the Standard Route (Fastest vehicle path, high emissions) and the Green Path (Electric rail, AC e-bus, ferry, or step-free pedestrian transit) side-by-side on an interactive vector map.
- **Accurate Fare Computation:** Implements authentic regional transport formulas (Maharashtra Motor Vehicle Department formula: Base fare Rs 28 + Rs 18.50/km for standard cabs vs. tiered electric public transit).
- **Environmental Grounding:** Integrates live Open-Meteo sensor readings for real-time Air Quality Index (AQI) along travel corridors.

### 3. Dedicated Trips Hub & Carbon Passport
- **Itinerary Management:** Save generated trips to local storage with instant one-tap schedule inspections.
- **Detailed Schedule Viewer:** Comprehensive timeline inspection showing transit segments, check-ins, attractions, and accessibility details.
- **Carbon Rewards:** Accumulate PULSE points for choosing low-emission transit alternatives.

### 4. B2B Hotel Resource & ESG Optimizer
- **Dynamic Occupancy Modeling:** Real-time forecasting of electricity, water consumption, and food surplus diversion based on active room inventory.
- **Automated HVAC Setback:** One-tap temperature setback scheduling for unoccupied wings to avoid unnecessary power consumption.
- **Surplus Food Rescue:** Automated dispatch trigger connecting hotel kitchens with verified food recovery organizations.
- **Official ISO 14064 PDF Generator:** Generates verifiable, cryptographic, A4-sized compliance audit reports ready for SEBI BRSR and LEED Platinum documentation via Android `FileProvider`.

---

## Technical Specifications

| Component | Technology / Implementation |
|---|---|
| **AI Inference** | Groq LPU Cloud (OpenAI GPT-OSS / Groq Compound models) |
| **Mobile Client** | Android SDK 34 (Kotlin, Jetpack Compose, Material 3, Coroutines) |
| **Web Platform** | HTML5, Vanilla ES6 JavaScript, CSS3 Design System, Leaflet.js |
| **Mapping Engine** | TomTom Maps SDK (Android) / Leaflet.js (Web) |
| **Environmental Data** | Open-Meteo Air Quality & Weather API |
| **Document Engine** | Android Native `PdfDocument` + `FileProvider` (A4 Vector PDF) |
| **Persistence** | Room SQLite Database / Encrypted SharedPreferences |

---

## Installation & Setup

### Prerequisites
- Android Studio Hedgehog or newer
- Android SDK 34
- JDK 17
- Physical Android device with USB Debugging enabled or Android Emulator

### Android Build Steps
1. Clone the repository:
   ```bash
   git clone https://github.com/SatyamPandey-07/Urban-Pulse.git
   cd Urban-Pulse/UrbanPulse
   ```
2. Configure Groq API key in `local.properties`:
   ```properties
   GROQ_API_KEY=your_groq_api_key
   TOMTOM_API_KEY=your_tomtom_api_key
   ```
3. Build and install the debug APK:
   ```bash
   ./gradlew assembleDebug
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```

### Running the Web Platform
Serve the root directory with any HTTP server:
```bash
npx serve .
```
Open `http://localhost:3000` in any web browser.

---

## Verification & Deployment
- **Live APK Download:** Available under [GitHub Releases](https://github.com/SatyamPandey-07/Urban-Pulse/releases/tag/v1.0.0-hackcelestial).
- **Demonstration Account:** 1-tap demo login is provided directly on the Welcome and Login screens for instant reviewer evaluation.

---

## License & Team
Developed for **HackCelestial 3.0** by the UrbanPulse Engineering Team.
Licensed under the Apache 2.0 License.
