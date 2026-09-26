# Urban Pulse Calc — Connect IQ app for the Forerunner 965

A calculator, built as the skeleton for the Urban Pulse watch app. It is a
Connect IQ **device app** (`watch-app`) written in Monkey C, targeting `fr965`
(API level 5.2, 454 × 454 round AMOLED, 786,432 bytes of RAM).

Built to the spec in the build manual:
<https://claude.ai/artifact/KsZfcsJV61gygEhHezaXjp>

## What's here

```
garmin/
├── manifest.xml              app id/type/products/permissions (none yet)
├── monkey.jungle             build config; tests are on the source path
├── build.sh                  sim / device / test wrapper for the CLI tools
├── source/
│   ├── UrbanPulseCalcApp.mc  AppBase — entry point, settings, persistence
│   ├── CalcEngine.mc         tokeniser → shunting-yard → RPN evaluator (no UI)
│   ├── Keypad.mc             the two 4×4 key pages and their labels
│   ├── CalcView.mc           all drawing; every coordinate from dc.getWidth()
│   ├── CalcDelegate.mc       all input: touch, swipe, five buttons
│   ├── SettingsMenu.mc       native Menu2 settings screen
│   └── HistoryView.mc        the last 12 calculations
├── resources/
│   ├── strings/strings.xml
│   ├── drawables/            launcher.png (65 × 65) + drawables.xml
│   └── settings/             properties.xml + settings.xml (Garmin Connect)
└── tests/EngineTest.mc       19 Run No Evil tests, stripped from release builds
```

**The engine knows nothing about the screen.** That is the point of the split:
`CalcEngine` is pure logic, so the whole test suite runs in the simulator, and
when the Urban Pulse API work lands it slots in beside the engine without
touching the view or the delegate.

## Using it

| Input | Does |
| --- | --- |
| Tap a key | Presses it (primary path) |
| Swipe left / right | Switches between the basic and scientific pages |
| UP / DOWN | Moves the key cursor (button-only fallback) |
| START | First press lights the key cursor; after that it presses the highlighted key |
| BACK | Deletes one token — and exits the app only when there is nothing left |
| Long-press UP | Settings: angle mode, vibration, history |

Page 1 is `7 8 9 ÷ / 4 5 6 × / 1 2 3 − / 0 . = +`.
Page 2 is `( ) C DEL / √ x² ^ % / sin cos tan π / ln log ans DEG`.

The result line shows a **live preview** while you type: `2+3` shows `5` before
you press `=`. Everything is computed in `Double` and rounded only at the
display, so `0.1+0.2` is `0.3` and `2+3×4` is `14`, not `20`.

## Running it

### 1. One-time setup (~45 minutes)

1. **Java 17+** — `java -version`.
2. **VS Code** + the **Monkey C** extension published by Garmin.
3. **Connect IQ SDK Manager** from <https://developer.garmin.com/connect-iq/sdk/> —
   sign in with your Garmin account, download **SDK 9.2.0** and set it active,
   then in the **Devices** tab download **Forerunner 965**.
4. In VS Code: `⌘⇧P` → `Monkey C: Verify Installation`, and clear anything it reports.
5. `⌘⇧P` → `Monkey C: Generate a Developer Key`. **Back the key up twice** —
   store updates must be signed with the same key forever.

### 2. Run in the simulator

Open `garmin/` as the VS Code workspace folder, open any `.mc` file from
`source/` (the extension builds whatever project owns the *active file*), then
**Run → Start Debugging** (`F5`) and pick **Forerunner 965**.

If the device list is empty, run `Monkey C: Edit Products` and select Forerunner 965.

### 3. Run the tests

In VS Code: the **Test Explorer** (flask icon) lists all 19 tests — run them there.

`monkey.jungle` puts `tests` on the source path; `(:test)` functions are stripped
from non-test builds. If a device build ever objects to `Toybox.Test`, drop
`;tests` from `base.sourcePath` for that build.

From the command line (SDK on PATH):

```bash
export PATH=$PATH:`cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"`/bin
cd garmin
DEV_KEY=~/path/to/developer_key.der ./build.sh test
```

### 4. Put it on the watch

1. `⌘⇧P` → `Monkey C: Build for Device` → **Forerunner 965** → choose an output folder.
   (Or `DEV_KEY=... ./build.sh device`, which writes `bin/UrbanPulseCalc.prg`.)
2. Connect the FR965 by USB and let it mount.
3. Copy the `.prg` into `GARMIN/APPS/` on the watch.
4. *(optional)* create an empty `GARMIN/APPS/LOGS/URBANPULSECALC.TXT` — without
   that file, `System.println()` on-device writes nowhere.
5. Eject the watch properly, then find **Pulse Calc** under **Activities & Apps**.

macOS does not mount MTP devices in Finder. Newer Garmin firmware presents the
watch as normal USB mass storage; if yours doesn't appear, use Android File
Transfer or a similar MTP client. **Test this before demo day** — it is the most
common last-minute failure.

## One platform rule this app depends on

`BehaviorDelegate` gets behavior events **before** low-level input, and returning
`true` consumes them. A screen tap arrives as `onSelect()` — which has no
coordinates — so `onSelect()` here returns `false` and lets the tap fall through
to `onTap()`, where the keypad hit-testing lives. The physical START button is
handled in `onKey()` (`KEY_ENTER`), the one path a tap never takes. Return `true`
from `onSelect()` and every tap silently does nothing but buzz.

## Check these on real hardware

The simulator hides three things:

- **Glyphs.** `√`, `²` and `π` come from `Keypad.LBL_SQRT`, `LBL_SQUARE` and
  `LBL_PI` at the top of `Keypad.mc`. If any renders as an empty box on your
  firmware, swap in the ASCII fallback in the comment — one line each.
- **Touch targets.** A fingertip is ~45 px; the keys here are ~55–66 px and
  taper with the bezel. Mouse clicks in the simulator are pixel-perfect and will
  hide an undersized key.
- **Legibility** of the dark palette at outdoor brightness.

## Next: the Urban Pulse version

Part 12 of the build manual covers this in full. The short version:

1. Add `<iq:uses-permission id="Communications"/>` to `manifest.xml`.
2. Add a `PulseClient.mc` next to `CalcEngine.mc` — one request in flight,
   `Communications.makeWebRequest`, every negative response code mapped to a
   sentence, last good value cached in `Application.Storage`.
3. Add one watch-shaped endpoint to `server/server.js` (flat JSON, short keys,
   pre-formatted strings, under ~8 KB) so the TomTom and Groq keys stay on the
   server and never reach the watch.
