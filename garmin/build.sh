#!/usr/bin/env bash
# Convenience wrapper around the Connect IQ command line tools.
#
#   ./build.sh sim      build and run in the simulator
#   ./build.sh device   build a sideloadable .prg into bin/
#   ./build.sh test     build with unit tests and run them in the simulator
#
# Requires the SDK on PATH:
#   export PATH=$PATH:`cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"`/bin
# and a developer key at the path below (override with DEV_KEY=...).

set -euo pipefail

DEVICE="${DEVICE:-fr965}"
DEV_KEY="${DEV_KEY:-$HOME/.garmin/developer_key.der}"
OUT="bin/UrbanPulse.prg"
MODE="${1:-sim}"

mkdir -p bin

if ! command -v monkeyc >/dev/null 2>&1; then
  echo "monkeyc not on PATH - see README.md, step 1." >&2
  exit 1
fi

if [ ! -f "$DEV_KEY" ]; then
  echo "No developer key at $DEV_KEY - see README.md, step 2." >&2
  exit 1
fi

case "$MODE" in
  test)
    monkeyc -f monkey.jungle -d "$DEVICE" -o "$OUT" -y "$DEV_KEY" -l 1 -w --unit-test
    connectiq &
    sleep 5
    monkeydo "$OUT" "$DEVICE" -t
    ;;
  device)
    monkeyc -f monkey.jungle -d "$DEVICE" -o "$OUT" -y "$DEV_KEY" -l 1 -w -r
    echo "Built $OUT - copy it to GARMIN/APPS/ on the watch."
    ;;
  *)
    monkeyc -f monkey.jungle -d "$DEVICE" -o "$OUT" -y "$DEV_KEY" -l 1 -w
    connectiq &
    sleep 5
    monkeydo "$OUT" "$DEVICE"
    ;;
esac
