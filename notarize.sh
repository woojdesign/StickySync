#!/usr/bin/env bash
#
# Build → Developer ID sign → notarize → staple → zip a distributable StickySync.
#
# ── One-time setup ──────────────────────────────────────────────────────────
# 1. Have a "Developer ID Application" certificate:
#      Xcode ▸ Settings ▸ Accounts ▸ (your team) ▸ Manage Certificates ▸
#      "+" ▸ Developer ID Application.
# 2. Store notarization credentials in the keychain (so they're never in this
#    file). Use an app-specific password from appleid.apple.com:
#
#      xcrun notarytool store-credentials "StickySync-notary" \
#          --apple-id "you@example.com" \
#          --team-id  BSPX8X9U4B \
#          --password "xxxx-xxxx-xxxx-xxxx"
#
# ── Usage ───────────────────────────────────────────────────────────────────
#      ./notarize.sh 0.2.0          # cut version 0.2.0
#      ./notarize.sh                # use the project's current version
#
set -euo pipefail

# --- config -----------------------------------------------------------------
PROJECT="StickySync/StickySync.xcodeproj"
SCHEME="StickySync"
TEAM_ID="BSPX8X9U4B"
NOTARY_PROFILE="StickySync-notary"     # keychain profile from the setup above
BUILD_DIR="build"
APP_NAME="StickySync.app"
# ----------------------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="${1:-}"                                  # optional marketing version
BUILD_NUMBER="$(git rev-list --count HEAD)"       # monotonic, tied to commits
ARCHIVE="$BUILD_DIR/StickySync.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/$APP_NAME"
LABEL="${VERSION:-dev}-$BUILD_NUMBER"
OUT_ZIP="$BUILD_DIR/StickySync-$LABEL.zip"

echo "==> Clean"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

echo "==> Archive (Release, build $BUILD_NUMBER${VERSION:+, version $VERSION})"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    ENABLE_APP_SANDBOX=NO \
    INFOPLIST_FILE=Info.plist \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    ${VERSION:+MARKETING_VERSION="$VERSION"}

echo "==> Export Developer ID-signed app"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -allowProvisioningUpdates

echo "==> Notarize (uploads and waits for Apple)"
ditto -c -k --keepParent "$APP" "$OUT_ZIP"
xcrun notarytool submit "$OUT_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Staple ticket onto the app"
xcrun stapler staple "$APP"

echo "==> Re-zip the stapled app for distribution"
rm -f "$OUT_ZIP"
ditto -c -k --keepParent "$APP" "$OUT_ZIP"

echo "==> Verify"
spctl -a -t exec -vv "$APP" || true
xcrun stapler validate "$APP" || true

echo
echo "Done."
echo "  app: $APP"
echo "  zip: $OUT_ZIP   ← upload this"
echo
echo "If notarization failed, see why with:"
echo "  xcrun notarytool history --keychain-profile \"$NOTARY_PROFILE\""
echo "  xcrun notarytool log <submission-id> --keychain-profile \"$NOTARY_PROFILE\""
