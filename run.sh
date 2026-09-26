#!/usr/bin/env bash
# Run Urban Pulse (Flutter) in debug mode on a USB-connected Android phone.
# No APK/release build: `flutter run` does a debug build, installs it and
# attaches for hot reload (r), hot restart (R) and quit (q).
#
# Usage:
#   ./run.sh                # first connected phone
#   ./run.sh <device-id>    # pick a specific device (see `adb devices`)
#   ./run.sh -- --verbose   # anything after -- goes straight to `flutter run`

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$ROOT/urbanpulse_flutter"

# Make flutter available even if it isn't on PATH (SDK lives in ~/flutter).
if ! command -v flutter >/dev/null 2>&1; then
  for sdk in "${FLUTTER_ROOT:-}" "$HOME/flutter" "$HOME/development/flutter" "$HOME/snap/flutter/common/flutter"; do
    if [[ -n "$sdk" && -x "$sdk/bin/flutter" ]]; then
      export PATH="$sdk/bin:$PATH"
      break
    fi
  done
fi
command -v flutter >/dev/null 2>&1 || { echo "flutter not found. Install it or set FLUTTER_ROOT." >&2; exit 1; }
command -v adb >/dev/null 2>&1 || { echo "adb not found. Install android-tools / platform-tools." >&2; exit 1; }

if [[ ! -f "$APP_DIR/pubspec.yaml" ]]; then
  echo "No pubspec.yaml in $APP_DIR - the Flutter sources (pubspec.yaml, lib/) are missing." >&2
  exit 1
fi

DEVICE="${1:-}"
[[ "$DEVICE" == "--" ]] && DEVICE=""
[[ -n "$DEVICE" && "$DEVICE" != -* ]] && shift || DEVICE=""
[[ "${1:-}" == "--" ]] && shift

# Wait for a phone over USB; report the usual failure states clearly.
adb start-server >/dev/null 2>&1 || true
if [[ -z "$DEVICE" ]]; then
  echo "Waiting for a USB device (enable USB debugging, accept the prompt on the phone)..."
  for _ in $(seq 1 30); do
    DEVICE="$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
    [[ -n "$DEVICE" ]] && break
    if adb devices | awk 'NR>1 && $2=="unauthorized" {f=1} END{exit !f}'; then
      echo "Phone is unauthorized - tap 'Allow USB debugging' on the phone."
    fi
    sleep 2
  done
  [[ -n "$DEVICE" ]] || { echo "No authorized device found." >&2; adb devices >&2; exit 1; }
fi
echo "Using device: $DEVICE"

cd "$APP_DIR"
flutter pub get

# API keys / backend URL live in config.json (gitignored, see config.example.json).
DEFINES=()
[[ -f config.json ]] && DEFINES=(--dart-define-from-file=config.json)

exec flutter run --debug -d "$DEVICE" ${DEFINES[@]+"${DEFINES[@]}"} "$@"
