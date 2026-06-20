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

# 1. Build + Developer ID sign + notarize + staple + zip (non-sandboxed, with
#    the Sparkle Info.plist).
./notarize.sh "$VERSION"

BUILD_NUMBER="$(git rev-list --count HEAD)"
ZIP="build/StickySync-$VERSION-$BUILD_NUMBER.zip"
[ -f "$ZIP" ] || { echo "error: expected $ZIP from notarize.sh"; exit 1; }

# 2. EdDSA-sign the update + build the appcast (private key read from keychain).
GEN_APPCAST="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type f -name generate_appcast -path '*artifacts/sparkle*' 2>/dev/null | head -1)"
[ -n "$GEN_APPCAST" ] || { echo "error: Sparkle's generate_appcast not found"; exit 1; }

RELEASES="build/releases"
rm -rf "$RELEASES"; mkdir -p "$RELEASES"
cp "$ZIP" "$RELEASES/"
echo "==> Signing update + generating appcast"
"$GEN_APPCAST" "$RELEASES" --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/"
[ -f "$RELEASES/appcast.xml" ] || { echo "error: appcast.xml not generated"; exit 1; }

# 3. Publish the GitHub Release. SUFeedURL is .../releases/latest/download/
#    appcast.xml, so the newest release's appcast is always the live feed.
echo "==> Publishing GitHub release $TAG"
gh release create "$TAG" \
    "$RELEASES/$(basename "$ZIP")" \
    "$RELEASES/appcast.xml" \
    --repo "$REPO" \
    --title "StickySync $VERSION" \
    --notes "StickySync $VERSION"

echo
echo "Released $TAG."
echo "  Feed: https://github.com/$REPO/releases/latest/download/appcast.xml"
echo "  Installed feed-enabled apps will now offer this version automatically."
