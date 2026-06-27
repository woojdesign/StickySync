#!/usr/bin/env bash
#
# Cut an iOS TestFlight build:
#   release notes  → polished via claude -p, opened in $EDITOR
#   archive        → xcodebuild archive (Release, generic/iOS)
#   export         → app-store-connect IPA
#   upload         → xcrun altool to App Store Connect
#   set notes      → poll ASC API for VALID, then set "What to Test"
#
# ── One-time setup ──────────────────────────────────────────────────────────
# 1. App Store Connect API key (ASC → Users and Access → Integrations →
#    App Store Connect API → Generate Team Key). Save Issuer ID, Key ID, and
#    the .p8 file, then in your shell rc:
#
#      export ASC_KEY_ID=ABCD123456
#      export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#      export ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_ABCD123456.p8
#
# 2. Python deps:  pip install PyJWT cryptography requests
# 3. ITSAppUsesNonExemptEncryption=NO is set in StickySyncMobile/Info.plist so
#    uploads don't pause on the encryption question.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#      ./testflight.sh 0.3.2
#      ./testflight.sh 0.3.2 --no-edit          # skip the notes editor pass
#      ./testflight.sh 0.3.2 --skip-upload      # build + write notes, don't upload
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# --- args -------------------------------------------------------------------
VERSION="${1:?usage: ./testflight.sh <version> [--no-edit] [--skip-upload]}"
shift
NOTES_FLAGS=()
SKIP_UPLOAD=0
KEEP_NOTES=0
while [ $# -gt 0 ]; do
    case "$1" in
        --no-edit)     NOTES_FLAGS+=(--no-edit); shift ;;
        --skip-upload) SKIP_UPLOAD=1; shift ;;
        --keep-notes)  KEEP_NOTES=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 1 ;;
    esac
done

# --- config -----------------------------------------------------------------
PROJECT="StickySync/StickySync.xcodeproj"
SCHEME="StickySyncMobile"
BUNDLE_ID="wooj.StickySyncMobile"
TEAM_ID="BSPX8X9U4B"
BUILD_DIR="build-ios"
BUILD_NUMBER="$(git rev-list --count HEAD)"
ASC_PYTHON="${ASC_PYTHON:-$HOME/.venvs/stickysync/bin/python3}"
ARCHIVE="$BUILD_DIR/StickySyncMobile.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
NOTES_FILE="release-notes/$VERSION.md"

if [ "$SKIP_UPLOAD" = "0" ]; then
    : "${ASC_KEY_ID:?ASC_KEY_ID not set (see one-time setup in this scripts header)}"
    : "${ASC_ISSUER_ID:?ASC_ISSUER_ID not set}"
    : "${ASC_KEY_PATH:?ASC_KEY_PATH not set}"
fi

# --- 1. release notes -------------------------------------------------------
if [ "$KEEP_NOTES" = "1" ] && [ -f "$NOTES_FILE" ]; then
    echo "==> Using existing $NOTES_FILE ($(wc -c < "$NOTES_FILE" | tr -d ' ') chars)"
else
    echo "==> Generating release notes for $VERSION"
    ./scripts/release_notes.sh "$VERSION" --platform ios "${NOTES_FLAGS[@]}"
fi
[ -f "$NOTES_FILE" ] || { echo "error: $NOTES_FILE missing"; exit 1; }

# xcodebuild's `-allowProvisioningUpdates` needs to authenticate to Apple
# to fetch a fresh distribution provisioning profile. The default auth
# path is the *keychain* (a signed-in Apple ID + cached tokens), which
# can quietly break — keychain rotations, token timeouts, Xcode sign-
# outs we never asked for. Pass the same App Store Connect API key the
# upload step uses so the auth path is single-rooted: if `altool` can
# upload, `xcodebuild` can sign. Required env: ASC_KEY_ID, ASC_ISSUER_ID,
# ASC_KEY_PATH (see CLAUDE.md).
ASC_XCODE_AUTH=()
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ]; then
    ASC_XCODE_AUTH=(
        -authenticationKeyID "$ASC_KEY_ID"
        -authenticationKeyIssuerID "$ASC_ISSUER_ID"
        -authenticationKeyPath "$ASC_KEY_PATH"
    )
fi

# --- 2. archive -------------------------------------------------------------
echo "==> Clean + archive (build $BUILD_NUMBER, version $VERSION)"
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    "${ASC_XCODE_AUTH[@]}" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    MARKETING_VERSION="$VERSION"

# --- 3. export IPA ----------------------------------------------------------
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>stripSwiftSymbols</key><true/>
</dict></plist>
PLIST

echo "==> Export signed IPA"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -allowProvisioningUpdates \
    "${ASC_XCODE_AUTH[@]}"

IPA="$(ls "$EXPORT_DIR"/*.ipa 2>/dev/null | head -1 || true)"
[ -n "$IPA" ] && [ -f "$IPA" ] || { echo "error: no IPA produced in $EXPORT_DIR"; exit 1; }
echo "    IPA: $IPA"

if [ "$SKIP_UPLOAD" = "1" ]; then
    echo
    echo "Skipped upload (--skip-upload). Notes at $NOTES_FILE, IPA at $IPA."
    exit 0
fi

# --- 4. upload --------------------------------------------------------------
echo "==> Upload to App Store Connect"
xcrun altool --upload-app \
    --type ios \
    --file "$IPA" \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID"

# --- 5. set What to Test ----------------------------------------------------
echo "==> Waiting for processing + setting What to Test"
"$ASC_PYTHON" ./scripts/asc_whats_new.py \
    --bundle-id "$BUNDLE_ID" \
    --version   "$VERSION" \
    --build     "$BUILD_NUMBER" \
    --notes-file "$NOTES_FILE"

# --- 6. Keep CLAUDE.md truthful ---------------------------------------------
# Future Claude sessions read "Last shipped" to find the right "since" tag
# and to set expectations. Failures here are non-fatal — the upload itself
# already succeeded.
./scripts/bump_claude_md.sh ios "$VERSION" "$BUILD_NUMBER" || \
    echo "warn: failed to bump CLAUDE.md (upload is shipped — fix manually)"

echo
echo "Uploaded StickySyncMobile $VERSION ($BUILD_NUMBER) to TestFlight."
echo "  • Internal testers can install as soon as processing finishes."
echo "  • External testers: first build needs Beta App Review (24–72h);"
echo "    later builds usually clear in minutes unless something material changes."
