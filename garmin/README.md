# Urban Pulse — Connect IQ app for the Forerunner 965

The itinerary the Yatri planner builds on the phone, on your wrist: what is
happening now, what is next and how far away it is, the whole day as a timeline,
and the trip against its budget.

It is a Connect IQ **device app** (`watch-app`) written in Monkey C, targeting
`fr965` (API level 5.2, 454 × 454 round AMOLED, 786,432 bytes of RAM).

## How the plan gets to the watch

The moment the multi-agent planner finishes an itinerary, the phone app publishes
a watch-sized copy of it to the Urban Pulse registry — the same `server/` the
rest of the app already uses. The watch pulls it from there.

```
Yatri agents finish
   │  YatriController.onItineraryReady
   ▼
WatchSyncService.publish()          lib/services/watch_sync_service.dart
   │  buildWatchPayload()           lib/services/watch_payload.dart
   │  PUT /api/watch/<code>
   ▼
Urban Pulse registry                server/server.js  (table: watch_trips)
   │  GET /api/watch/<code>?since=<u>
   ▼
TripClient ──► TripStore ──► PulseView
```

**There is no companion-app channel, on purpose.** Nothing platform-specific is
needed on either side, the watch works with the phone locked or out of range, and
a replanned trip reaches the watch without the traveller doing anything.

Pairing is one code, entered once: the phone shows it under **Settings → Garmin
Watch**, you type it into the watch app's settings in Garmin Connect.

### The payload

Deliberately tiny and pre-chewed, because a watch has kilobytes to spend on a
response and one text font. Short keys, ASCII only, wall-clock times already
rendered — the watch does no date arithmetic beyond comparing epoch seconds.

```json
{ "v":1, "t":"Rishikesh", "o":"Delhi", "dr":"26 Sep - 28 Sep 2026",
  "hn":"Ganga View Homestay", "b":22280, "bx":30000, "co2":38, "u":1790445192,
  "d":[ { "n":1, "dt":"Sat 26 Sep", "w":"31 degC, 20% rain",
          "sl":[ { "k":"visit", "hm":"17:00", "a":1790, "z":1790, "ti":"Ganga Aarti",
                   "c":0, "fl":"Crowded after 17:30", "la":30.1087, "ln":78.2932 } ] } ] }
```

A three-day plan is about 2 KB. `v` is what lets an older watch build refuse a
payload it would only half understand; the server caps the whole thing at 16 KB.
`since` makes the refresh conditional: an unchanged plan costs one `204`.

## What's here

```
garmin/
├── manifest.xml              app id/type/products/permissions
├── monkey.jungle             build config; tests are on the source path
├── build.sh                  sim / device / test wrapper for the CLI tools
├── source/
│   ├── PulseApp.mc           AppBase — entry point, settings, cache, sync
│   ├── TripStore.mc          the trip model and every question about it (no UI)
│   ├── TripClient.mc         the only class that makes a web request
│   ├── Fmt.mc                formatting and geometry, all pure functions
│   ├── PulseView.mc          all drawing; every coordinate from dc.getWidth()
│   ├── PulseDelegate.mc      all input: touch, swipe, five buttons
│   ├── PulseMenu.mc          long-press menu: sync, today, pairing code
│   ├── BgService.mc          the same fetch on a temporal event, app closed
│   └── SamplePlan.mc         a debug-only plan to develop the screens against
├── resources/
│   ├── strings/strings.xml
│   ├── drawables/            launcher.png (65 × 65) + drawables.xml
│   └── settings/             properties.xml + settings.xml (Garmin Connect)
└── tests/TripStoreTest.mc    19 Run No Evil tests, stripped from release builds
```

**`TripStore` and `Fmt` know nothing about the screen.** That is the point of the
split: they are pure logic, so the whole test suite runs in the simulator, and
the view is the only thing that has to be looked at to be checked.

## Using it

