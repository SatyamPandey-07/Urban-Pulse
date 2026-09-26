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
#   …then edit config.json and fill in GROQ_API_KEY / TOMTOM_API_KEY / GEMINI_API_KEY

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
| `GEMINI_API_KEY` | Second-choice intent parser after Groq | Falls through to the keyword parser |
| `CENTRAL_REGISTRY_BASE_URL` | Shared experiences/bookings/reports backend | On-device SQLite store only |

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
```

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
- **Google Generative AI SDK** — Gemini is now called over its public REST endpoint,
  so no SDK is needed for the one request the app makes.

---

## Migration notes — behaviour that changed, and why

Everything below is a deliberate decision, not an oversight.

**Authentication is local, as it effectively was before.** `AuthManager.kt` wrapped
Firebase Auth, but every screen called it inside a `try { } catch { }` that silently
swallowed failures and then gated navigation on three `SharedPreferences` keys. The
observable behaviour was entirely local, so that is what is ported. Wiring real
Firebase would mean adding `firebase_auth` + `cloud_firestore`, a
`google-services.json` / `GoogleService-Info.plist` per platform, and replacing
`AuthController` with a `Stream<User?>`; nothing else in the app depends on it.

**The Dashboard's AQI and weather are live.** The Kotlin `DashboardFragment` plotted
a fixed seven-value array and showed hardcoded "136" / "28°C" tiles. A
`DashboardViewModel` that fetched the real Open-Meteo figures existed but was never
instantiated by anything. The Flutter dashboard wires that telemetry up for real and shows an explicit empty state when it cannot be read. The
12-hour traffic forecast is still the same static congestion profile — no endpoint in
this project supplies a real per-hour forecast, so it is labelled "typical" rather
than "live".

**SOS resolves a real location.** The Kotlin handler showed a toast claiming the
location had been shared without reading one. The Flutter screen reads the fix first
and reports honestly whether it got one. Actually dispatching to contacts still needs
a backend; `EmergencyContactsManager.kt` stored contacts but nothing sent anything.

**The Web3 wallet button is gone.** `AchievementsActivity` generated a random hex
string, called it a wallet address, and unlocked a badge locally. There was no wallet,
chain or signature behind it. The Achievements screen keeps progression, challenges
and badges.

**Seeded values differ from the Kotlin build.** Both seed their tables procedurally
from a fixed RNG seed, but Dart and Kotlin ship different PRNGs, so individual rows
differ. The relationships they encode (carbon trending down as eco score rises,
weekend occupancy peaks, and so on) are identical, which is what the regression models
and rankers actually depend on.

**PDF section titles lost their emoji.** `package:pdf`'s built-in Helvetica has no
emoji glyphs, where Android's `Canvas` could borrow them from the system font.
Embedding an emoji font would add megabytes to the bundle for decoration.

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
