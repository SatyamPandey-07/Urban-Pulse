# 🚀 HackCelestial 3.0 — Official Presentation Slide Content
**Mahatma Education Society’s PILLAI UNIVERSITY**  
**Event**: HackCelestial 3.0  
**Team Name**: `UntrainedModels`  
**Problem Statement**: `Green & Inclusive Travel — Smart Sustainable and Accessible Hospitality`  
**Project Name**: **UrbanPulse**

---

## 🖥️ SLIDE 1: Title & Pitch Summary

```
====================================================================================================
Mahatma Education Society's PILLAI UNIVERSITY                                   HackCelestial 3.0
====================================================================================================

01. Identification
Team Name: UntrainedModels

02. Focus Area
Problem Statement Title:
Green & Inclusive Travel — Smart Sustainable and Accessible Hospitality

03. Pitch Summary
Abstract:
UrbanPulse is an AI-powered, evidence-grounded travel and hospitality platform designed to make
tourism both environmentally sustainable and universally accessible. It generates personalized,
multimodal itineraries by balancing a traveler’s budget, step-free mobility requirements, sensory
preferences, transit modes, comfort, and carbon sensitivity.

The platform pairs Gemini 1.5 Flash agentic function-calling with TomTom MCP spatial tools,
live Open-Meteo environmental telemetry, and multi-objective Pareto optimization to deliver
provable travel recommendations with zero hardcoded assumptions. Simultaneously, UrbanPulse
empowers hotels and resorts with live facility resource forecasting, automated HVAC eco-scheduling,
surplus food shelter rescue dispatching, and 1-tap verifiable ESG compliance audit sheets.
====================================================================================================
```

---

## 🖥️ SLIDE 2: Proposed Solution

```
====================================================================================================
                                      Proposed Solution
====================================================================================================

[ARCHITECTURE DATAFLOW DIAGRAM]

User Voice / Chat / UI Request
       │
       ▼
LLM Intent Parser (Gemini 1.5 Flash Function Calling)
       │
       ▼
Evidence Matrix (Live GPS + TomTom MCP Tools + Open-Meteo Telemetry)
       │
       ▼
Multi-Objective Pareto Optimizer (Carbon vs Time vs Cost vs Step-Free)
       │
       ├────────────────────────────────────────┬────────────────────────────────────────┐
       ▼                                        ▼                                        ▼
[Traveler Features: Android App]     [Hotel Features: B2B Dashboard]          [Additional Capabilities]
• Simultaneous Dual-Route Canvas     • Live Operations Scale Slider           • Multilingual Voice Input
• Pareto-Optimal Green Corridors     • AI Kitchen Surplus Forecasting         • 1-Tap Demo / Judge Access
• Evidence-Based Accessibility       • Auto-Dispatch to Food Shelters         • SOS & Trauma Geodesic Pinning
• Carbon Wallet & Incentive Ledger   • Signed LEED / BEE ESG Audit Export     • Weather & AQI Health Shield


[RIGHT SUMMARY CARD]
UrbanPulse transforms a traveler's plain-language request into a verified, mathematically
optimized journey. An LLM parses stated preferences (budget, mobility, step-free requirements,
carbon goals) into structured constraints, which are grounded against live TomTom routing and
Open-Meteo environmental sensor data—every accessibility and sustainability metric is backed
by a live API source, not just asserted.

A multi-objective optimizer balances cost, carbon, time, and accessibility to generate Pareto-
optimal trips for travelers, while hotels get a parallel resource dashboard for facility demand
forecasting, HVAC energy optimization, surplus food rescue, and exportable ESG audit compliance.
====================================================================================================
```

---

## 🖥️ SLIDE 3: Flow Chart | Architecture

