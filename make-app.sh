#!/usr/bin/env bash
#
# Build a double-clickable StickySync.app from the SwiftPM executable.
#
# The bundle is ad-hoc signed, which is enough to run locally with the JSON
# store. iCloud sync additionally needs a real signing identity and the iCloud
# entitlement — see the README (Phase 2).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="release"
BIN_NAME="StickySync"
APP="$ROOT/$BIN_NAME.app"

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

echo "==> Assembling $BIN_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Ad-hoc signing…"
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
echo "    Run it with:  open \"$APP\""
