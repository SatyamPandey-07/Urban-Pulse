# Urban Pulse — Garmin watch companion

A Connect IQ **watch app** that mirrors the phone, and the phone-side link that
feeds it. Three features, and nothing else:

1. **Next stop** — its title, its time, and its distance when the phone knows one.
2. **Live Mode alerts** — a buzz and one line of text (`leave`, `arrived`,
   `late`, `meal`, `rain`).
3. **SOS** — hold START for 3 seconds; the *phone* does the work and reports back
   what actually happened.

Target device: **fr965** (API 5.2, 454 × 454 round AMOLED). Every coordinate in
the views comes from `dc.getWidth()` / `dc.getHeight()`, so adding a product to
`manifest.xml` needs no code change.

```
garmin/urbanpulse-watch/     the Monkey C watch app
urbanpulse_flutter/lib/services/watch/      the Dart side of the link
urbanpulse_flutter/lib/services/emergency/  contacts + SMS
urbanpulse_flutter/lib/state/sos_controller.dart
urbanpulse_flutter/android/app/src/main/kotlin/com/urbanpulse/app/  Kotlin bridges
urbanpulse_flutter/ios/Runner/Watch/GarminWatchBridge.swift         Swift bridge
```

---

## The honesty rules this code is built around

These are not stylistic preferences; most of the code exists to keep them.

**The watch never shows a number the phone did not send.** With nothing received
it says `Waiting for phone`. A distance the phone omitted stays omitted — it is
never derived on the watch. State older than **5 minutes** is still shown, but
greyed and labelled with its age, because a stop that was right five minutes ago
is worth seeing and worth doubting.

**`sent` means the OS accepted a message. Nothing else may say `sent`.**
The SOS protocol has a separate `prepared` status for "a composer was opened and
the traveller must tap send", and the watch renders it as *"SOS ready on phone"*.
There is a unit test asserting that string does not contain the word "sent".

**A status is never optimistic.** Each of the six `WatchStatus` values comes from
something the Connect IQ SDK actually reported. "Connected but the app is not
confirmed installed" reports `watchAppNotInstalled`, not `connected`.

---

## Protocol (v1)

JSON-like dictionaries. ASCII only, ≤ 60 chars per line of text, each message
< 900 bytes. Both sides ignore a missing, non-numeric, or different `v`.

### phone → watch

| type | payload |
|---|---|
| `state` | `{t:"state", v:1, live:bool, next:{title, at:"HH:MM", dist:metres?}, day:"Day 2"?, ts:epochSec}` |
| `alert` | `{t:"alert", v:1, id, kind:"leave\|arrived\|late\|meal\|rain", text, ts}` |
| `sosAck` | `{t:"sosAck", v:1, status:"countdown\|cancelled\|sent\|prepared\|failed", detail?, secondsLeft?}` |
| `ping` | `{t:"ping", v:1}` — the test buzz in Settings |

### watch → phone

| type | payload |
|---|---|
| `hello` | `{t:"hello", v:1, device, appVersion}` |
| `sos` | `{t:"sos", v:1, ts}` |
| `sosCancel` | `{t:"sosCancel", v:1}` |
| `ack` | `{t:"ack", v:1, id}` |

`late` is the wire value; the Dart enum constant is `runningBehind` because
`late` is a Dart keyword.

### Rate limiting

Enforced on the **phone**, in `WatchMirror`, because a buzz the traveller did not
ask for is worse than a missed line of text:

- no two alerts within **20 s**;
- at most **5 alerts per rolling 5 minutes**;
- the same `kind`+`text` inside **2 minutes** is the same alert, compared *after*
  sanitising;
- a repeated `id` is never re-sent;
- an unchanged `state` is dropped unless 2 minutes have passed (so the watch's
  freshness dot stays meaningful).

The watch keeps its own small ring buffer of the last 8 alert ids, so a
re-delivered alert is acknowledged again but neither shown nor buzzed.

---

## Building the watch app

Requires the Connect IQ SDK (4.x+; **7.4.3 or newer is required by recent fr965
firmware**, and this was built with 9.2.0) and a developer key.

```bash
SDK=~/Library/Application\ Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.2.0-*
cd garmin/urbanpulse-watch

# release build
"$SDK/bin/monkeyc" -f monkey.jungle -d fr965 -o bin/UrbanPulse.prg \
  -y ~/.garmin/developer_key.der -r

# with the unit tests compiled in
"$SDK/bin/monkeyc" -f monkey.jungle -d fr965 -o bin/UrbanPulseTest.prg \
  -y ~/.garmin/developer_key.der -t
```

