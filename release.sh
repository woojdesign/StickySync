#!/usr/bin/env bash
#
# Cut a release AND publish it for Sparkle auto-update:
#   build → Developer ID sign → notarize → staple → EdDSA-sign → appcast →
#   GitHub Release (uploads the zip + appcast.xml).
#
# Prerequisites (all one-time, already set up):
#   • notarize.sh's prereqs: Developer ID Application cert + the
#     "StickySync-notary" keychain profile.
#   • A Sparkle EdDSA signing key in the keychain (from `generate_keys`).
#   • gh authenticated for the woojdesign account.
#
# Usage:
#   ./release.sh 0.2.0
#
# The first run is the bootstrap build: install it manually on each Mac. Every
# release after that updates installed copies automatically.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="${1:?usage: ./release.sh <version>   e.g. ./release.sh 0.2.0}"
TAG="v$VERSION"
REPO="woojdesign/StickySync"

# 1. Polished release notes from `git log <last-tag>..HEAD` via `claude -p`,
#    opened in $EDITOR for a final pass.
./scripts/release_notes.sh "$VERSION" --platform mac
CHANGELOG="release-notes/$VERSION.md"
[ -f "$CHANGELOG" ] || { echo "error: $CHANGELOG missing"; exit 1; }

# 2. Build + Developer ID sign + notarize + staple + zip (non-sandboxed, with
#    the Sparkle Info.plist).
./notarize.sh "$VERSION"

BUILD_NUMBER="$(git rev-list --count HEAD)"
ZIP="build/StickySync-$VERSION-$BUILD_NUMBER.zip"
[ -f "$ZIP" ] || { echo "error: expected $ZIP from notarize.sh"; exit 1; }

# 3. EdDSA-sign the update + build the appcast (private key read from keychain).
GEN_APPCAST="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type f -name generate_appcast -path '*artifacts/sparkle*' 2>/dev/null | head -1)"
[ -n "$GEN_APPCAST" ] || { echo "error: Sparkle's generate_appcast not found"; exit 1; }

RELEASES="build/releases"
rm -rf "$RELEASES"; mkdir -p "$RELEASES"
cp "$ZIP" "$RELEASES/"
echo "==> Signing update + generating appcast"
"$GEN_APPCAST" "$RELEASES" --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/"
[ -f "$RELEASES/appcast.xml" ] || { echo "error: appcast.xml not generated"; exit 1; }

# Stable-named copy so .../releases/latest/download/StickySync.zip is a
# permanent download link to share. Made AFTER generate_appcast so it isn't
# picked up as a second appcast entry.
cp "$RELEASES/$(basename "$ZIP")" "$RELEASES/StickySync.zip"

# Friend-facing release notes: polished changelog + install guide.
cat > "$RELEASES/NOTES.md" <<EOF
## What's new in $VERSION

$(cat "$CHANGELOG")

---

## Install StickySync $VERSION

Requires macOS 15.6 or later.

1. **Download:** [StickySync.zip](https://github.com/$REPO/releases/latest/download/StickySync.zip) — always the newest version.
2. **Unzip** (double-click) and drag **StickySync** into your **Applications** folder.
3. **First launch.** macOS is cautious about apps from outside the App Store, so the first open takes a couple of extra clicks:
   - Double-click StickySync. You'll see *"Apple could not verify…"* — click **Done** (not Move to Trash).
   - Open **System Settings → Privacy & Security**, scroll to **Security**, and next to *"StickySync was blocked…"* click **Open Anyway**, then confirm with your password or Touch ID.
   - The app is notarized by Apple — this is just macOS's standard caution for non-App-Store apps, and you only do it once.
4. Done! StickySync lives in your **menu bar**. ⌘N = new note, ⌘L = all notes, ✕ hides a note (reopen it from the menu-bar list).

**Updates** install themselves automatically — no need to come back here.
**Sync** (optional): while signed into iCloud, your notes sync across your own Macs.
EOF

# 4. Publish the GitHub Release. SUFeedURL is .../releases/latest/download/
#    appcast.xml, so the newest release's appcast is always the live feed;
#    StickySync.zip is the stable friend-facing download.
echo "==> Publishing GitHub release $TAG"
gh release create "$TAG" \
    "$RELEASES/$(basename "$ZIP")" \
    "$RELEASES/StickySync.zip" \
    "$RELEASES/appcast.xml" \
    --repo "$REPO" \
    --title "StickySync $VERSION" \
    --notes-file "$RELEASES/NOTES.md"

echo
echo "Released $TAG."
echo "  Feed: https://github.com/$REPO/releases/latest/download/appcast.xml"
echo "  Installed feed-enabled apps will now offer this version automatically."
