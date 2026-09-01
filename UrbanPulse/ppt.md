# 📊 HackCelestial 3.0 — Pitch Deck Slide Content
**Mahatma Education Society’s PILLAI UNIVERSITY**  
**Hackathon Challenge**: *HackCelestial 3.0*

---

<!-- SLIDE 1 -->
## 📌 Slide 1: Identification, Focus Area & Pitch Summary

### Header:
- **Institution**: Mahatma Education Society’s PILLAI UNIVERSITY
- **Event**: HackCelestial 3.0
- **Logos**: Pillai University | TechAlegria | Pillai HOC

### 01. Identification:
- **Team Name**: `UntrainedModels`

### 02. Focus Area:
- **Problem Statement Title**:  
  **Green & Inclusive Travel — Smart Sustainable and Accessible Hospitality**

### 03. Pitch Summary:
- **Abstract**:  
  **UrbanPulse** is an AI-powered, evidence-grounded travel and hospitality platform designed to make tourism both sustainable and accessible. It creates personalized itineraries and route plans by considering a traveler’s budget, mobility requirements, step-free preferences, transport modes, comfort, and carbon sensitivity. The platform combines Gemini 1.5 Flash agentic function-calling with TomTom MCP spatial tools, live Open-Meteo environmental telemetry, carbon estimation, and multi-objective Pareto optimization to generate and compare travel options. For hospitality businesses, UrbanPulse provides dynamic facility resource forecasting, automated HVAC eco-scheduling, surplus food rescue dispatch, and 1-tap verifiable ESG audit export sheets.

---

<!-- SLIDE 2 -->
## 📌 Slide 2: Proposed Solution

### Visual Diagram Structure:
```
[User Request: Voice / Chat / UI]
            │
            ▼
[LLM Intent & Preference Parser] ──► [Matched Against Evidence Matrix (GPS + TomTom API)]
            │
            ▼
   [Optimization Engine]
     ┌──────┴──────────────────────────────┐
     ▼                                     ▼
[Traveler B2C App]                [Hotel B2B Dashboard]
 • Dual-Route Map Comparison       • Live Dynamic Facility Slider
 • Pareto-Optimal Green Routes     • AI Kitchen Surplus Forecasting
 • Accessibility Confidence Score  • Auto-Dispatch to Food Shelters
 • Carbon Budget & Passport        • 1-Tap Signed ESG Audit Export
```

### Description:
UrbanPulse turns a traveler's plain-language request into a verified, mathematically optimized journey. A Gemini AI Agent parses stated preferences (budget, mobility, step-free needs, carbon goals) into structured constraints, which are grounded against live TomTom routing and Open-Meteo sensor data—every accessibility and sustainability metric is backed by live API calculations, never hallucinated. A multi-objective optimizer balances cost, carbon emissions, travel time, and step-free access to generate Pareto-optimal options for travelers, while hotels get a parallel resource dashboard for dynamic occupancy scaling, food waste shelter dispatch, and exportable ESG compliance sheets.

---

<!-- SLIDE 3 -->
## 📌 Slide 3: Flow Chart | Architecture

### High-Level Design (HLD):
1. **Presentation Layer**: Native Kotlin Android + Material Design 3 UI, Dark Slate Surface (`#0F172A`), Leaflet Vector Canvas.
2. **ViewModel Layer**: MVVM Architecture with Kotlin Coroutines + StateFlow reactive state management.
3. **Domain Layer**: Intent Parser, Multi-Objective Pareto Optimizer, Carbon Footprint Engine, Evidence-Based Accessibility Ranker.
4. **Data Layer**: Live City Intelligence Service, Local SharedPreferences Passport Ledger, Offline-Resilient Geodesic Fallback Matrix.
5. **External Services**: TomTom Maps & Routing API, TomTom MCP Server, Open-Meteo Air Quality & Weather API, Google Play FusedLocation Services.

### Basic Flow:
```
[User Enters Trip / Hospitality Request]
                 │
                 ▼
[Parse into Structured Constraints (Mobility, Budget, Carbon, Time)]
                 │
                 ▼
[Fetch Live TomTom Routes, Traffic & Open-Meteo AQI Data]
                 │
                 ▼
     <Meets Hard Constraints (e.g. 100% Step-Free)?>
        ├── NO  ──► [Ineligible Route Excluded]
        └── YES ──► [Multi-Objective Pareto Optimization]
                          │
                          ▼
[Render Simultaneous Dual Routes (Green vs Normal) + "Why this?" Explanation]
```

---

<!-- SLIDE 4 -->
## 📌 Slide 4: Innovation and Unique Functionality

