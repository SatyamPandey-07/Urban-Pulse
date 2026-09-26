# UrbanPulse — Flutter

The Flutter/Dart implementation of UrbanPulse, migrated from the native Android app
in [`../UrbanPulse`](../UrbanPulse). It is the primary mobile client; the Kotlin
project is kept in the repository for reference during the transition, and the
shared **Central Registry** backend in [`../server`](../server) is unchanged and is
still the service both this app and the web app read and write.

---

## Running it

```bash
# 1. From the repository root, start the shared backend (optional but recommended —
#    the app falls back to its on-device store when it is unreachable).
cd server && npm install && npm start      # listens on :3001

# 2. Configure your own API keys. No key is committed to this repository.
cd ../urbanpulse_flutter
cp config.example.json config.json         # config.json is gitignored
#   …then edit config.json and fill in GROQ_API_KEY / TOMTOM_API_KEY

# 3. Run.
flutter pub get
flutter run --dart-define-from-file=config.json
```

Every key is optional. With none configured the app still runs end to end: the AI
assistant falls back to its rule-routed, source-grounded answers, intent parsing
falls back to the deterministic keyword parser, and route comparison falls back to a
haversine estimate — each of which says so in the UI rather than presenting an
estimate as live data.

### Configuration keys

| Key | Used by | Without it |
|---|---|---|
| `GROQ_API_KEY` | Yatri AI chat, agentic trip planner, intent parsing | Grounded fallback answers; itineraries labelled "offline template estimate" |
| `TOMTOM_API_KEY` | Live Map dual routing, POI search, traffic, real route distance | Straight-line route estimate, labelled as such |
| `CENTRAL_REGISTRY_BASE_URL` | Shared experiences/bookings/reports backend | On-device SQLite store only |
| `GROQ_API_KEY_2` … `_4` | Extra Groq keys for the multi-agent planner (agents are spread 2-3 per key) | Agents share `GROQ_API_KEY` |
| `TAVILY_API_KEY` (`_2`, `_3`) | The agents' shared `web_search` / `fetch_page` tools (free: 1,000 credits/month per key) | Falls back to Groq compound search, then Wikipedia / OpenStreetMap |
| `GEOAPIFY_API_KEY` | Hotels and hotspots with coordinates and wheelchair tags (free: ~3,000 credits/day) | OpenStreetMap (Overpass) only, plus AI-estimated details |
| `XOTELO_RAPIDAPI_KEY` | Optional: Xotelo `/search` (city to TripAdvisor location key) | Location key found by other means and validated by distance |

`CENTRAL_REGISTRY_BASE_URL` defaults to `http://10.0.2.2:3001` — the Android
emulator's alias for the host machine's localhost. On a physical device, set it to
your host's LAN IP (e.g. `http://192.168.1.23:3001`).

---

## Architecture

```
lib/
  core/          theme, palette, build-time config, routes, formatting helpers
  models/        plain data classes (no framework dependencies)
  domain/        pure business logic — Pareto/experience/mobility ranking,
                 the Evidence Graph, carbon estimation, OLS regression
  services/      network + platform edges — Groq, TomTom, Open-Meteo, the Central
                 Registry, location, the ESG PDF generator
  repositories/  SQLite- and preference-backed data access
  state/         ChangeNotifier controllers and view models
  screens/       one file per screen, mirroring the original Activities/Fragments
  widgets/       shared UI pieces (cards, charts, chat bubbles, the logo)
  agents/        the Yatri multi-agent trip planner (see below)
```

### Yatri multi-agent planner (`lib/agents/`)

Yatri collects a validated `TripBrief` by chat (phase 1), then a team of agents
plans the trip in parallel while the user watches a live task graph (phase 2).
**Yatri is the only decision-maker**; every other agent is a specialist worker
with tools.

| Agent | Job |
|---|---|
| Yatri | plans, allocates tasks, resolves conflicts, asks the user, finalises |
| Atithi | hotels (live prices, per-need accessibility) |
| Bhatkanti | hotspots, scaled to trip length |
| Hisab | budget engine (deterministic) |
| Khoji | verifies claims, finds reviews and sources |
| Saksham | audits the whole journey for every access need |
| Raah | orders places into days (hours, weather) |
| Safar | transport to and around the destination |
| Hariyali | carbon and eco scoring |