`tests/` is on the source path for every build; `(:test)` functions are stripped
unless `-t` is given, so the tests cannot silently stop compiling.

### Creating the developer key

```bash
mkdir -p ~/.garmin
openssl genrsa -out ~/.garmin/developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt \
  -in ~/.garmin/developer_key.pem -out ~/.garmin/developer_key.der
```

A Connect IQ developer account is only needed to *publish*: register at
<https://developer.garmin.com/connect-iq/> and upload the `.iq` produced by
`monkeyc -e`. Side-loading needs no account. **The key is gitignored** — it signs
every build, and a leaked one lets someone publish as you.

### Running in the simulator

```bash
"$SDK/bin/connectiq"                                   # start the simulator
"$SDK/bin/monkeydo" bin/UrbanPulse.prg fr965           # run the app
"$SDK/bin/monkeydo" bin/UrbanPulseTest.prg fr965 -t    # run the unit tests
```

### Side-loading to a real fr965

The fr965 exposes **MTP only** — no USB mass storage mode (its USB Mode menu
offers "Garmin" and "MTP"), and macOS has no native MTP support. So:

1. Watch: hold **MENU** → **System** → **USB Mode** → **MTP**.
2. Connect it by USB. **Quit Garmin Express** — it grabs the device.
3. Install [OpenMTP](https://openmtp.ganeshrvel.com/) (`brew install --cask openmtp`).
4. Copy `bin/UrbanPulse.prg` into the watch's **`GARMIN/APPS/`**.
5. Unplug. The watch restarts and the app appears in the app list.

> The bundled `mtp-cli` inside OpenMTP does **not** work with the fr965 — it
> fails with a repeated `drop message … error: vector` session desync against
> Garmin's MTP stack. Use the OpenMTP GUI. `libmtp`'s `mtp-detect` cannot claim
> the interface on macOS at all (`avoid probing device using attached kernel
> interface`).
>
> Unplug any iPhone first: iOS also speaks MTP/PTP, and MTP tools grab whichever
> device they enumerate first.

---

## Background delivery — what each side actually allows

This is the part most easily over-promised, so it is spelled out.

### On the watch

`Communications.registerForPhoneAppMessages` receives only while the app is on
screen. `Background.registerForPhoneAppMessageEvent` additionally wakes a
background service (`BgService.mc`) when the app is closed. That service:

- **buzzes** — the one thing that must happen immediately;
- **stores the payload** and exits, handing it to the app on next open.

What it **cannot** do on any device: show a view. There is no UI from a
background service. So with the app closed the traveller feels the buzz and reads
the text when they next open the app. The glance view (`GlanceView.mc`) shows the
next stop from the watch-face carousel without opening the app.

Registering for background phone events is wrapped in a `try`: a device without
the Background permission granted throws, and that must not break the foreground
half.

### On the phone

| | Android | iOS |
|---|---|---|
| SDK | `com.garmin.connectiq:ciq-companion-app-sdk:2.2.0` (Maven Central) | `ConnectIQ.xcframework` 1.8.0, fetched by script |
| Simulator testing | **yes** — `IQConnectType.TETHERED` + `adb forward tcp:7381 tcp:7381` | **no such mode exists**; needs a real watch + iPhone + Garmin Connect |
| Device discovery | `getKnownDevices()`, silent | `showDeviceSelection()` **app-switches into Garmin Connect**, returns via URL scheme |
| Send SMS for SOS | real send with `SEND_SMS` → `sent` | **impossible**; composer only → `prepared` |
| Watch SOS offered? | yes (default off) | **no** — see below |

**Watch SOS is disabled on iOS on purpose.** No iOS API sends an SMS without the
traveller tapping send, so a wrist SOS could never complete on its own. Rather
than ship a hold-to-send button whose only possible outcome is "now go find your
phone", the toggle is hidden, and if a watch asks anyway the phone replies with a
`sosAck` of `failed` explaining why.

**iOS `.connected` does not mean ready to send.** SDK 1.8 added
`deviceCharacteristicsDiscovered`; until it fires, sends fail. The bridge gates on
it and reports `deviceNotConnected` until then.

**iOS background** is better than it first appears: the SDK's
`stateRestorationIdentifier` overload sets `CBCentralManagerOptionRestoreIdentifierKey`,
which with the `bluetooth-central` background mode lets iOS relaunch the app on
BLE activity from a paired watch. Not verified on hardware here.

---

## Setting up the phone side

### Android

Nothing to fetch — the SDK is a Gradle line in `android/app/build.gradle.kts`.

To test against the **simulator** instead of a watch:

```bash
adb forward tcp:7381 tcp:7381
```

then start the connection from the simulator's **Connection** menu. Tethered mode
needs no Garmin Connect Mobile on the phone.

### iOS

```bash
./urbanpulse_flutter/ios/scripts/fetch_connectiq_sdk.sh
```

This clones Garmin's official SDK repo at a pinned tag and drops
`ConnectIQ.xcframework` into `ios/Frameworks/`. It is **gitignored**: Garmin
distributes it as a binary under its own licence. The Xcode project already links
and embeds it (Embed & Sign) and `Info.plist` already declares the
`urbanpulse-ciq` URL scheme, the `gcm-ciq` query scheme, `bluetooth-central`, and
the Bluetooth usage description.

---

## Manual test checklist

Needs a real fr965 with the app side-loaded and a phone with Garmin Connect.

**Link status** — open Settings → Garmin watch and check each state reads
correctly and distinctly:

- [ ] Garmin Connect not installed → *Garmin Connect app missing*
- [ ] No watch chosen → *No watch paired*; **Choose watch** opens Garmin Connect
      (iOS) and returns with the device
- [ ] Watch out of range → *Not connected*
- [ ] Watch connected, app not side-loaded → *Watch app not installed*
- [ ] App running → *Connected*, and the watch's part number is shown
- [ ] **Send a test buzz** → the watch vibrates; with do-not-disturb on, the text
      still appears and there is no buzz

**Next stop** — start navigation on the Live Map to any place:

- [ ] The watch shows the destination, an arrival clock time, and a distance
- [ ] The distance counts down as you move; the time updates
- [ ] Arriving raises an `ARRIVED` alert and buzzes once
- [ ] Stop navigation → the watch stops showing a stop

**Staleness** — with the state on screen, turn off the phone's Bluetooth:

- [ ] After 5 minutes the text greys and the top line reads e.g. *6 min ago*
- [ ] The connected dot goes hollow
- [ ] Force-quit the app and reopen with no phone → *Waiting for phone*

**Alerts while closed** — press BACK out of the app, then send a test buzz:

- [ ] The watch buzzes with the app closed
- [ ] Opening the app shows the alert text that arrived

**SOS (Android only)** — add at least one emergency contact first:

- [ ] With no contacts, the watch SOS toggle is disabled and says why
- [ ] With the toggle off, holding START gives *SOS failed* and an explanation
- [ ] With it on, hold START 3 s → ring fills, the watch buzzes, *Sent to phone*
- [ ] The phone counts down from 10 and the watch mirrors the seconds
- [ ] **Cancel from the watch** (BACK during the countdown) → *SOS cancelled*,
      and no message is sent
- [ ] **Cancel from the phone** → the watch shows *SOS cancelled*
- [ ] Let it run out with `SEND_SMS` granted → the contacts receive a message with
      a maps link, and the watch shows *SOS sent*
- [ ] Deny `SEND_SMS` → the composer opens pre-filled and the watch shows
      *SOS ready on phone*, **never** *SOS sent*
- [ ] Turn off location, then SOS → the message says the location is unknown, or
      gives the last known fix **with its age**
- [ ] Letting go of the button before 3 s sends nothing

**SOS (iOS)**:

- [ ] The watch SOS toggle is disabled and explains the iOS limitation
- [ ] The in-app SOS button still works and opens the composer

---

## Tests

```bash
# Dart
cd urbanpulse_flutter && flutter analyze && flutter test

# Monkey C
cd garmin/urbanpulse-watch
"$SDK/bin/monkeyc" -f monkey.jungle -d fr965 -o bin/UrbanPulseTest.prg \
  -y ~/.garmin/developer_key.der -t
"$SDK/bin/monkeydo" bin/UrbanPulseTest.prg fr965 -t
```

Monkey C tests cover message parsing (version rejection, wrong types, non-maps),
sanitising and truncation, the alert ring buffer, SOS status validation, the
stale-state rule, and that `prepared` never renders as "sent".

Dart tests cover the same protocol from the other side, plus rate limiting and
dedupe, `WatchStatus` handling, Live Mode mirroring, and the SOS controller
(countdown, cancel from either side, no contacts, no position, SMS unavailable,
and honest acknowledgements).