### 1. Evidence-Based Accessibility
- Never assumes binary `"Accessible: Yes"`—every transit hub and facility is tagged with verified physical attributes (level boarding, elevator concourses, tactile paths, wheelchair ramps).
- Proximity ranking grounded strictly in real GPS coordinates `(19.1775° N, 72.9544° E)` with live TomTom POI search.
- Flags and eliminates route segments with physical barriers.

### 2. Multi-Objective Pareto Optimization
- Returns multiple optimal choices (**Greenest**, **100% Step-Free**, **Fastest**, **Lowest Cost**) instead of a single arbitrary answer.
- Hard constraints (e.g., wheelchair step-free requirement) eliminate inaccessible paths outright.
- Soft preferences (carbon priority, budget threshold) dynamically shape ranking and visual highlighting.

### 3. Explainable Dual-Route Comparison
- Live map renders **both routes simultaneously**: Glowing Neon Green Corridor (`#10B981`) vs. Standard Congested Path (`#EF4444`).
- Interactive HUD explains exact tradeoffs: **`-435g CO2 (91% Cleaner) • ₹210 Saved • 12 mins Faster`**.
- Turns sustainability from vague marketing into clear, provable numbers.

### 4. LLM as Reasoner, Not Decision-Maker
- Gemini 1.5 Flash is constrained to intent parsing and autonomous function calling with TomTom MCP tools.
- Mathematical carbon emission formulas and geodesic distances govern all recommendations to guarantee zero hallucination.
- Completely auditable and transparent logic.

---

<!-- SLIDE 5 -->
## 📌 Slide 5: Technical Details & Tech Stack

### Frameworks & Technologies:
- **Kotlin + Android SDK 34 (Android 14)**: Native UI with Material Design 3 and custom vector geometry.
- **MVVM Architecture**: Kotlin Coroutines, StateFlow, LiveData for reactive state management.
- **TomTom Maps & Routing API**: Online search, traffic flow segment analysis, and multimodal routing.
- **TomTom Model Context Protocol (MCP)**: Tool integration for agentic autonomous execution.
- **Open-Meteo APIs**: Real-time localized weather telemetry and Air Quality Index (PM2.5, PM10, US AQI).
- **Google Generative AI SDK**: Gemini 1.5 Flash function calling.

### Cost & Scalability:
- **TomTom API**: Free tier (~2,500 requests/day) covers hackathon and pilot scale; commercial tier scales at ~$0.50 per 1,000 requests.
- **Open-Meteo API**: Free, open-access, zero API key required.
- **Gemini 1.5 Flash**: Highly optimized token efficiency with native function calling, free tier sufficient for demo, enterprise scalability at $0.075 / 1M tokens.
- **Hosting & Backend**: Self-contained client-side intelligence engine with zero mandatory server runtime cost during demo.

---

<!-- SLIDE 6 -->
## 📌 Slide 6: Existing Solutions and Comparison

| Feature Dimension | Existing Solutions (Google Maps / MakeMyTrip) | Typical Eco Badge Apps | **UrbanPulse (Our Solution)** |
| :--- | :--- | :--- | :--- |
| **Accessibility Info** | Binary yes/no listing, often outdated and unverified | Self-reported checklists | **Evidence-based audit matrix with verified step-free, tactile, and elevator data** |
| **Route Visualization** | Shows single car/transit route | Text-only recommendations | **Simultaneous Dual-Route Map Canvas (Green Path vs Normal Route) with live HUD** |
| **Sustainability Data** | Vague "eco-friendly" badge or zero data | Generic static carbon charts | **Transparent live $\text{CO}_2\text{e}$ calculation per trip with visible methodology** |
| **Optimization Logic** | Optimizes solely for transit time | Static manual sorting | **Multi-objective Pareto Optimizer (Carbon vs Time vs Budget vs Accessibility)** |
| **B2B Hotel Optimizer** | None | Static surveys | **Dynamic facility occupancy slider, automated HVAC eco setpoint & shelter dispatch** |
| **ESG Audit Compliance** | None | None | **1-Tap verifiable ESG compliance audit sheet export via Android share sheet** |

---

<!-- SLIDE 7 -->
## 📌 Slide 7: Supplementary Information

### 🔗 Project Links:
- **GitHub Repository**: [https://github.com/SatyamPandey-07/Urban-Pulse](https://github.com/SatyamPandey-07/Urban-Pulse)
- **APK Target**: Android 8.0+ (API 26 to 34), tested live on **Vivo V40**
- **1-Tap Demo Access**: Instant Judge / Guest mode built into Welcome and Login screens for immediate evaluation.
