#!/usr/bin/env bash
#
# Fetches the Connect IQ Companion App SDK for iOS into ios/Frameworks/.
#
# Garmin distributes this as a binary xcframework under its own licence, so it is
# not committed here (see .gitignore). Run this once after cloning, before
# building the iOS app.
#
#   ./ios/scripts/fetch_connectiq_sdk.sh
#
# Pinned deliberately: a binary dependency that moves under you is worse than one
# you have to bump on purpose.
set -euo pipefail

VERSION="1.8.0"
REPO="https://github.com/garmin/connectiq-companion-app-sdk-ios.git"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ios_dir="$(dirname "$here")"
dest="$ios_dir/Frameworks/ConnectIQ.xcframework"

if [ -d "$dest" ]; then
  echo "ConnectIQ.xcframework already present at:"
  echo "  $dest"
  echo "Delete it and re-run to refresh."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Fetching Connect IQ iOS SDK $VERSION ..."
git clone --quiet --depth 1 --branch "$VERSION" "$REPO" "$tmp/sdk"

if [ ! -d "$tmp/sdk/ConnectIQ.xcframework" ]; then
  echo "ERROR: ConnectIQ.xcframework missing from the $VERSION tag." >&2
  exit 1
fi

mkdir -p "$ios_dir/Frameworks"
cp -R "$tmp/sdk/ConnectIQ.xcframework" "$dest"
# Keep the licence and docs next to the binary they apply to.
cp "$tmp/sdk/README.md" "$ios_dir/Frameworks/ConnectIQ-README.md" 2>/dev/null || true

echo "Installed: $dest"
echo
echo "Next: in Xcode, add ConnectIQ.xcframework to the Runner target under"
echo "  General > Frameworks, Libraries, and Embedded Content"
echo "as 'Embed & Sign'. See garmin/README.md for the full iOS checklist."