```
====================================================================================================
                                  Flow Chart | Architecture
====================================================================================================

[HIGH-LEVEL DESIGN (HLD)]                            [BASIC FLOW]

┌──────────────────────────────────────┐            ┌──────────────────────────────────────────────┐
│             Mobile App               │            │           User Enters Trip Request           │
│   Native Kotlin + Material Design 3  │            │     in natural language / voice / chips      │
└──────────────────┬───────────────────┘            └──────────────────────┬───────────────────────┘
                   │                                                       │
┌──────────────────▼───────────────────┐            ┌──────────────────────▼───────────────────────┐
│           ViewModel Layer            │            │        Parse into Structured Constraints     │
│   MVVM + Coroutines + StateFlow      │            │       (Mobility, Carbon, Budget, Time)       │
└──────────────────┬───────────────────┘            └──────────────────────┬───────────────────────┘
                   │                                                       │
┌──────────────────▼───────────────────┐            ┌──────────────────────▼───────────────────────┐
│            Domain Layer              │            │        Fetch Live TomTom & Weather Data      │
│  Intent Parser • Pareto Optimizer    │            │  (Routing API, Traffic Flow, Open-Meteo AQI) │
└──────────────────┬───────────────────┘            └──────────────────────┬───────────────────────┘
                   │                                                       │
┌──────────────────▼───────────────────┐                                   ▼
│             Data Layer               │                         /───────────────────\
│ Live City Service • Offline Matrix   │                        <  Meets Hard         >─── NO ──► [Excluded]
└──────────────────┬───────────────────┘                        <  Constraints?       >
                   │                                             \───────────────────/
┌──────────────────▼───────────────────┐                                   │ YES
│          External Services           │                                   ▼
│ TomTom Maps & MCP • Open-Meteo API   │            ┌──────────────────────────────────────────────┐
│ Google Play FusedLocation Services   │            │             Pareto Optimization              │
└──────────────────────────────────────┘            │        rank & compute tradeoff scores        │
                                                    └──────────────────────┬───────────────────────┘
                                                                           │
                                                    ┌──────────────────────▼───────────────────────┐
                                                    │        Recommended Trip Plans on Map         │
                                                    │  Dual-Route Canvas with "Why this?" HUD      │
                                                    └──────────────────────────────────────────────┘
====================================================================================================
```

---

## 🖥️ SLIDE 4: Innovation and Unique Functionality

```
====================================================================================================
                               Innovation and Unique Functionality
====================================================================================================

┌─────────────────────────────────────────────────┐ ┌─────────────────────────────────────────────────┐
│ Evidence-Based Accessibility                    │ │ Multi-Objective Pareto Optimization             │
│ • Never states "Accessible: Yes" outright;     │ │ • Returns multiple optimal trips (Greenest,     │
│   every claim is verified with physical specs   │ │   100% Step-Free, Fastest, Lowest Cost)         │
│   (level boarding, elevator concourse, tactile).│ │   instead of one single "black-box" choice.     │
│ • Real GPS proximity ranking to local trauma    │ │ • Hard constraints (e.g. wheelchair ramp)       │
│   hospitals (Fortis Mulund, Jupiter Thane).     │ │   eliminate ineligible routes outright.         │
│ • Flags contradictions between listings and     │ │ • Soft preferences (carbon priority, budget)    │
│   physical street infrastructure.               │ │   dynamically shape ranking and route scores.   │
└─────────────────────────────────────────────────┘ └─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐ ┌─────────────────────────────────────────────────┐
│ Explainable Dual-Route Recommendations          │ │ LLM as Reasoner, Not Decision-Maker             │
│ • Renders simultaneous Dual Routes on map:      │ │ • Gemini 1.5 Flash only parses natural intent   │
│   Neon Green Path (#10B981) vs Normal (#EF4444).│ │   into structured constraints with MCP tools.   │
│ • Floating HUD explains exact real-time delta:  │ │ • A deterministic mathematical engine makes     │
│   "-435g CO2 (91% Cleaner) • ₹210 Saved".       │ │   the actual physical carbon & route decisions. │
│ • Turns sustainability from preachy to          │ │ • Keeps the system 100% auditable, transparent, │
│   provable, data-backed savings.                │ │   and immune to LLM hallucination.              │
└─────────────────────────────────────────────────┘ └─────────────────────────────────────────────────┘
====================================================================================================
```

---

## 🖥️ SLIDE 5: Technical Details & Tech Stack

