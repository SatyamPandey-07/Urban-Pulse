# 🌿 UrbanPulse

### An accessibility-first, sustainability-first travel companion, with nine AI agents that plan a whole trip while you watch.

<div align="center">

[![Flutter](https://img.shields.io/badge/Flutter-3.41-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.11-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Groq](https://img.shields.io/badge/Groq-gpt--oss--120b%20%C2%B7%20compound-F55036?style=for-the-badge)](https://groq.com)
[![Agents](https://img.shields.io/badge/AI%20agents-9-00B87A?style=for-the-badge)](#-yatri-ai-the-multi-agent-trip-planner)
[![Tests](https://img.shields.io/badge/tests-424%20passing-brightgreen?style=for-the-badge)](#-quality-and-testing)
[![Release](https://img.shields.io/badge/Release-v1.0.0--hackcelestial-00E676?style=for-the-badge&logo=github&logoColor=white)](https://github.com/SatyamPandey-07/Urban-Pulse/releases/tag/v1.0.0-hackcelestial)

**Built for HackCelestial 3.0 (Pillai University) · Track: Local & Experiences**

</div>

---

## Why UrbanPulse

Planning a trip is hard for anyone. It is much harder if you use a wheelchair, are blind or deaf, travel with an elderly parent or a child with sensory needs, or have a tight budget and a conscience about carbon. The information you need is scattered across booking sites, blogs, reviews and maps, and it is rarely honest about the details that matter: *is there a step-free entrance? does the lift actually work? is that price real?*

UrbanPulse does three things about that:

1. **It plans the whole trip for you** (stay, places, journey, days, budget), using a team of specialised AI agents that work in parallel while you watch a live task graph, and that ask you a question only when a choice is genuinely yours.
2. **It never pretends.** Every fact carries its source. Anything a model filled in is labelled *AI-estimated*. Access is "confirmed", "partly" or "unconfirmed", never assumed fine.
3. **It thinks about the whole journey**, for *every* access need in the group (not just wheelchairs) and for the carbon footprint of every choice.

---

## ✨ Yatri AI: the multi-agent trip planner

Yatri is the assistant in the app. It starts as a friendly intake conversation, then hands your confirmed brief to a team of agents.

### 1. The conversation (phase 1)

- Chat-first: type "Family of four from Pune to Munnar, one is in a wheelchair, ₹40,000", or tap through **choice cards**. Yatri prefers options, checkboxes and yes/no over free text.
- One question at a time, mandatory fields first, then a couple of optional ones only if the model thinks they would improve the plan.
- Smart about groups (adults, seniors, children and their ages, women's safety preferences) and about accessibility follow-ups for wheelchair, limited mobility, visual, hearing, elderly care, service animals, sensory or cognitive needs, and other special needs.
- A route map draws itself once origin and destination are known; a review form lets you check everything before planning starts. The whole UI is responsive (phone, tablet, wide screens).

### 2. The agents (phase 2)

**Yatri is the only decision-maker.** Every other agent is a specialist worker: it does its job, reports back with evidence and any problems it can see, and never decides anything for you.

| Agent | Job | How it works |
|---|---|---|
| 🟢 **Yatri** | Plans, allocates tasks, checks reports against gates, resolves conflicts, asks you, assembles the itinerary | Deterministic policy over the workers' reports, so a model outage never stops a plan |
| 🔵 **Atithi** | Finds hotels with live prices and per-need accessibility | Xotelo (TripAdvisor data, live per-OTA totals in ₹, price heatmap), Geoapify, OpenStreetMap, a `web_search` tool loop and TripAdvisor listing pages |
| 🟠 **Bhatkanti** | Finds places worth visiting, about 5 to 6 a day | OpenStreetMap, Geoapify, Wikipedia and web search ("must-see", "new and trending", "local food"), ranked and sized to the trip |
| 🟣 **Hisab** | The budget engine | Deterministic: stay, journey, local travel, entry fees, meals and a buffer, each line marked *live* or *estimate*; offers real savings when over budget |
| 🩷 **Khoji** | Verifies claims and finds guest reviews | `groq/compound` (searches the web itself) first, then Tavily search plus the listing page; brings back 2 to 3 reviews, **lower-rated first**, with source links |
| 🩵 **Saksham** | Audits **every step** of the trip for **every access need** | Rules over map tags, listings, reviews and per-mode profiles; a labelled model reading for gaps, capped at "partly" |
| 🔷 **Raah** | Turns places into practical days | Deterministic: clusters places by geography, reads opening hours, uses the weather forecast, adds meals and local legs |
| 🟡 **Safar** | The journey there and back and local legs | Deterministic: time, cost, CO₂ and access per mode (train, bus, e-bus, shared EV, self-drive EV, cab, flight, metro) |
| 🍃 **Hariyali** | Carbon footprint and eco score | Journey, local travel and stay emissions vs the most polluting comparable choices, plus concrete greener options |

```mermaid
flowchart LR
    U([You: confirmed trip brief]) --> Y{{Yatri}}
    Y --> A[Atithi<br/>hotels]
    Y --> B[Bhatkanti<br/>places]
    Y --> S[Safar<br/>journey]
    Y --> W[Raah<br/>weather]
    A -. delegates .-> K[Khoji<br/>verifies]
    B -. delegates .-> K
    A & B & S & W --> R[Raah<br/>plans the days]
    R --> SK[Saksham<br/>access audit]
    R --> H[Hisab<br/>budget]
    R --> G[Hariyali<br/>carbon]
    SK & H & G --> Y2{{Yatri decides:<br/>fix, re-plan or ask}}
    Y2 -->|problem| R
    Y2 --> I([Itinerary])
```

Watch it happen: the chat shows a **live task graph** (agent-coloured nodes, status glyphs, a "?" on everything explaining *why* an agent did something) and a feed narrating the work ("Yatri allocated the hotel search to Atithi", "Hisab is asking Atithi and Safar for cheaper options"). It expands to a full-screen "mission control" view.

### 3. When Yatri asks you (and only then)

Yatri asks when goals collide, always with concrete options:

- *None of these hotels is confirmed wheelchair accessible. Show the best anyway, or search wider?*
- *The cheapest suitable stay is ₹X a night, above your budget. Raise it, search wider, or keep it?*
- *Classics or newly popular places?*  ·  *Which way to travel* (time, cost, CO₂ and access side by side)?
- *Heavy rain on Saturday with outdoor plans. Move them to drier days?*
- *The plan is ₹Y over budget: a cheaper stay, a cheaper journey, or skip the paid places?*
- *You said the greenest option matters most: the train saves 180 kg CO₂. Switch?*

Minor problems are fixed quietly (an unsuitable minor place is swapped for a better fit, and the feed says so). Questions are asked one at a time, and the time you spend answering is not counted against the 45 to 60 second planning target.

### 4. What you get

A full itinerary screen (also saved to *My Trips* and shareable as a **PDF**):

- **Days**: a map with numbered stops and a timeline (arrival, check-in, visits with opening-hours awareness, meals, local legs with cost and CO₂, access and warning chips)
- **Budget**: the total against your budget, split by category, every line marked live or estimate
- **Access**: an audit of every step for every need, with the source of each reading and a "confirm before you go" list
- **Green**: eco score, footprint breakdown, and greener choices
- **Trip**: the stay (with Khoji's verdicts and review quotes), journey options, a confidence score, everything the plan assumes, every source, and how long each agent worked

### 5. Change your mind: Edit with Yatri (phase 3)

Open any itinerary (from the chat or *My Trips*) and tap **Edit with Yatri**, or tap any stop in the timeline. One agent, still Yatri, turns what you say into a few validated operations; ordinary code then applies them by calling the same engines that made the plan. Nothing is guessed silently: an unclear request gets a question with options.

- **More rest on a day**: "make day 2 relaxed" (a later start, fewer stops; what was displaced moves to a later or emptier day, never dropped quietly) or "day 3 completely free"
- **Replace, add, remove, move, lock**: "swap the museum for something outdoors", "add Eravikulam Park", "do the fort on day 3", "keep the sunrise point where it is"
- **A new hotel**: "wheelchair accessible under ₹3,000": Atithi and Khoji search and check again, and you choose
- **Preferences and logistics**: greener, cheaper, slower pace, another way to travel, one more day (the forecast is fetched again)
- **After every edit** Saksham (access), Hisab (budget), Hariyali (carbon) and the weather check run again, and you are asked, with options, if a change makes something collide
- Every change shows a **diff** (what moved, cost, CO₂, access) with **Undo / Redo**; a plan is replaced only when the whole edit succeeds, and the saved trip keeps its version and edit history

Without a model key the common phrases and the quick chips still work (a rule-based reader), and text that tries to instruct the agent is only ever treated as a request.

---

## 📦 Object (JSON) Contracts & Data Schemas

UrbanPulse is built around typed, validated JSON contracts that govern the hand-off between conversational intake, autonomous specialist swarms, and final itinerary rendering.

### 1. Initial Trip Detail Object (`TripBrief` JSON Schema)

The `TripBrief` is the structured hand-off contract produced by the **Receptionist Agent (Phase 1)** once the traveler has stated and reviewed their trip requirements. Every downstream specialist agent reads from this immutable contract.

#### TypeScript / JSON Interface Definition

```typescript
interface TripBrief {
  id: string;                                 // Unique brief identifier (e.g. "brief_1727391456000")
  createdAt: string;                          // ISO 8601 creation timestamp
  destination: string | null;                 // Destination city or region
  originCity: string | null;                  // Departure / starting city
  start: string | null;                       // ISO 8601 trip start date-time
  end: string | null;                         // ISO 8601 trip end date-time
  
  // Group Composition
  travellerCount: number | null;              // Total number of travellers
  adults: number | null;                      // Adults (ages 18-59)
  seniors: number | null;                     // Seniors (ages 60+)
  children: number | null;                    // Children (under 18)
  women: number | null;                       // Women travellers count
  childAges: number[];                        // Specific child ages (e.g. [5, 11])
  
  // Budget (Whole-trip for entire group in INR)
  budgetMinInr: number | null;                // Lower budget bound in ₹
  budgetMaxInr: number | null;                // Upper budget bound in ₹
  
  // Modes & Preferences (Enums)
  transportModes: TripTransportMode[];        // Acceptable transit options
  accessibilityNeeds: AccessibilityNeed[];    // Specific physical / sensory requirements
  accessibilityConfirmed: boolean;            // Whether traveler explicitly confirmed needs
  accessibilityDetails: Record<string, string[]>; // Sub-option answers (e.g. {"a11y.stairs": ["avoid_steep_climbs"]})
  womenSafety: WomenSafetyPref[];             // Dedicated safety requirements
  style: TripStyle | null;                    // Thematic style of trip
  pace: TripPace | null;                      // Schedule density & touring speed
  stayTypes: StayType[];                      // Preferred accommodation types
  dietary: Dietary[];                         // Food restrictions and preferences
  sustainability: SustainabilityPriority;     // Carbon vs Convenience weighting
  
  notes: string | null;                       // Freeform special instructions
  uncertain: BriefField[];                    // Fields requiring follow-up user clarification
}

// Canonical Enumerations
type TripTransportMode = "train" | "metroLocal" | "eBus" | "bus" | "sharedEv" | "selfDriveEv" | "carTaxi" | "flight";
type AccessibilityNeed = "wheelchair" | "limitedMobility" | "visual" | "hearing" | "elderlyCare" | "serviceAnimal" | "cognitiveSensory" | "otherSpecial" | "none";
type WomenSafetyPref = "womenOnlyTransport" | "verifiedStays" | "avoidLateNightTransit" | "sharedLiveLocation" | "none";
type TripStyle = "leisure" | "family" | "pilgrimage" | "adventure" | "heritage" | "nature" | "workation";
type TripPace = "relaxed" | "balanced" | "packed";
type StayType = "ecoStay" | "homestay" | "hotel" | "hostel" | "resort";
type Dietary = "veg" | "vegan" | "jain" | "halal" | "noPreference";
type SustainabilityPriority = "greenest" | "balanced" | "convenience";
type BriefField = "destination" | "origin" | "dates" | "travellers" | "group" | "womenSafety" | "accessibility" | "transport" | "budget" | "style" | "pace" | "stay" | "dietary" | "sustainability" | "notes";
```

#### Annotated Real-World `TripBrief` JSON Example

```json
{
  "id": "brief_1727391456000",
  "createdAt": "2026-09-27T09:00:00.000Z",
  "destination": "Rishikesh",
  "originCity": "Panvel",
  "start": "2026-10-15T09:00:00.000Z",
  "end": "2026-10-18T18:00:00.000Z",
  "travellerCount": 2,
  "adults": 1,
  "seniors": 1,
  "children": 0,
  "women": 1,
  "childAges": [],
  "budgetMinInr": 25000,
  "budgetMaxInr": 50000,
  "transportModes": [
    "train",
    "eBus",
    "sharedEv"
  ],
  "accessibilityNeeds": [
    "elderlyCare",
    "limitedMobility"
  ],
  "accessibilityConfirmed": true,
  "accessibilityDetails": {
    "a11y.stairs": ["avoid_steep_climbs"],
    "a11y.vehicle": ["low_floor"]
  },
  "womenSafety": [
    "verifiedStays",
    "womenOnlyTransport",
    "avoidLateNightTransit"
  ],
  "style": "nature",
  "pace": "relaxed",
  "stayTypes": [
    "ecoStay",
    "resort"
  ],
  "dietary": [
    "veg"
  ],
  "sustainability": "greenest",
  "notes": "Looking for peaceful ghats, meditation sights, and serene viewpoints without steep climbs.",
  "uncertain": []
}
```

---

### 2. Final Trip Plan Object (`Itinerary` JSON Schema)

The `Itinerary` is the comprehensive multi-agent synthesis object containing timeline days, slot breakdowns, itemized budget ledgers, carbon benchmarks, source provenance, and universal accessibility audits.

#### TypeScript / JSON Interface Definition

```typescript
interface Itinerary {
  id: string;                                 // Itinerary identifier (e.g. "itin_rishikesh_98241")
  createdAt: string;                          // ISO 8601 generation timestamp
  destination: string;                        // Destination name
  origin: string;                             // Origin city / departure point
  start: string;                              // ISO 8601 trip start date-time
  end: string;                                // ISO 8601 trip end date-time
  travellerSummary: string;                   // E.g., "2 travellers · 1 adult, 1 senior"
  
  // Stays & Transport
  hotel: HotelOption | null;                  // Chosen accommodation
  hotelAlternatives: HotelOption[];           // Evaluated alternatives
  transportOptions: TransportLeg[];           // Intercity transit options evaluated
  chosenTransport: TransportLeg | null;       // Selected journey option
  
  // Day-by-Day Timeline
  days: ItineraryDay[];                       // Structured timeline days
  
  // Multi-Agent Audits
  budget: Budget;                             // Itemized financial ledger
  audit: AccessibilityAudit | null;           // Saksham accessibility audit
  green: GreenReport | null;                  // Hariyali emissions & eco score report
  sources: SourceRef[];                       // Citations and provenance of real data consulted
  assumptions: string[];                      // Disclosures of any estimations made
  confidence: number;                         // 0.0 to 1.0 confidence score
  brief: TripBrief | null;                    // Original brief
}

interface ItineraryDay {
  number: number;                             // Day 1, 2, 3...
  date: string;                               // ISO 8601 date (YYYY-MM-DD)
  title: string;                              // Day headline
  weather: string | null;                     // E.g. "25°C · Sunny & Crisp"
  slots: ItinerarySlot[];                     // Chronological slots
}

interface ItinerarySlot {
  kind: "stay" | "visit" | "meal" | "transit" | "rest";
  start: string;                              // ISO 8601 slot start time
  end: string;                                // ISO 8601 slot end time
  title: string;                              // Activity / attraction / step title
  location: { latitude: number; longitude: number } | null;
  refId: string | null;                       // ID of hotel or hotspot
  note: string | null;                        // Practical context / tips
  costInr: number | null;                     // Admission or service fee
  leg: TransportLeg | null;                   // If transit, leg metrics
  access: "yes" | "partial" | "no" | "unknown" | null; // Saksham accessibility rating
  flags: string[];                            // Short badges (e.g. "Ramp access confirmed")
}

interface Budget {
  lines: BudgetLine[];                        // Itemized expenditure lines
  budgetMinInr: number | null;
  budgetMaxInr: number | null;
  totalInr: number;                           // Total computed spend in ₹
  remainingInr: number | null;                // Remaining budget headroom
  isWithinBudget: boolean;
  hasEstimates: boolean;
}

interface BudgetLine {
  label: string;                              // E.g., "3 nights at Ganga Kinare Eco Hotel"
  amountInr: number;                          // Cost in ₹
  category: "stay" | "transport" | "activities" | "food" | "buffer";
  isEstimated: boolean;                       // True if estimated by model, false if live quote
}

interface GreenReport {
  co2Kg: number;                              // Total trip emissions in kg CO₂
  co2SavedKg: number;                         // kg CO₂ saved vs high-carbon baseline
  score: number;                              // Eco score (0 to 100)
  tips: string[];                             // Tailored sustainability suggestions
}
```

#### Annotated Real-World `Itinerary` JSON Example

```json
{
  "id": "itin_rishikesh_98241",
  "createdAt": "2026-09-27T09:05:30.000Z",
  "destination": "Rishikesh",
  "origin": "Panvel",
  "start": "2026-10-15T09:00:00.000Z",
  "end": "2026-10-18T18:00:00.000Z",
  "travellerSummary": "2 travellers · 1 adult, 1 senior (Elderly care, step-free preference)",
  "hotel": {
    "id": "stay_ganga_kinare_01",
    "name": "Ganga Kinare — A Riverside Boutique Eco Hotel",
    "location": { "latitude": 30.1084, "longitude": 78.2917 },
    "pricePerNightInr": 6200,
    "rating": 4.6,
    "sustainabilityScore": 92,
    "amenities": ["Elevator", "Ramp Access", "Organic Dining", "Solar Water Heating"],
    "access": {
      "elderlyCare": { "level": "yes", "reason": "Ground-floor suites, elevator to all levels, wheelchair on site" },
      "limitedMobility": { "level": "yes", "reason": "Direct riverfront deck without steep stairwells" }
    }
  },
  "hotelAlternatives": [
    {
      "id": "stay_ananda_resort_02",
      "name": "Aloha On The Ganges",
      "location": { "latitude": 30.1345, "longitude": 78.3241 },
      "pricePerNightInr": 7800,
      "rating": 4.5,
      "sustainabilityScore": 88
    }
  ],
  "chosenTransport": {
    "mode": "train",
    "from": "Panvel Junction (PNVL)",
    "to": "Yog Nagari Rishikesh (YNRK)",
    "durationMin": 1420,
    "distanceKm": 1640,
    "costInr": 3540,
    "co2Grams": 45920,
    "walking": false,
    "note": "Express AC 2-Tier with step-free station assistance and confirmed lower berths."
  },
  "days": [
    {
      "number": 1,
      "date": "2026-10-15T00:00:00.000Z",
      "title": "Arrive in Rishikesh · Riverside Check-in & Evening Aarti",
      "weather": "25°C · Pleasant & Clear",
      "slots": [
        {
          "kind": "transit",
          "start": "2026-10-15T09:00:00.000Z",
          "end": "2026-10-15T13:40:00.000Z",
          "title": "Arrive at Yog Nagari Rishikesh via Eco Express Rail",
          "location": { "latitude": 30.0891, "longitude": 78.2882 },
          "costInr": 3540,
          "access": "yes",
          "note": "Station porter and low-floor EV cab transfer to hotel.",
          "flags": ["Step-free assistance booked"]
        },
        {
          "kind": "stay",
          "start": "2026-10-15T14:00:00.000Z",
          "end": "2026-10-15T15:30:00.000Z",
          "title": "Check in at Ganga Kinare Boutique Hotel",
          "location": { "latitude": 30.1084, "longitude": 78.2917 },
          "note": "Settle into accessible ground-floor river view suite and rest.",
          "access": "yes",
          "flags": []
        },
        {
          "kind": "visit",
          "start": "2026-10-15T17:15:00.000Z",
          "end": "2026-10-15T19:00:00.000Z",
          "title": "Triveni Ghat & Evening Ganga Aarti",
          "location": { "latitude": 30.1058, "longitude": 78.2971 },
          "refId": "spot_triveni_ghat",
          "note": "Reserved seating near the ramp platform for elderly comfort; watch the sacred floating diyas.",
          "costInr": 0,
          "access": "yes",
          "flags": ["Ramp access confirmed"]
        },
        {
          "kind": "meal",
          "start": "2026-10-15T19:30:00.000Z",
          "end": "2026-10-15T20:45:00.000Z",
          "title": "Dinner at Chotiwala Heritage Restaurant",
          "location": { "latitude": 30.1245, "longitude": 78.3150 },
          "note": "Wholesome satvik Garhwali thali with mild spices.",
          "costInr": 750,
          "access": "yes",
          "flags": []
        }
      ]
    },
    {
      "number": 2,
      "date": "2026-10-16T00:00:00.000Z",
      "title": "Heritage & Serenity · The Beatles Ashram & River Overlooks",
      "weather": "26°C · Sunny & Crisp",
      "slots": [
        {
          "kind": "visit",
          "start": "2026-10-16T09:30:00.000Z",
          "end": "2026-10-16T12:00:00.000Z",
          "title": "The Beatles Ashram (Chaurasi Kutia)",
          "location": { "latitude": 30.1132, "longitude": 78.3125 },
          "refId": "spot_beatles_ashram",
          "note": "Gentle nature paths through forested heritage ruins and colorful meditation dome art.",
          "costInr": 300,
          "access": "yes",
          "flags": ["Shaded paths"]
        },
        {
          "kind": "meal",
          "start": "2026-10-16T12:30:00.000Z",
          "end": "2026-10-16T14:00:00.000Z",
          "title": "Lunch at Little Buddha Cafe & River Overlook",
          "location": { "latitude": 30.1278, "longitude": 78.3204 },
          "note": "Wood-fired meals, herbal teas, and soothing views of the Ganges.",
          "costInr": 850,
          "access": "partial",
          "flags": []
        },
        {
          "kind": "visit",
          "start": "2026-10-16T15:30:00.000Z",
          "end": "2026-10-16T17:30:00.000Z",
          "title": "Parmarth Niketan Ashram & Gardens",
          "location": { "latitude": 30.1190, "longitude": 78.3160 },
          "refId": "spot_parmarth_niketan",
          "note": "Step-free floral courtyards, sacred banyan trees, and tranquil evening music.",
          "costInr": 0,
          "access": "yes",
          "flags": ["Step-free verified"]
        }
      ]
    },
    {
      "number": 3,
      "date": "2026-10-17T00:00:00.000Z",
      "title": "Spiritual Vistas · Ram Jhula & Local Craft Trail",
      "weather": "24°C · Clear Sky",
      "slots": [
        {
          "kind": "visit",
          "start": "2026-10-17T10:00:00.000Z",
          "end": "2026-10-17T12:00:00.000Z",
          "title": "Ram Jhula & Swarg Ashram Trail",
          "location": { "latitude": 30.1221, "longitude": 78.3175 },
          "refId": "spot_ram_jhula",
          "note": "Pedestrian suspension bridge with panoramic river vistas and authentic Ayurvedic shops.",
          "costInr": 0,
          "access": "yes",
          "flags": ["Flat pedestrian zone"]
        },
        {
          "kind": "visit",
          "start": "2026-10-17T14:30:00.000Z",
          "end": "2026-10-17T16:00:00.000Z",
          "title": "Tera Manzil Temple (Trimbakeshwar)",
          "location": { "latitude": 30.1305, "longitude": 78.3280 },
          "refId": "spot_tera_manzil",
          "note": "Riverside sacred complex overlooking Lakshman Jhula area.",
          "costInr": 0,
          "access": "partial",
          "flags": []
        }
      ]
    },
    {
      "number": 4,
      "date": "2026-10-18T00:00:00.000Z",
      "title": "Departure · Scenic Farewell & Return Transit",
      "weather": "25°C · Clear Sky",
      "slots": [
        {
          "kind": "stay",
          "start": "2026-10-18T10:00:00.000Z",
          "end": "2026-10-18T10:45:00.000Z",
          "title": "Check out of Ganga Kinare Hotel",
          "location": { "latitude": 30.1084, "longitude": 78.2917 },
          "note": "Baggage assistance to departure cab.",
          "access": "yes",
          "flags": []
        },
        {
          "kind": "transit",
          "start": "2026-10-18T11:30:00.000Z",
          "end": "2026-10-18T18:00:00.000Z",
          "title": "Return Journey to Panvel via Train",
          "location": { "latitude": 18.9894, "longitude": 73.1175 },
          "costInr": 3540,
          "access": "yes",
          "flags": []
        }
      ]
    }
  ],
  "budget": {
    "lines": [
      { "label": "3 nights at Ganga Kinare Eco Hotel", "amountInr": 18600, "category": "stay", "isEstimated": false },
      { "label": "Round-trip Train (Panvel ⇄ Rishikesh AC 2-Tier)", "amountInr": 7080, "category": "transport", "isEstimated": false },
      { "label": "Local transfers & EV cab services", "amountInr": 2400, "category": "transport", "isEstimated": true },
      { "label": "Attractions admission & heritage entry", "amountInr": 600, "category": "activities", "isEstimated": false },
      { "label": "Dining & traditional meals", "amountInr": 5200, "category": "food", "isEstimated": true },
      { "label": "Contingency & accessibility assistance buffer", "amountInr": 2500, "category": "buffer", "isEstimated": false }
    ],
    "budgetMinInr": 25000,
    "budgetMaxInr": 50000,
    "totalInr": 36380,
    "remainingInr": 13620,
    "isWithinBudget": true,
    "hasEstimates": true
  },
  "audit": {
    "items": [
      {
        "name": "Ganga Kinare — A Riverside Boutique Eco Hotel",
        "kind": "stay",
        "checks": [
          { "need": "elderlyCare", "level": "yes", "reason": "Ground floor suites, elevators, and step-free access." },
          { "need": "limitedMobility", "level": "yes", "reason": "Ramped riverside veranda." }
        ],
        "action": "keep"
      },
      {
        "name": "Triveni Ghat Evening Aarti",
        "kind": "visit",
        "checks": [
          { "need": "elderlyCare", "level": "yes", "reason": "Wheelchair accessible ramp to dedicated viewing platform." }
        ],
        "action": "keep"
      }
    ],
    "actionsRequired": []
  },
  "green": {
    "co2Kg": 91.8,
    "co2SavedKg": 420.4,
    "score": 89,
    "tips": [
      "Choosing electric rail over flights or petrol cars cut your group's footprint by over 420 kg CO₂.",
      "Staying at an eco-certified hotel saved an estimated 18 kWh of grid electricity each day."
    ]
  },
  "sources": [
    { "title": "The Beatles Ashram", "url": "https://en.wikipedia.org/wiki/Beatles_Ashram", "source": "Curated Guide" },
    { "title": "Triveni Ghat", "url": "https://en.wikipedia.org/wiki/Triveni_Ghat", "source": "Curated Guide" },
    { "title": "Open-Meteo Weather Model", "url": "https://open-meteo.com", "source": "Raah Weather" }
  ],
  "assumptions": [
    "Local meal costs are budgeted at approximately ₹650 per person per day.",
    "Indian Railways AC 2-Tier ticket costs assume standard dynamic Tatkal / General quota pricing."
  ],
  "confidence": 0.94
}
```

---

### 3. Trips Dashboard Flat Object (`TripPlan` Schema)

For instant rendering on the mobile **Trips Tab** and local SQLite persistence, `Itinerary.toTripPlan()` projects the rich multi-agent structure into the lightweight `TripPlan` model:

```typescript
interface TripPlan {
  id: string;
  destination: string;
  title: string;                               // E.g., "Rishikesh — 4-day trip"
  durationDays: number;
  travelDates: string;                         // E.g., "15 Oct – 18 Oct 2026"
  travelMode: string;                          // E.g., "Train"
  co2SavedKg: number;                          // 420.4
  pulsePointsEarned: number;                   // CO2 savings converted to gamified rewards
  isCompleted: boolean;
  hotelName: string;                           // "Ganga Kinare — A Riverside Boutique Eco Hotel"
  hotelRating: number;                         // 4.6
  isStepFreeAccessible: boolean;               // Verified by Saksham audit
  totalBudgetInr: number;                      // 36380
  aqiStatus: string;                           // Telemetry readout
  transitCostInr: number;                      // 7080
  dailyItinerary: TripDaySchedule[];
  transitOpt1Name?: string;
  transitOpt1Metrics?: string;
  source: "multi_agent";
}
```

---

### 5. Built not to break

Judges, and travellers, type strange things and networks fail.

- **Real data first; the model only fills gaps, and says so.** No city or trip is hardcoded. The TripAdvisor destination key is validated by distance so a wrong guess can never put Bengaluru hotels in Munnar.
- **Every worker can time out, fail or return partial data** without breaking the plan. Yatri routes around it and tells you.
- **Sanitised input** (control characters, length), **safe links** (only http/https), **offline detection** (an offline estimate, never "unknown place"), **cancellation** (restart the chat and a running plan stops and can never write into the new one).
- **Chaos-tested**: the whole pipeline is run against hostile destinations (emoji, SQL, HTML, prompt injection, a 10,000-character name), random service outages, garbage model replies and random answers.
- **Free-tier friendly**: a per-plan credit budget for paid searches, aggressive caching, shared request de-duplication, and a spread of Groq calls across several keys.
- **Persistent In-App API Key Overrides**: Switch or test Groq, Tavily, Geoapify, Xotelo RapidAPI, or TomTom keys at runtime directly inside **Settings → API Key & Provider Overrides** without recompiling.

---

## 🧭 The rest of the app

The original UrbanPulse experience is still here, now in Flutter:

| Area | What it does |
|---|---|
| **Local discovery** | Pareto-ranked local experiences that balance carbon, accessibility and price, a 2-hour micro-experience filter near your live location, and one-tap adaptation to rain or delays |
| **Evidence-based accessibility** | Every accessibility and sustainability claim is tagged *Verified / Reported / Inferred*; traveller confirmations and "report an issue" feed it as an independent second source |
| **Live map** | Dual-route comparison (green transit corridor vs petrol cab) with live TomTom routing, CO₂ avoided and a live AQI readout |
| **Provider hub** | Local artisans and guides list experiences, toggle availability and see real demand |
| **Hospitality & ESG** | A B2B tool that forecasts resource use for hotels and exports an ISO 14064-style A4 audit PDF with computed pass/fail and a content hash |
| **Wallet, achievements, SOS** | Carbon wallet, badges and challenges, and an emergency screen |
| **Central Registry** | A small Express + SQLite backend (`server/`) shared by the app and the web app: listings, bookings and traveller reports; the app keeps working offline with a local store |

There is also a **web platform** (`index.html`, `app.js`, Leaflet) that talks to the same registry.

---

## 🏗️ Architecture

```
urbanpulse_flutter/lib/
  core/          theme, palette, build-time config, routes, safe link opening
  models/        plain data classes: trip brief, questions, itinerary (JSON round-trip)
  domain/        pure logic: brief validation, question planning, accessibility rules,
                 opening hours, Pareto ranking, evidence graph, carbon estimation
  services/      network edges: Groq, TomTom, Open-Meteo, Xotelo, Geoapify, Overpass,
                 Wikipedia, the registry, PDF generation
  repositories/  SQLite and preference-backed storage (trips, briefs, itineraries)
  state/         ChangeNotifier controllers (the Yatri controller runs the conversation
                 and the planner)
  agents/
    runtime/     task board (DAG scheduler), live task graph model, plan clock,
                 Groq key ring, lenient JSON, toolkit
    tools/       shared web_search / fetch_page tools + bounded tool-use loop
    receptionist/  the intake agent (phase 1)
    yatri/ atithi/ bhatkanti/ hisab/ khoji/ saksham/ raah/ safar/ hariyali/
  screens/ widgets/  UI: chat, choice cards, task graph, itinerary screen
```

Design rules that hold everywhere:

- **Deterministic core, model at the edges.** Budget, routing, scheduling, gates and carbon are plain code with table-style tests; models extract, rank, estimate and verify, and their output is validated.
- **Provenance on everything.** Values carry where they came from; estimates are always marked.
- **State management** is Flutter's built-in `ChangeNotifier` through one `AppScope`. No state package.

### Data sources

| Source | Used for | Key needed |
|---|---|---|
| [Groq](https://groq.com) (`gpt-oss-120b`, `gpt-oss-20b`, `groq/compound`) | Conversation, agent reasoning, verification with built-in web search | `GROQ_API_KEY` (extra keys optional) |
| [Tavily](https://tavily.com) | The agents' shared web search and page extraction | `TAVILY_API_KEY` (optional) |
| [Geoapify](https://www.geoapify.com) | Hotels and attractions with coordinates and wheelchair tags | `GEOAPIFY_API_KEY` (optional) |
| [Xotelo](https://xotelo.com) | TripAdvisor hotel lists, live per-OTA prices, price heatmap | None (search endpoint optional via RapidAPI) |
| OpenStreetMap (Overpass) | Places, opening hours, access tags | None |
| Wikipedia | Notability and short descriptions | None |
| [Open-Meteo](https://open-meteo.com) | Forecast, seasonal weather history, geocoding, air quality | None |
| [TomTom](https://developer.tomtom.com) | Live map routing, traffic (existing tabs) | `TOMTOM_API_KEY` (optional) |

---

## 🚀 Getting started

### Prerequisites

- Flutter 3.41+ (Dart 3.11)
- Android SDK and a device or emulator (the project is developed against Android; other platforms are generated but less tested)
- Node.js 18+ (only for the shared registry backend and the web app)

### Configure your keys

No key is committed. Copy the example and fill in your own:

```bash
cd urbanpulse_flutter
cp config.example.json config.json      # gitignored
```

| Key | Needed? | What it powers |
|---|---|---|
| `GROQ_API_KEY` | **Yes** for Yatri | Conversation, agents, Khoji's web-search verification |
| `TAVILY_API_KEY` | Recommended | Web search for hotels, places, reviews |
| `GEOAPIFY_API_KEY` | Recommended | Hotels and places with coordinates and wheelchair tags |
| `GROQ_API_KEY_2` … `_4` | Optional | Extra keys so parallel agents do not share one rate limit |
| `TAVILY_API_KEY_2`, `_3` | Optional | More search credits |
| `XOTELO_RAPIDAPI_KEY` | Optional | City to TripAdvisor key lookup (everything else in Xotelo needs no key) |
| `TOMTOM_API_KEY` | Optional | The live map and traffic tabs |
| `CENTRAL_REGISTRY_BASE_URL` | Optional | The shared backend (use your PC's LAN IP on a real phone) |

Keys are baked in at build time, so add them **before** building. Every key is optional in the sense that the app still runs: without a Groq key the Yatri chat is disabled, and without the search keys the planner falls back to OpenStreetMap, Wikipedia and clearly labelled estimates.

### Run on a phone in debug mode (one command)

```bash
./run.sh            # first USB-connected phone; hot reload with r, restart with R
./run.sh <device>   # pick a device from `adb devices`
```

Or by hand:

```bash
cd urbanpulse_flutter
flutter pub get
flutter run --dart-define-from-file=config.json
```

### Optional: the shared backend and the web app

```bash
cd server && npm install && npm start      # http://localhost:3001
# web app: copy config.local.example.js to config.local.js, add keys, then
npx serve .                                 # http://localhost:3000
```

### Try the planner without keys

Open the **Yatri AI** tab, tap ⋮ and choose **Preview agent graph (demo)** to watch the full agent graph run offline with scripted data.

---

## ✅ Quality and testing

```bash
cd urbanpulse_flutter
flutter analyze
flutter test        # 485 tests
```

The suite includes table-driven tests for the deterministic engines (validation, question planning, accessibility rules, opening hours, day planning, budgets, gates), orchestration tests with scripted model and service replies, widget tests for the chat, hotel cards, task graph and itinerary screen at phone, tablet and desktop sizes in light and dark, and **chaos tests** that run the whole planning pipeline, and 60 random edits in a row, against hostile inputs and random failures. Live runs of the editor against the real services: `flutter test test/live/edit_trace_test.dart --dart-define-from-file=config.json`.

CI (`.github/workflows/flutter-ci-cd.yml`) builds the Android APK on pushes to `main`.

### An honest status note

Everything above is verified with tests, mocks and a debug build. The planner has **not yet been run end to end against live Groq, Tavily and Geoapify or measured against its 45 to 60 second target on a device**; that is the next thing to do once keys are in. Prices and times shown as estimates are estimates, and the app says so.

---

## 📂 Repository map

| Path | What is in it |
|---|---|
| [`urbanpulse_flutter/`](urbanpulse_flutter) | The Flutter app (primary client). Its [README](urbanpulse_flutter/README.md) has the screen map and dependency notes |
| [`server/`](server) | The Central Registry backend (Express + SQLite) |
| `index.html`, `app.js`, `style.css` | The web platform |
| [`FEATURES.md`](FEATURES.md) | Additional implemented features (e.g. the real-time impact dashboard) |
| [`ppt.md`](ppt.md) | The hackathon pitch deck outline |
| [`release/`](release) | The v1.0.0 Android APK |
| `run.sh` | One-command debug run on a USB phone |

---

<div align="center">
  <sub>Made for HackCelestial 3.0 · <a href="https://github.com/SatyamPandey-07/Urban-Pulse">github.com/SatyamPandey-07/Urban-Pulse</a></sub>
</div>