**Built so far:** Yatri, Atithi, Bhatkanti, Safar, Raah and Hisab (stages 2.1 and
2.2). After you confirm the brief, Yatri runs the hotel search (Atithi), the search
for places (Bhatkanti), the journey (Safar) and the weather check (Raah) at the
same time, asking you one question at a time when goals collide ("none of these
are wheelchair accessible", "the cheapest suitable stay is ₹X — raise the
budget?", "classics or newly popular places?", "which way to travel?"). Raah then
groups places into days by geography, opening hours and weather; Hisab prices the
whole plan line by line and, if it is over budget, offers real savings (a cheaper
stay, a cheaper way to travel, skipping paid places). The result is a full
itinerary with a day-by-day map, timeline and budget. Hotels come from Xotelo
(TripAdvisor data and live per-OTA prices), Geoapify, OpenStreetMap and a
`web_search` tool loop; the TripAdvisor location key is validated by distance
so a wrong guess can never put Bengaluru hotels in Munnar. The remaining agents
arrive in later stages.

```
agents/atithi/    hotel search: merge, rank, live rates, listing pages, AI fill
agents/bhatkanti/ places to visit: OSM, Geoapify, Wikipedia, web search, ranking
agents/safar/     journey options (time, cost, CO₂, access per mode) and local legs
agents/raah/      day planner: clustering, opening hours, weather, meals, local legs
agents/hisab/     the budget engine and its levers
agents/yatri/     the orchestrator (Yatri's loop), the gates and the itinerary assembler
domain/access/    OSM tags / listing text -> per-need accessibility support
domain/opening_hours.dart  reads OSM opening_hours text
agents/runtime/   task board (DAG scheduler), task graph model, plan clock,
                  LLM pool + key ring, lenient JSON, tool kit, demo run
agents/tools/     shared web_search / fetch_page tools and the bounded tool-use loop
services/data/    Xotelo, Geoapify, Overpass, Wikipedia, Open-Meteo, AI estimator, cache
models/itinerary/ what the planner produces
widgets/taskgraph/ the live task graph, agent feed and "?" explainers
```

Design rules: real data first, the model fills gaps and is always labelled
"AI-estimated"; every worker can time out, fail or return partial data without
breaking the plan; Groq calls are spread across the configured keys. The Yatri
tab's ⋮ menu has **Preview agent graph (demo)** to see the graph run offline.

State management is Flutter's built-in `ChangeNotifier` + `AnimatedBuilder`, wired
through a single `AppScope` `InheritedWidget` that owns every controller and
repository. This replaces the Kotlin singletons (`GamificationManager`,
`TripPlanManager`, `AccessibilityManager.getInstance`, `AppDatabaseHelper`) with one
composition root — no state-management package needed.

### Screen map

| Flutter screen | Replaces |
|---|---|
| `splash_screen` / `welcome_screen` / `login_screen` / `signup_screen` | `SplashActivity`, `WelcomeActivity`, `LoginActivity`, `SignUpActivity` |
| `home_screen` + `tabs/` | `MainActivity` + `MainPagerAdapter` (5 tabs) |
| `tabs/dashboard_tab` | `DashboardFragment` |
| `tabs/live_map_tab` (+ `live_map_html`) | `LiveMapFragment` |
| `tabs/trips_tab` | `TripsFragment` |
| `tabs/yatri_ai_tab` (+ `state/yatri_ai_controller`) | `YatriAiFragment` |
| `tabs/settings_tab` | `SettingsFragment` |
| `hospitality_screen` | `HospitalityActivity` + `HospitalityAdapter` |
| `green_route_planner_screen` | `GreenRoutePlannerActivity` |
| `itinerary_screen` | `ItineraryActivity` |
| `carbon_wallet_screen` | `CarbonWalletActivity` |
| `hotel_optimizer_screen` | `HotelOptimizerActivity` |
| `trip_detail_screen` | `TripDetailActivity` |
| `achievements_screen` | `AchievementsActivity` + `ChallengesFragment` + `BadgesFragment` |
| `sos_screen` | `SosActivity` |
| `dialogs/add_experience_dialog`, `dialogs/provider_dashboard_dialog` | `dialog_add_experience.xml`, `dialog_provider_dashboard.xml` |

---

## Dependencies, and why each one is here

| Package | Replaces | Why not built-in |
|---|---|---|
| `http` | Retrofit + OkHttp | One HTTP client for Groq, TomTom, Open-Meteo and the registry |
| `shared_preferences` | `android.content.SharedPreferences` | Every persisted preference in the app (session, wallet, trip plan, saved trips, accessibility flags, accent) |
| `sqflite` | `SQLiteOpenHelper` / `AppDatabaseHelper` | The on-device relational store; Flutter ships no SQLite API |
| `geolocator` | `FusedLocationProviderClient` + runtime permissions | Real GPS |
| `geocoding` | `android.location.Geocoder` | Reverse-geocoding the fix to a city name for Yatri AI |
| `webview_flutter` | The `WebView` + Leaflet map | Keeps the original map implementation and its injected-JS contract intact |
| `url_launcher` | `Intent.ACTION_DIAL` | "Call Venue" on a stay |
| `pdf` | `android.graphics.pdf.PdfDocument` | The ISO 14064 ESG audit sheet |
| `printing` | `FileProvider` + `ACTION_VIEW`/`ACTION_SEND` | Opens and shares the generated PDF (one package instead of `path_provider` + an opener + a sharer) |
| `crypto` | `MessageDigest.getInstance("SHA-256")` | The report's content-integrity hash; `dart:*` has no digest |
| `speech_to_text` | `RecognizerIntent.ACTION_RECOGNIZE_SPEECH` | Voice input on the Yatri AI composer |

Deliberately **not** added: any charting library (the two Dashboard charts are
`CustomPainter`s), any state-management package, any UI or animation kit, `intl`
(a ~20-line formatting helper covers `%,d` / `%.1f`), and `go_router` (the
navigation graph is a plain stack).

Dependencies from the Kotlin build with no Flutter counterpart here:

- **MPAndroidChart** — replaced by `CustomPainter` (`widgets/mini_charts.dart`).
- **Coil** — the reachable screens load no network images.
- **Health Connect** — `HealthConnectManager.kt` had no caller.
- **TomTom Search SDK** — search now uses the same TomTom *REST* POI endpoint the rest
  of the app already used. Identical data, one fewer SDK.
- **Firebase Auth / Firestore / Storage** — see the notes below.

---

## Migration notes — behaviour that changed, and why

Everything below is a deliberate decision, not an oversight.

### Nothing on screen is a placeholder

Every figure the UI shows is measured, computed, or persisted. Where a reading
cannot be obtained the screen says so — it never substitutes an invented number.
What was fixed in the Kotlin source and is now real:

| Was hardcoded | Now |
|---|---|
| Header read "Mumbai / Maharashtra, India" | Real reverse-geocoded place from the device fix, with a pending/unavailable state; tap to re-resolve |
| Dashboard AQI "136" and weather "28°C" | Live Open-Meteo readings at the traveler's coordinates |
| AQI chart: seven fixed values, Mon–Sun labels | The real daily averages Open-Meteo returns, labelled with their actual weekdays |
| "12h Traffic Forecast": seven fixed bars | Live TomTom flow at the traveler's corridor, recorded to SQLite and charted as measured history (empty until readings exist) |
| Badges/challenges with frozen progress (`5/10`, `12/50`) | Progress computed from real counters — questions asked, journeys confirmed, reports filed, trips saved, experiences published — plus real lifetime CO2 |
| Carbon Wallet perks + voucher codes `ORCHID-ECO-15` / `TATA-EV-FREE` | Real perks from the Central Registry, with server-issued unique voucher codes and persisted per-traveler redemptions |
| Hotel Optimizer `totalRooms = 120`, facility name, "38.5% Renewable", "85% greywater" | An editable, persisted facility profile; the audit PDF reports what the operator actually declared, and the integrity hash covers it |
| Three fully hand-written `TripPlan` templates in `TripRepository` | Deleted. Quick-plan destinations run the real planner |
| Trips suggestions "83 km • AQI: 28" | Real haversine distance from the traveler's fix and a live AQI reading per destination |
| Live Map: four POI pins and two traffic polylines baked into the HTML | Real TomTom POI search results and the real flow-segment geometry, injected at runtime and coloured by measured congestion |
| Live Map chips routing to fixed lat/lons | Real category searches that route to the nearest actual result |
| Trip Detail: four per-destination transit tables | Computed from the real distance via the same estimator the Green Route Planner uses |
| Agentic planner fallback: three canned itineraries | Computed from a routed distance, the real per-mode fares/durations/emissions, and live AQI at the destination — still labelled an offline estimate, because no model wrote it |
| SOS emergency category cards with no listener | Selectable, and the chosen category is included in the raised alert |
| Settings rows for Units/Language that did nothing | Removed; "Detected Location" shows the real fix and re-resolves on tap |

Two things are deliberately still fixed values, because they are reference data
rather than measurements: the landmark coordinate table in `CarbonEstimator`
(real geographic constants) and the seeded catalogs in `AppDatabase` (reference
rows a production migration would ship, overridden by the Central Registry
whenever it is reachable). Both are documented as such in place.

### Other deltas

**Authentication is local, as it effectively was before.** `AuthManager.kt`
wrapped Firebase Auth, but every screen called it inside a `try { } catch { }`
that silently swallowed failures and then gated navigation on three
`SharedPreferences` keys. The observable behaviour was entirely local, so that is
what is ported. Wiring real Firebase would mean adding `firebase_auth` +
`cloud_firestore`, a `google-services.json` / `GoogleService-Info.plist` per
platform, and replacing `AuthController` with a `Stream<User?>`; nothing else in
the app depends on it.

**The trip planner asks where you are starting from.** It used to assume
"Mumbai". If no GPS place resolves, it now asks for the origin city in the
conversation and plans from the answer.

**SOS resolves a real location.** The Kotlin handler showed a toast claiming the
location had been shared without reading one. The Flutter screen reads the fix
first and reports honestly whether it got one. Actually dispatching to contacts
still needs a backend; `EmergencyContactsManager.kt` stored contacts but nothing
sent anything.

**The Web3 wallet button is gone.** `AchievementsActivity` generated a random hex
string, called it a wallet address, and unlocked a badge locally. There was no
wallet, chain or signature behind it.

**Seeded catalog values differ from the Kotlin build.** Both seed their tables
procedurally from a fixed RNG seed, but Dart and Kotlin ship different PRNGs, so
individual rows differ. The relationships they encode (carbon trending down as
eco score rises, weekend occupancy peaks) are identical, which is what the
regression models and rankers actually depend on.

**PDF section titles lost their emoji.** `package:pdf`'s built-in Helvetica has
no emoji glyphs, where Android's `Canvas` could borrow them from the system font.

### Backend additions

`server/server.js` gained two tables (`perks`, `perk_redemptions`) and three
endpoints, additive and backward compatible with the existing web client:

- `GET /api/perks?travelerName=…` — active perks, with this traveler's voucher if
  they have already redeemed one
- `POST /api/perks/:id/redeem` — issues a unique voucher, idempotent per traveler

### Not migrated: unreachable Android code

A large part of the Kotlin source was unreachable — declared in the manifest but never
started by any `Intent`, and not linked from any screen. Verified by grepping every
reference: `MapActivity`, `YatriAiActivity` (a duplicate of the fragment),
`CommunityActivity`, `IncidentsActivity`, `MedicalActivity`, `LocationPickerActivity`,
`PostDetailActivity`, `ReportIncidentActivity`, `EmergencyContactsActivity`,
`ProfileFragment`, `DigitalTwinFragment`, `MapDemoScreen`, `FirestoreManager`,
`UserLocationManager`, `HealthConnectManager`, plus empty stub classes
(`BentoCard.kt`, `SosAlert.kt`, `HealthStats.kt`, `AchievementAdapter.kt`,
`AirPollutionService.kt`, `AirPollutionResponse.kt`, `AreaAnalyticsService.kt`,
`McpRequest.kt`, `McpResponse.kt`), `TomTomMcpClient` (called only from the
unreachable `YatriAiActivity`), and `YatriAiFragment.buildDynamicTrip` (superseded by
`GroqAgenticEngine`).

They are preserved in `../UrbanPulse` and in git history. Porting any of them means
first deciding what they should do, since none of them were reachable to observe.

---

## Verification

`flutter analyze` is clean. The app has **not** been built or run.