```
====================================================================================================
Technical Details                                                                         Tech Stack
====================================================================================================

Frameworks & Technologies:
• Kotlin 1.9 + Android SDK 34 (Android 14) with Material Design 3 and custom dark theme token system.
• MVVM Architecture with Kotlin Coroutines + StateFlow for reactive, non-blocking asynchronous state.
• TomTom Maps SDK & Routing API: Dynamic polyline canvas, live traffic segment analysis, POI search.
• TomTom Model Context Protocol (MCP): Tool integration for agentic autonomous query resolution.
• Open-Meteo Live APIs: Real-time localized weather telemetry and Air Quality Index (PM2.5, PM10, AQI).
• Google Generative AI SDK: Gemini 1.5 Flash Function Calling for structured grounding.
• Networking: OkHttp 4.12 + Retrofit 2.9 + Gson serialization.

Cost & Scalability Analysis:
• TomTom API: Free tier (~2,500 calls/day) covers hackathon & pilot scale; paid scales at ~$0.50/1k calls.
• Open-Meteo API: 100% free, open-access, zero API key or billing required.
• Gemini 1.5 Flash: Highly optimized token usage via native function calling; free tier sufficient for demo;
  production scaling costs only $0.075 per 1M input tokens.
• Local Processing: Client-side mathematical optimization & caching engine with zero server runtime overhead.
• Google Play Developer Account: One-time $25 registration for global store distribution.
====================================================================================================
```

---

## 🖥️ SLIDE 6: Existing Solutions and Comparison

```
====================================================================================================
                                 Existing Solutions and Comparison
====================================================================================================

┌─────────────────────┬───────────────────────────────────────┬─────────────────────────────────────┐
│ Dimension           │ Existing Solutions (Google Maps / MMT)│ UrbanPulse (Our Solution)           │
├─────────────────────┼───────────────────────────────────────┼─────────────────────────────────────┤
│ Accessibility Info  │ Binary yes/no listing, often          │ Evidence-based audit matrix with    │
│                     │ inaccurate or outdated                │ verified step-free & elevator data  │
├─────────────────────┼───────────────────────────────────────┼─────────────────────────────────────┤
│ Route Visualization │ Single road route, optimized only     │ Simultaneous Dual-Route Canvas      │
│                     │ for vehicle speed                     │ (Green vs Normal) with live HUD     │
├─────────────────────┼───────────────────────────────────────┼─────────────────────────────────────┤
│ Sustainability Data │ Vague "eco-friendly" badges with      │ Transparent live CO2e estimation    │
│                     │ zero data or backing                  │ with visible math & credit ledger   │
├─────────────────────┼───────────────────────────────────────┼─────────────────────────────────────┤
│ Explainability      │ Black-box ranking — no tradeoff       │ "Why this?" HUD + Tradeoff Priority │
│                     │ reasoning shown to user               │ Selector (Carbon/Time/Cost/Access)  │
├─────────────────────┼───────────────────────────────────────┼─────────────────────────────────────┤
│ Personalization     │ Generic filters only — price, star    │ Natural-language intent parsed into │
│                     │ rating, distance                      │ multi-constraint travel personas    │
├─────────────────────┼───────────────────────────────────────┼─────────────────────────────────────┤
│ B2B Hotel Tools &   │ None (hospitality business side is    │ Live occupancy slider, HVAC eco     │
│ ESG Compliance      │ completely ignored)                   │ setpoints & 1-tap signed ESG export │
└─────────────────────┴───────────────────────────────────────┴─────────────────────────────────────┘
====================================================================================================
```

---

## 🖥️ SLIDE 7: Supplementary Information

```
====================================================================================================
                                 Supplementary Information (Optional)
====================================================================================================

┌─────────────────────────────────────────────────┐ ┌─────────────────────────────────────────────────┐
│ 🎬 Live Demo & APK Target                       │ │ 🌐 Live GitHub Repository                       │
│                                                 │ │                                                 │
│ • Production APK: Native Android 8.0+ (API 26+) │ │ URL: https://github.com/SatyamPandey-07/        │
│ • Live Hardware Target: Tested on Vivo V40      │ │      Urban-Pulse                                │
│ • 1-Tap Demo / Judge Access: Instant bypass     │ │                                                 │
│   buttons on Welcome and Login screens for      │ │ Clean architecture, documented commits, and    │
│   zero-friction evaluation during live pitches. │ │ production Gradle build setup.                  │
└─────────────────────────────────────────────────┘ └─────────────────────────────────────────────────┘
====================================================================================================
```