| Input | Does |
| --- | --- |
| Swipe left / right | Next / previous page (Next up → Day → Trip) |
| UP / DOWN | Scroll the day's timeline, rolling into the next day; change page elsewhere |
| START | Sync with the phone's plan now |
| Tap the day header, left / right edge | Previous / next day |
| Tap elsewhere on the Day page | Back to today |
| Tap the first page | Sync |
| Long-press UP | Menu: sync now, go to today, read the pairing code |
| BACK | Exit |

**Next up** shows the stop you are in (`NOW`, amber) or the next one (`NEXT`),
its wall-clock time, how long until it starts or ends, and — when the watch has a
fix and the planner resolved the place — how far away it is and in which
direction. **Day** is the timeline, each row railed in its kind's colour, the
current stop highlighted. **Trip** is origin, stay, stops, budget against the
ceiling the traveller gave the planner (amber when over), and CO₂.

The countdown is redrawn every 30 seconds, the day rolls over on its own at
midnight, and the last good plan is cached in `Application.Storage`, so the app
opens on it instantly and keeps working with no phone in range.

## Running it

### 1. One-time setup (~45 minutes)

1. **Java 17+** — `java -version`.
2. **VS Code** + the **Monkey C** extension published by Garmin.
3. The **Connect IQ SDK** (the extension's *Verify Installation* command walks
   you through it), then put it on your PATH:
   ```bash
   export PATH=$PATH:`cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"`/bin
   ```
4. A **developer key** — `openssl genrsa -out developer_key.pem 4096` then
   `openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out
   developer_key.der -nocrypt`, saved at `~/.garmin/developer_key.der`.

### 2. In the simulator

```bash
./build.sh sim      # build and run
./build.sh test     # run the 19 unit tests
./build.sh device   # build a sideloadable bin/UrbanPulse.prg
```

A debug build with no cached plan loads `SamplePlan.mc` — a three-day Rishikesh
trip anchored to today, so `NOW`, `NEXT` and the countdowns are live. That exists
because of the next section.

### 3. A word about the network — this will bite you

**Connect IQ does not send `makeWebRequest` from the watch.** The request is
relayed through Garmin's own servers, which fetch the URL and hand the device a
response it can hold. Two consequences, both of which look like bugs:

* **HTTPS only.** A plain `http://` URL fails with `-1001`, before anything
  leaves the machine.
* **The URL must be publicly reachable.** `localhost`, `127.0.0.1` and a LAN
  address are all fetched *by Garmin*, from Garmin's network, and come back
  `404`. The simulator behaves exactly like the watch here — there is no
  loopback shortcut for development.

So to run the real thing end to end, `server/` has to be reachable over HTTPS.
In development that means a tunnel:

```bash
cd server && npm start                     # :3001
ngrok http 3001                            # or cloudflared tunnel --url http://localhost:3001
```

Then set the watch app's **Urban Pulse server** setting to the `https://…` URL
the tunnel prints, and its **Pairing code** to the one the phone shows. Note that
a tunnel publishes your local server to the internet for as long as it runs.

To put a plan there without running the phone app:

```bash
WATCH_DEMO_SERVER=https://<tunnel-host> WATCH_DEMO_CODE=DEMO42 \
  flutter test test/tools/publish_demo_to_watch_test.dart
```

That builds the same demo itinerary the planner would produce
(`test/fixtures/demo_itinerary.dart`), runs it through the real
`buildWatchPayload`, and publishes it.

### 4. On the watch

`./build.sh device`, then copy `bin/UrbanPulse.prg` to `GARMIN/APPS/` over USB.
Settings live in Garmin Connect → the app → Settings.

Background refresh asks for a temporal event every 30 minutes; the service keeps
its own footprint small deliberately (`BgService.mc` duplicates two trivial
checks rather than reaching into `TripStore`, because the background process is
given its own, much smaller memory budget and loads every class it can reach).
